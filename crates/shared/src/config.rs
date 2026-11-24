//! 启动期配置：从键值对装载并集中校验。
//!
//! 设计要点：
//! - 只做数据与校验，不直接读环境（`from_env` 是薄封装），便于单测。
//! - 一次收集全部问题再返回，避免"改一个、启动一次"的往返（06 §6.4）。
//! - `DATABASE_URL` / `REDIS_URL` / `JWT_SECRET` 为强制必填；其余密钥类配置在
//!   消费它们的 ST 里转为必填。连接串中的密码在错误信息与 `Debug` 中一律脱敏（C28）。

use std::collections::BTreeMap;
use std::fmt;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};

use thiserror::Error;

/// 监听地址默认值（06 §6.4 未列出该变量，按 ST-0.1 既有行为固化）。
pub const DEFAULT_BIND_ADDR: &str = "0.0.0.0:8080";
/// 日志过滤默认值（06 §6.4）。
pub const DEFAULT_LOG_FILTER: &str = "info,sqlx=warn";
/// `JWT_SECRET` 最小字节数（06 §6.4）。
pub const MIN_JWT_SECRET_BYTES: usize = 32;
/// access token 默认有效期（06 §6.4）。
pub const DEFAULT_JWT_ACCESS_TTL_SEC: u64 = 900;
/// refresh token 默认有效期（06 §6.4）。
pub const DEFAULT_JWT_REFRESH_TTL_SEC: u64 = 1_209_600;
/// 数据库连接池默认上限（06 §6.4）。
pub const DEFAULT_DATABASE_MAX_CONNECTIONS: u32 = 20;
/// OTel 服务名默认值。
pub const DEFAULT_OTEL_SERVICE_NAME: &str = "ecom-server";
/// 请求体上限默认值：2 MiB。
pub const DEFAULT_HTTP_BODY_LIMIT_BYTES: u32 = 2_097_152;
/// 请求处理超时默认值（秒）。
pub const DEFAULT_HTTP_TIMEOUT_SECS: u64 = 30;

/// 运行环境。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppEnv {
    Dev,
    Test,
    Prod,
}

impl AppEnv {
    /// 稳定的字符串表示，用于日志与错误信息。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Dev => "dev",
            Self::Test => "test",
            Self::Prod => "prod",
        }
    }
}

/// 日志输出格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogFormat {
    Pretty,
    Json,
}

impl LogFormat {
    /// 稳定的字符串表示，用于日志与错误信息。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pretty => "pretty",
            Self::Json => "json",
        }
    }
}

/// 日志配置：`RUST_LOG` 过滤串与输出格式。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogConfig {
    pub filter: String,
    pub format: LogFormat,
}

impl LogConfig {
    /// 从环境变量装载（宽松模式，供 tracing 初始化先行使用）。
    pub fn from_env() -> Self {
        Self::from_map(&std::env::vars().collect())
    }

    /// 从键值集合以宽松模式装载：非法值回退默认，不阻塞日志出口。
    ///
    /// 严格校验在 [`AppConfig::from_map`] 中完成，二者共用同一套解析函数。
    pub fn from_map(vars: &BTreeMap<String, String>) -> Self {
        let mut issues = Vec::new();
        let app_env = parse_app_env(vars, &mut issues);
        let filter = match lookup(vars, "RUST_LOG") {
            Some(value) => value.to_owned(),
            None => DEFAULT_LOG_FILTER.to_owned(),
        };
        let format = parse_log_format(vars, app_env, &mut issues);
        Self { filter, format }
    }
}

/// JWT 配置。`Debug` 手写实现，确保密钥不进入日志（C28）。
#[derive(Clone, PartialEq, Eq)]
pub struct JwtConfig {
    secret: String,
    pub access_ttl_sec: u64,
    pub refresh_ttl_sec: u64,
}

impl JwtConfig {
    /// 构造配置；长度校验由 [`AppConfig::from_map`] 负责。
    pub fn new(secret: impl Into<String>, access_ttl_sec: u64, refresh_ttl_sec: u64) -> Self {
        Self {
            secret: secret.into(),
            access_ttl_sec,
            refresh_ttl_sec,
        }
    }

    /// 取出密钥原文；仅在签名/验签处调用，禁止写日志。
    pub fn secret(&self) -> &str {
        &self.secret
    }
}

impl fmt::Debug for JwtConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("JwtConfig")
            .field("secret", &"<redacted>")
            .field("access_ttl_sec", &self.access_ttl_sec)
            .field("refresh_ttl_sec", &self.refresh_ttl_sec)
            .finish()
    }
}

/// PostgreSQL 配置。`Debug` 手写实现，连接串密码不进入日志（C28）。
#[derive(Clone, PartialEq, Eq)]
pub struct DatabaseConfig {
    url: String,
    pub max_connections: u32,
}

impl DatabaseConfig {
    /// 构造配置；URL 格式校验由 [`AppConfig::from_map`] 负责。
    pub fn new(url: impl Into<String>, max_connections: u32) -> Self {
        Self {
            url: url.into(),
            max_connections,
        }
    }

    /// 取出连接串原文；仅在建立连接池时调用，禁止写日志。
    pub fn url(&self) -> &str {
        &self.url
    }
}

impl fmt::Debug for DatabaseConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DatabaseConfig")
            .field("url", &redact_url(&self.url))
            .field("max_connections", &self.max_connections)
            .finish()
    }
}

/// Redis 配置。`Debug` 手写实现，连接串密码不进入日志（C28）。
#[derive(Clone, PartialEq, Eq)]
pub struct RedisConfig {
    url: String,
}

impl RedisConfig {
    /// 构造配置；URL 格式校验由 [`AppConfig::from_map`] 负责。
    pub fn new(url: impl Into<String>) -> Self {
        Self { url: url.into() }
    }

    /// 取出连接串原文；仅在建立连接池时调用，禁止写日志。
    pub fn url(&self) -> &str {
        &self.url
    }
}

impl fmt::Debug for RedisConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RedisConfig")
            .field("url", &redact_url(&self.url))
            .finish()
    }
}

/// 遥测配置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TelemetryConfig {
    pub service_name: String,
    /// 为空表示不安装 OTLP 导出器（trace 仍在本地生成，见 ADR-008）。
    pub otlp_endpoint: Option<String>,
}

impl TelemetryConfig {
    /// 从环境变量以宽松模式装载，供订阅器先行装配。
    ///
    /// 严格校验在 [`AppConfig::from_map`] 中完成；非法端点在此按未配置处理，
    /// 保证配置错误仍能通过已装配的日志出口打印出来。
    pub fn from_env() -> Self {
        Self::from_map(&std::env::vars().collect())
    }

    /// 从键值集合以宽松模式装载。
    pub fn from_map(vars: &BTreeMap<String, String>) -> Self {
        let service_name = match lookup(vars, "OTEL_SERVICE_NAME") {
            Some(raw) if raw.chars().any(char::is_whitespace) => {
                DEFAULT_OTEL_SERVICE_NAME.to_owned()
            }
            Some(raw) => raw.to_owned(),
            None => DEFAULT_OTEL_SERVICE_NAME.to_owned(),
        };
        let otlp_endpoint = lookup(vars, "OTEL_EXPORTER_OTLP_ENDPOINT")
            .filter(|raw| is_connection_url(raw, &["http", "https"]))
            .map(str::to_owned);
        Self {
            service_name,
            otlp_endpoint,
        }
    }
}

/// HTTP 请求护栏配置：请求体上限、处理超时与跨域白名单。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpConfig {
    pub body_limit_bytes: u32,
    pub timeout_secs: u64,
    /// 允许的跨域来源；为空表示不放行任何跨域来源。
    pub cors_allowed_origins: Vec<String>,
}

impl Default for HttpConfig {
    fn default() -> Self {
        Self {
            body_limit_bytes: DEFAULT_HTTP_BODY_LIMIT_BYTES,
            timeout_secs: DEFAULT_HTTP_TIMEOUT_SECS,
            cors_allowed_origins: Vec::new(),
        }
    }
}

/// 将连接串中的密码替换为 `***`，用于错误信息与 `Debug`。
///
/// 只处理 `scheme://userinfo@rest` 形式；无 userinfo 或无密码时原样返回。
pub fn redact_url(raw: &str) -> String {
    let Some((scheme, rest)) = raw.split_once("://") else {
        return raw.to_owned();
    };
    let Some((userinfo, host)) = rest.split_once('@') else {
        return raw.to_owned();
    };
    let masked = match userinfo.split_once(':') {
        Some((user, _)) => format!("{user}:***"),
        None => userinfo.to_owned(),
    };
    format!("{scheme}://{masked}@{host}")
}

/// 应用启动配置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppConfig {
    pub app_env: AppEnv,
    pub bind_addr: SocketAddr,
    pub log: LogConfig,
    pub jwt: JwtConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub telemetry: TelemetryConfig,
    pub http: HttpConfig,
}

impl AppConfig {
    /// 从环境变量装载并严格校验。
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_map(&std::env::vars().collect())
    }

    /// 从键值集合装载并严格校验；失败时返回**全部**问题。
    pub fn from_map(vars: &BTreeMap<String, String>) -> Result<Self, ConfigError> {
        let mut issues = Vec::new();
        let app_env = parse_app_env(vars, &mut issues);
        let bind_addr = parse_bind_addr(vars, &mut issues);
        let log = LogConfig {
            filter: match lookup(vars, "RUST_LOG") {
                Some(value) => value.to_owned(),
                None => DEFAULT_LOG_FILTER.to_owned(),
            },
            format: parse_log_format(vars, app_env, &mut issues),
        };
        let jwt = parse_jwt(vars, &mut issues);
        let database = parse_database(vars, &mut issues);
        let redis = parse_redis(vars, &mut issues);
        let telemetry = parse_telemetry(vars, &mut issues);
        let http = parse_http(vars, &mut issues);

        if issues.is_empty() {
            Ok(Self {
                app_env,
                bind_addr,
                log,
                jwt,
                database,
                redis,
                telemetry,
                http,
            })
        } else {
            Err(ConfigError { issues })
        }
    }
}

/// 单条配置问题。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigIssue {
    /// 必填项缺失。
    Missing {
        key: &'static str,
        hint: &'static str,
    },
    /// 长度不足（如密钥）。
    TooShort {
        key: &'static str,
        min_bytes: usize,
        actual_bytes: usize,
    },
    /// 值非法（枚举、地址、数字等）。
    Invalid {
        key: &'static str,
        value: String,
        expected: &'static str,
    },
}

impl ConfigIssue {
    /// 出问题的配置键，便于调用方按变量聚合打印。
    pub const fn key(&self) -> &'static str {
        match self {
            Self::Missing { key, .. } | Self::TooShort { key, .. } | Self::Invalid { key, .. } => {
                key
            }
        }
    }
}

impl fmt::Display for ConfigIssue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Missing { key, hint } => write!(f, "{key} 缺失（必填，{hint}）"),
            Self::TooShort {
                key,
                min_bytes,
                actual_bytes,
            } => write!(
                f,
                "{key} 长度不足：要求 ≥{min_bytes} 字节，实际 {actual_bytes} 字节"
            ),
            Self::Invalid {
                key,
                value,
                expected,
            } => write!(f, "{key}={value} 非法：要求 {expected}"),
        }
    }
}

/// 配置校验失败的聚合错误。
#[derive(Debug, Error)]
#[error("配置校验失败（{} 项问题）", .issues.len())]
pub struct ConfigError {
    pub issues: Vec<ConfigIssue>,
}

/// 读取非空值；空白字符串视为未设置，便于 compose 里留空占位。
fn lookup<'a>(vars: &'a BTreeMap<String, String>, key: &str) -> Option<&'a str> {
    vars.get(key)
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
}

fn parse_app_env(vars: &BTreeMap<String, String>, issues: &mut Vec<ConfigIssue>) -> AppEnv {
    match lookup(vars, "APP_ENV") {
        None | Some("dev") => AppEnv::Dev,
        Some("test") => AppEnv::Test,
        Some("prod") => AppEnv::Prod,
        Some(other) => {
            issues.push(ConfigIssue::Invalid {
                key: "APP_ENV",
                value: other.to_owned(),
                expected: "dev|test|prod",
            });
            AppEnv::Dev
        }
    }
}

fn default_log_format(app_env: AppEnv) -> LogFormat {
    match app_env {
        AppEnv::Prod => LogFormat::Json,
        AppEnv::Dev | AppEnv::Test => LogFormat::Pretty,
    }
}

fn parse_log_format(
    vars: &BTreeMap<String, String>,
    app_env: AppEnv,
    issues: &mut Vec<ConfigIssue>,
) -> LogFormat {
    match lookup(vars, "LOG_FORMAT") {
        None => default_log_format(app_env),
        Some("pretty") => LogFormat::Pretty,
        Some("json") => LogFormat::Json,
        Some(other) => {
            issues.push(ConfigIssue::Invalid {
                key: "LOG_FORMAT",
                value: other.to_owned(),
                expected: "pretty|json",
            });
            default_log_format(app_env)
        }
    }
}

fn parse_bind_addr(vars: &BTreeMap<String, String>, issues: &mut Vec<ConfigIssue>) -> SocketAddr {
    let default = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 8080);
    match lookup(vars, "SERVER_BIND_ADDR") {
        None => default,
        Some(raw) => match raw.parse::<SocketAddr>() {
            Ok(addr) => addr,
            Err(_) => {
                issues.push(ConfigIssue::Invalid {
                    key: "SERVER_BIND_ADDR",
                    value: raw.to_owned(),
                    expected: "IP:PORT，例如 0.0.0.0:8080",
                });
                default
            }
        },
    }
}

fn parse_ttl(
    vars: &BTreeMap<String, String>,
    key: &'static str,
    default: u64,
    issues: &mut Vec<ConfigIssue>,
) -> u64 {
    match lookup(vars, key) {
        None => default,
        Some(raw) => match raw.parse::<u64>() {
            Ok(0) | Err(_) => {
                issues.push(ConfigIssue::Invalid {
                    key,
                    value: raw.to_owned(),
                    expected: "正整数（秒）",
                });
                default
            }
            Ok(value) => value,
        },
    }
}

fn parse_jwt(vars: &BTreeMap<String, String>, issues: &mut Vec<ConfigIssue>) -> JwtConfig {
    let secret = match lookup(vars, "JWT_SECRET") {
        None => {
            issues.push(ConfigIssue::Missing {
                key: "JWT_SECRET",
                hint: "随机字符串，≥32 字节",
            });
            String::new()
        }
        Some(raw) if raw.len() < MIN_JWT_SECRET_BYTES => {
            issues.push(ConfigIssue::TooShort {
                key: "JWT_SECRET",
                min_bytes: MIN_JWT_SECRET_BYTES,
                actual_bytes: raw.len(),
            });
            String::new()
        }
        Some(raw) => raw.to_owned(),
    };

    let access_ttl_sec = parse_ttl(
        vars,
        "JWT_ACCESS_TTL_SEC",
        DEFAULT_JWT_ACCESS_TTL_SEC,
        issues,
    );
    let refresh_ttl_sec = parse_ttl(
        vars,
        "JWT_REFRESH_TTL_SEC",
        DEFAULT_JWT_REFRESH_TTL_SEC,
        issues,
    );
    if refresh_ttl_sec <= access_ttl_sec {
        issues.push(ConfigIssue::Invalid {
            key: "JWT_REFRESH_TTL_SEC",
            value: refresh_ttl_sec.to_string(),
            expected: "大于 JWT_ACCESS_TTL_SEC",
        });
    }

    JwtConfig::new(secret, access_ttl_sec, refresh_ttl_sec)
}

fn parse_positive_u32(
    vars: &BTreeMap<String, String>,
    key: &'static str,
    default: u32,
    issues: &mut Vec<ConfigIssue>,
) -> u32 {
    match lookup(vars, key) {
        None => default,
        Some(raw) => match raw.parse::<u32>() {
            Ok(0) | Err(_) => {
                issues.push(ConfigIssue::Invalid {
                    key,
                    value: raw.to_owned(),
                    expected: "正整数",
                });
                default
            }
            Ok(value) => value,
        },
    }
}

/// 连接串只做协议与形态校验，不解析主机细节（解析交给驱动）。
fn is_connection_url(raw: &str, schemes: &[&str]) -> bool {
    let Some((scheme, rest)) = raw.split_once("://") else {
        return false;
    };
    schemes.contains(&scheme)
        && !rest.is_empty()
        && !rest.chars().any(char::is_whitespace)
        && rest.chars().any(|c| c != '/')
}

fn parse_database(
    vars: &BTreeMap<String, String>,
    issues: &mut Vec<ConfigIssue>,
) -> DatabaseConfig {
    let url = match lookup(vars, "DATABASE_URL") {
        None => {
            issues.push(ConfigIssue::Missing {
                key: "DATABASE_URL",
                hint: "postgres://user:pass@host:5432/db",
            });
            String::new()
        }
        Some(raw) if !is_connection_url(raw, &["postgres", "postgresql"]) => {
            issues.push(ConfigIssue::Invalid {
                key: "DATABASE_URL",
                value: redact_url(raw),
                expected: "postgres:// 或 postgresql:// 开头的连接串",
            });
            String::new()
        }
        Some(raw) => raw.to_owned(),
    };
    let max_connections = parse_positive_u32(
        vars,
        "DATABASE_MAX_CONNECTIONS",
        DEFAULT_DATABASE_MAX_CONNECTIONS,
        issues,
    );
    DatabaseConfig::new(url, max_connections)
}

fn parse_redis(vars: &BTreeMap<String, String>, issues: &mut Vec<ConfigIssue>) -> RedisConfig {
    let url = match lookup(vars, "REDIS_URL") {
        None => {
            issues.push(ConfigIssue::Missing {
                key: "REDIS_URL",
                hint: "redis://host:6379/0",
            });
            String::new()
        }
        Some(raw) if !is_connection_url(raw, &["redis", "rediss"]) => {
            issues.push(ConfigIssue::Invalid {
                key: "REDIS_URL",
                value: redact_url(raw),
                expected: "redis:// 或 rediss:// 开头的连接串",
            });
            String::new()
        }
        Some(raw) => raw.to_owned(),
    };
    RedisConfig::new(url)
}

fn parse_telemetry(
    vars: &BTreeMap<String, String>,
    issues: &mut Vec<ConfigIssue>,
) -> TelemetryConfig {
    let service_name = match lookup(vars, "OTEL_SERVICE_NAME") {
        None => DEFAULT_OTEL_SERVICE_NAME.to_owned(),
        Some(raw) if raw.chars().any(char::is_whitespace) => {
            issues.push(ConfigIssue::Invalid {
                key: "OTEL_SERVICE_NAME",
                value: raw.to_owned(),
                expected: "非空且不含空白字符",
            });
            DEFAULT_OTEL_SERVICE_NAME.to_owned()
        }
        Some(raw) => raw.to_owned(),
    };

    let otlp_endpoint = match lookup(vars, "OTEL_EXPORTER_OTLP_ENDPOINT") {
        None => None,
        Some(raw) if !is_connection_url(raw, &["http", "https"]) => {
            issues.push(ConfigIssue::Invalid {
                key: "OTEL_EXPORTER_OTLP_ENDPOINT",
                value: redact_url(raw),
                expected: "http:// 或 https:// 开头的 OTLP 端点",
            });
            None
        }
        Some(raw) => Some(raw.to_owned()),
    };

    TelemetryConfig {
        service_name,
        otlp_endpoint,
    }
}

fn parse_http(vars: &BTreeMap<String, String>, issues: &mut Vec<ConfigIssue>) -> HttpConfig {
    let body_limit_bytes = parse_positive_u32(
        vars,
        "HTTP_BODY_LIMIT_BYTES",
        DEFAULT_HTTP_BODY_LIMIT_BYTES,
        issues,
    );
    let timeout_secs = parse_ttl(vars, "HTTP_TIMEOUT_SECS", DEFAULT_HTTP_TIMEOUT_SECS, issues);
    let cors_allowed_origins = parse_cors_origins(vars, issues);

    HttpConfig {
        body_limit_bytes,
        timeout_secs,
        cors_allowed_origins,
    }
}

fn parse_cors_origins(
    vars: &BTreeMap<String, String>,
    issues: &mut Vec<ConfigIssue>,
) -> Vec<String> {
    let Some(raw) = lookup(vars, "CORS_ALLOWED_ORIGINS") else {
        return Vec::new();
    };

    let mut origins = Vec::new();
    let mut invalid = Vec::new();
    for origin in raw
        .split(',')
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        if is_connection_url(origin, &["http", "https"]) && !origin.contains('*') {
            origins.push(origin.to_owned());
        } else {
            invalid.push(origin.to_owned());
        }
    }

    if !invalid.is_empty() {
        issues.push(ConfigIssue::Invalid {
            key: "CORS_ALLOWED_ORIGINS",
            value: invalid.join(","),
            expected: "逗号分隔的 http(s) 来源列表，例如 https://app.example.com",
        });
    }

    origins
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 32 字节测试密钥。
    const SECRET: &str = "0123456789abcdef0123456789abcdef";
    /// 测试用数据库连接串（密码故意可识别，便于断言脱敏）。
    const DATABASE_URL: &str = "postgres://app:db-pass-123@127.0.0.1:5432/app";
    /// 测试用 Redis 连接串。
    const REDIS_URL: &str = "redis://127.0.0.1:6379/0";

    /// 构造键值集合；未显式覆盖时补上必填依赖，聚焦被测变量。
    fn vars(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        let mut map: BTreeMap<String, String> = pairs
            .iter()
            .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
            .collect();
        map.entry("DATABASE_URL".to_owned())
            .or_insert_with(|| DATABASE_URL.to_owned());
        map.entry("REDIS_URL".to_owned())
            .or_insert_with(|| REDIS_URL.to_owned());
        map
    }

    #[test]
    fn defaults_apply_with_only_secret() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)]))
            .expect("仅设置 JWT_SECRET 时应装载成功");

        assert_eq!(config.app_env, AppEnv::Dev);
        assert_eq!(config.bind_addr.to_string(), DEFAULT_BIND_ADDR);
        assert_eq!(config.log.filter, DEFAULT_LOG_FILTER);
        assert_eq!(config.log.format, LogFormat::Pretty);
        assert_eq!(config.jwt.access_ttl_sec, DEFAULT_JWT_ACCESS_TTL_SEC);
        assert_eq!(config.jwt.refresh_ttl_sec, DEFAULT_JWT_REFRESH_TTL_SEC);
        assert_eq!(config.jwt.secret(), SECRET);
    }

    #[test]
    fn missing_secret_is_reported() {
        let error = AppConfig::from_map(&vars(&[])).expect_err("缺少 JWT_SECRET 必须失败");
        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].key(), "JWT_SECRET");
        assert!(matches!(
            error.issues[0],
            ConfigIssue::Missing {
                key: "JWT_SECRET",
                ..
            }
        ));
        assert!(error.to_string().contains("1 项问题"));
    }

    #[test]
    fn short_secret_is_reported() {
        let short = "x".repeat(MIN_JWT_SECRET_BYTES - 1);
        let error = AppConfig::from_map(&vars(&[("JWT_SECRET", &short)]))
            .expect_err("不足 32 字节必须失败");

        assert_eq!(
            error.issues[0],
            ConfigIssue::TooShort {
                key: "JWT_SECRET",
                min_bytes: MIN_JWT_SECRET_BYTES,
                actual_bytes: MIN_JWT_SECRET_BYTES - 1,
            }
        );
        assert!(
            !error.to_string().contains(&short),
            "错误信息不得回显密钥原文"
        );
    }

    #[test]
    fn issues_are_aggregated() {
        let error = AppConfig::from_map(&vars(&[("SERVER_BIND_ADDR", "not-an-addr")]))
            .expect_err("缺密钥 + 非法地址必须失败");

        assert_eq!(error.issues.len(), 2, "两个问题应一次返回");
        assert_eq!(error.issues[0].key(), "SERVER_BIND_ADDR");
        assert_eq!(error.issues[1].key(), "JWT_SECRET");
    }

    #[test]
    fn invalid_bind_addr_is_reported() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("SERVER_BIND_ADDR", "0.0.0.0"),
        ]))
        .expect_err("缺少端口必须失败");

        assert!(matches!(
            error.issues[0],
            ConfigIssue::Invalid {
                key: "SERVER_BIND_ADDR",
                ..
            }
        ));
    }

    #[test]
    fn invalid_app_env_and_log_format_are_reported() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("APP_ENV", "staging"),
            ("LOG_FORMAT", "xml"),
        ]))
        .expect_err("非法枚举必须失败");

        assert_eq!(error.issues.len(), 2);
        assert_eq!(error.issues[0].key(), "APP_ENV");
        assert_eq!(error.issues[1].key(), "LOG_FORMAT");
    }

    #[test]
    fn blank_values_are_treated_as_absent() {
        let config = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("SERVER_BIND_ADDR", "  "),
            ("RUST_LOG", ""),
        ]))
        .expect("空白值应按未设置处理");

        assert_eq!(config.bind_addr.to_string(), DEFAULT_BIND_ADDR);
        assert_eq!(config.log.filter, DEFAULT_LOG_FILTER);
    }

    #[test]
    fn prod_defaults_to_json_log() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET), ("APP_ENV", "prod")]))
            .expect("prod 环境装载成功");

        assert_eq!(config.app_env, AppEnv::Prod);
        assert_eq!(config.log.format, LogFormat::Json);
    }

    #[test]
    fn refresh_ttl_must_exceed_access_ttl() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("JWT_ACCESS_TTL_SEC", "900"),
            ("JWT_REFRESH_TTL_SEC", "900"),
        ]))
        .expect_err("refresh 不大于 access 必须失败");

        assert_eq!(error.issues.len(), 1);
        assert!(matches!(
            error.issues[0],
            ConfigIssue::Invalid {
                key: "JWT_REFRESH_TTL_SEC",
                ..
            }
        ));
    }

    #[test]
    fn zero_ttl_is_rejected() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("JWT_ACCESS_TTL_SEC", "0"),
        ]))
        .expect_err("TTL 为 0 必须失败");

        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].key(), "JWT_ACCESS_TTL_SEC");
    }

    #[test]
    fn debug_redacts_secret() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)])).expect("配置装载成功");
        let text = format!("{config:?}");

        assert!(!text.contains(SECRET), "Debug 不得泄漏密钥");
        assert!(text.contains("<redacted>"));
    }

    #[test]
    fn lenient_log_config_falls_back_on_invalid_value() {
        let log = LogConfig::from_map(&vars(&[("LOG_FORMAT", "xml")]));

        assert_eq!(log.format, LogFormat::Pretty);
        assert_eq!(log.filter, DEFAULT_LOG_FILTER);
    }

    #[test]
    fn lenient_log_config_reads_env_values() {
        let log = LogConfig::from_map(&vars(&[
            ("LOG_FORMAT", "json"),
            ("RUST_LOG", "debug"),
            ("APP_ENV", "prod"),
        ]));

        assert_eq!(log.format, LogFormat::Json);
        assert_eq!(log.filter, "debug");
    }

    #[test]
    fn missing_dependencies_are_reported() {
        let mut map = BTreeMap::new();
        map.insert("JWT_SECRET".to_owned(), SECRET.to_owned());

        let error = AppConfig::from_map(&map).expect_err("缺少 DB/Redis 连接串必须失败");
        let keys: Vec<_> = error.issues.iter().map(ConfigIssue::key).collect();
        assert_eq!(keys, vec!["DATABASE_URL", "REDIS_URL"]);
    }

    #[test]
    fn invalid_database_url_is_redacted() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("DATABASE_URL", "mysql://app:db-pass-123@127.0.0.1/app"),
        ]))
        .expect_err("非 postgres 协议必须失败");

        assert!(matches!(
            error.issues[0],
            ConfigIssue::Invalid {
                key: "DATABASE_URL",
                ..
            }
        ));
        let text = error.issues[0].to_string();
        assert!(text.contains("***"), "错误信息应脱敏：{text}");
        assert!(
            !text.contains("db-pass-123"),
            "错误信息不得回显密码：{text}"
        );
    }

    #[test]
    fn invalid_redis_url_is_reported() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("REDIS_URL", "http://127.0.0.1:6379"),
        ]))
        .expect_err("非 redis 协议必须失败");

        assert!(matches!(
            error.issues[0],
            ConfigIssue::Invalid {
                key: "REDIS_URL",
                ..
            }
        ));
    }

    #[test]
    fn database_defaults_apply() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)])).expect("配置装载成功");

        assert_eq!(config.database.url(), DATABASE_URL);
        assert_eq!(
            config.database.max_connections,
            DEFAULT_DATABASE_MAX_CONNECTIONS
        );
        assert_eq!(config.redis.url(), REDIS_URL);
    }

    #[test]
    fn zero_max_connections_is_rejected() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("DATABASE_MAX_CONNECTIONS", "0"),
        ]))
        .expect_err("连接数为 0 必须失败");

        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].key(), "DATABASE_MAX_CONNECTIONS");
    }

    #[test]
    fn debug_redacts_connection_passwords() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)])).expect("配置装载成功");
        let text = format!("{config:?}");

        assert!(text.contains("***"), "Debug 应体现脱敏标记：{text}");
        assert!(
            !text.contains("db-pass-123"),
            "Debug 不得泄漏数据库密码：{text}"
        );
    }

    #[test]
    fn redact_url_keeps_urls_without_credentials() {
        assert_eq!(
            redact_url("redis://127.0.0.1:6379/0"),
            "redis://127.0.0.1:6379/0"
        );
        assert_eq!(
            redact_url("postgres://app:pw@db:5432/app"),
            "postgres://app:***@db:5432/app"
        );
    }

    #[test]
    fn telemetry_defaults_apply() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)])).expect("配置装载成功");

        assert_eq!(config.telemetry.service_name, DEFAULT_OTEL_SERVICE_NAME);
        assert_eq!(config.telemetry.otlp_endpoint, None);
    }

    #[test]
    fn otlp_endpoint_without_scheme_is_rejected() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("OTEL_EXPORTER_OTLP_ENDPOINT", "127.0.0.1:4317"),
        ]))
        .expect_err("缺少 scheme 必须失败");

        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].key(), "OTEL_EXPORTER_OTLP_ENDPOINT");
    }

    #[test]
    fn otlp_endpoint_accepts_http() {
        let config = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:4317"),
        ]))
        .expect("合法端点应装载成功");

        assert_eq!(
            config.telemetry.otlp_endpoint.as_deref(),
            Some("http://127.0.0.1:4317")
        );
    }

    #[test]
    fn blank_otlp_endpoint_means_disabled() {
        let config = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("OTEL_EXPORTER_OTLP_ENDPOINT", "  "),
        ]))
        .expect("空白端点应按未配置处理");

        assert_eq!(config.telemetry.otlp_endpoint, None);
    }

    #[test]
    fn http_guard_defaults_apply() {
        let config = AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET)])).expect("配置装载成功");

        assert_eq!(config.http.body_limit_bytes, DEFAULT_HTTP_BODY_LIMIT_BYTES);
        assert_eq!(config.http.timeout_secs, DEFAULT_HTTP_TIMEOUT_SECS);
        assert!(config.http.cors_allowed_origins.is_empty());
    }

    #[test]
    fn cors_origins_are_split_and_trimmed() {
        let config = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            (
                "CORS_ALLOWED_ORIGINS",
                " https://app.example.com , http://localhost:3000 ",
            ),
        ]))
        .expect("合法来源应装载成功");

        assert_eq!(
            config.http.cors_allowed_origins,
            vec![
                "https://app.example.com".to_owned(),
                "http://localhost:3000".to_owned()
            ]
        );
    }

    #[test]
    fn invalid_cors_origin_is_rejected() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("CORS_ALLOWED_ORIGINS", "https://ok.example.com,*"),
        ]))
        .expect_err("通配来源必须失败");

        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].key(), "CORS_ALLOWED_ORIGINS");
    }

    #[test]
    fn zero_body_limit_is_rejected() {
        let error = AppConfig::from_map(&vars(&[
            ("JWT_SECRET", SECRET),
            ("HTTP_BODY_LIMIT_BYTES", "0"),
        ]))
        .expect_err("请求体上限为 0 必须失败");

        assert_eq!(error.issues[0].key(), "HTTP_BODY_LIMIT_BYTES");
    }

    #[test]
    fn zero_timeout_is_rejected() {
        let error =
            AppConfig::from_map(&vars(&[("JWT_SECRET", SECRET), ("HTTP_TIMEOUT_SECS", "0")]))
                .expect_err("超时为 0 必须失败");

        assert_eq!(error.issues[0].key(), "HTTP_TIMEOUT_SECS");
    }

    #[test]
    fn lenient_telemetry_ignores_invalid_endpoint() {
        let telemetry = TelemetryConfig::from_map(&vars(&[
            ("OTEL_EXPORTER_OTLP_ENDPOINT", "127.0.0.1:4317"),
            ("OTEL_SERVICE_NAME", "bad name"),
        ]));

        assert_eq!(telemetry.otlp_endpoint, None);
        assert_eq!(telemetry.service_name, DEFAULT_OTEL_SERVICE_NAME);
    }
}
