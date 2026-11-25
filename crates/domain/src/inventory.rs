//! 库存与供应链状态机：采购单、调拨单、盘点单（02 §2.13 ⑧⑨⑩）。
//!
//! 每套状态机只表达「状态 × 动作」的合法迁移，不含业务规则（数量、金额、权限）。
//! 数据库 `status` 列的 CHECK 枚举与本模块枚举取值必须一致。

/// 非法状态迁移。
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("非法状态迁移：{state} 不接受动作 {action}")]
pub struct InvalidTransition {
    /// 迁移前的状态。
    pub state: &'static str,
    /// 被拒绝的动作。
    pub action: &'static str,
}

/// 采购单状态机（02 §2.13⑧）。
///
/// 合法路径：`draft → approving → approved → ordered → partially_received → received → settled → closed`，
/// 另有 `approved → cancelled`；取消只允许在 `approved`。
pub mod purchase_order {
    use super::InvalidTransition;

    /// 采购单状态。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Status {
        /// 草稿。
        Draft,
        /// 审批中。
        Approving,
        /// 已审批。
        Approved,
        /// 已下单。
        Ordered,
        /// 部分收货。
        PartiallyReceived,
        /// 已收货。
        Received,
        /// 已结算。
        Settled,
        /// 已关闭。
        Closed,
        /// 已取消。
        Cancelled,
    }

    impl Status {
        /// 与 `purchase_order.status` 列取值一致的字符串。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Draft => "draft",
                Self::Approving => "approving",
                Self::Approved => "approved",
                Self::Ordered => "ordered",
                Self::PartiallyReceived => "partially_received",
                Self::Received => "received",
                Self::Settled => "settled",
                Self::Closed => "closed",
                Self::Cancelled => "cancelled",
            }
        }

        /// 执行一次迁移，非法组合返回 [`InvalidTransition`]。
        pub fn transition(self, action: Action) -> Result<Self, InvalidTransition> {
            use Action as A;
            use Status as S;
            match (self, action) {
                (S::Draft, A::Submit) => Ok(S::Approving),
                (S::Approving, A::Approve) => Ok(S::Approved),
                (S::Approved, A::Order) => Ok(S::Ordered),
                (S::Ordered, A::ReceivePartial) | (S::PartiallyReceived, A::ReceivePartial) => {
                    Ok(S::PartiallyReceived)
                }
                (S::PartiallyReceived, A::ReceiveAll) => Ok(S::Received),
                (S::Received, A::Settle) => Ok(S::Settled),
                (S::Settled, A::Close) => Ok(S::Closed),
                (S::Approved, A::Cancel) => Ok(S::Cancelled),
                _ => Err(InvalidTransition {
                    state: self.as_str(),
                    action: action.as_str(),
                }),
            }
        }
    }

    /// 采购单动作。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Action {
        /// 提交审批。
        Submit,
        /// 审批通过。
        Approve,
        /// 向供应商下单。
        Order,
        /// 部分收货。
        ReceivePartial,
        /// 收齐剩余数量。
        ReceiveAll,
        /// 结算。
        Settle,
        /// 关闭。
        Close,
        /// 取消。
        Cancel,
    }

    impl Action {
        /// 动作名称，用于错误信息。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Submit => "submit",
                Self::Approve => "approve",
                Self::Order => "order",
                Self::ReceivePartial => "receive_partial",
                Self::ReceiveAll => "receive_all",
                Self::Settle => "settle",
                Self::Close => "close",
                Self::Cancel => "cancel",
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{Action, Status};

        const ALL_STATUSES: [Status; 9] = [
            Status::Draft,
            Status::Approving,
            Status::Approved,
            Status::Ordered,
            Status::PartiallyReceived,
            Status::Received,
            Status::Settled,
            Status::Closed,
            Status::Cancelled,
        ];

        const ALL_ACTIONS: [Action; 8] = [
            Action::Submit,
            Action::Approve,
            Action::Order,
            Action::ReceivePartial,
            Action::ReceiveAll,
            Action::Settle,
            Action::Close,
            Action::Cancel,
        ];

        const LEGAL: [(Status, Action, Status); 9] = [
            (Status::Draft, Action::Submit, Status::Approving),
            (Status::Approving, Action::Approve, Status::Approved),
            (Status::Approved, Action::Order, Status::Ordered),
            (
                Status::Ordered,
                Action::ReceivePartial,
                Status::PartiallyReceived,
            ),
            (
                Status::PartiallyReceived,
                Action::ReceivePartial,
                Status::PartiallyReceived,
            ),
            (
                Status::PartiallyReceived,
                Action::ReceiveAll,
                Status::Received,
            ),
            (Status::Received, Action::Settle, Status::Settled),
            (Status::Settled, Action::Close, Status::Closed),
            (Status::Approved, Action::Cancel, Status::Cancelled),
        ];

        #[test]
        fn legal_transitions_all_pass() {
            for (from, action, to) in LEGAL {
                assert_eq!(
                    from.transition(action),
                    Ok(to),
                    "合法迁移被拒绝：{:?} --{:?}-->",
                    from,
                    action
                );
            }
        }

        #[test]
        fn illegal_transitions_all_rejected() {
            for from in ALL_STATUSES {
                for action in ALL_ACTIONS {
                    if LEGAL.iter().any(|(f, a, _)| *f == from && *a == action) {
                        continue;
                    }
                    let err = from.transition(action).expect_err("非法组合必须被拒绝");
                    assert_eq!(err.state, from.as_str());
                    assert_eq!(err.action, action.as_str());
                }
            }
        }

        #[test]
        fn cancel_only_allowed_when_approved() {
            for status in ALL_STATUSES {
                let result = status.transition(Action::Cancel);
                if status == Status::Approved {
                    assert_eq!(result, Ok(Status::Cancelled));
                } else {
                    assert!(result.is_err(), "{status:?} 不应允许取消");
                }
            }
        }
    }
}

/// 调拨单状态机（02 §2.13⑨）。
///
/// 合法路径：`created → approved → outbound → in_transit → inbound → completed`；
/// 取消只允许在出库前（`created` / `approved`）。
pub mod transfer_order {
    use super::InvalidTransition;

    /// 调拨单状态。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Status {
        /// 已创建。
        Created,
        /// 已审批。
        Approved,
        /// 已出库。
        Outbound,
        /// 在途。
        InTransit,
        /// 已入库。
        Inbound,
        /// 已完成。
        Completed,
        /// 已取消。
        Cancelled,
    }

    impl Status {
        /// 与 `transfer_order.status` 列取值一致的字符串。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Created => "created",
                Self::Approved => "approved",
                Self::Outbound => "outbound",
                Self::InTransit => "in_transit",
                Self::Inbound => "inbound",
                Self::Completed => "completed",
                Self::Cancelled => "cancelled",
            }
        }

        /// 执行一次迁移，非法组合返回 [`InvalidTransition`]。
        pub fn transition(self, action: Action) -> Result<Self, InvalidTransition> {
            use Action as A;
            use Status as S;
            match (self, action) {
                (S::Created, A::Approve) => Ok(S::Approved),
                (S::Approved, A::Outbound) => Ok(S::Outbound),
                (S::Outbound, A::Ship) => Ok(S::InTransit),
                (S::InTransit, A::Inbound) => Ok(S::Inbound),
                (S::Inbound, A::Complete) => Ok(S::Completed),
                (S::Created | S::Approved, A::Cancel) => Ok(S::Cancelled),
                _ => Err(InvalidTransition {
                    state: self.as_str(),
                    action: action.as_str(),
                }),
            }
        }
    }

    /// 调拨单动作。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Action {
        /// 审批通过。
        Approve,
        /// 出库。
        Outbound,
        /// 发运（进入在途）。
        Ship,
        /// 到仓入库。
        Inbound,
        /// 完成。
        Complete,
        /// 取消。
        Cancel,
    }

    impl Action {
        /// 动作名称，用于错误信息。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Approve => "approve",
                Self::Outbound => "outbound",
                Self::Ship => "ship",
                Self::Inbound => "inbound",
                Self::Complete => "complete",
                Self::Cancel => "cancel",
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{Action, Status};

        const ALL_STATUSES: [Status; 7] = [
            Status::Created,
            Status::Approved,
            Status::Outbound,
            Status::InTransit,
            Status::Inbound,
            Status::Completed,
            Status::Cancelled,
        ];

        const ALL_ACTIONS: [Action; 6] = [
            Action::Approve,
            Action::Outbound,
            Action::Ship,
            Action::Inbound,
            Action::Complete,
            Action::Cancel,
        ];

        const LEGAL: [(Status, Action, Status); 7] = [
            (Status::Created, Action::Approve, Status::Approved),
            (Status::Approved, Action::Outbound, Status::Outbound),
            (Status::Outbound, Action::Ship, Status::InTransit),
            (Status::InTransit, Action::Inbound, Status::Inbound),
            (Status::Inbound, Action::Complete, Status::Completed),
            (Status::Created, Action::Cancel, Status::Cancelled),
            (Status::Approved, Action::Cancel, Status::Cancelled),
        ];

        #[test]
        fn legal_transitions_all_pass() {
            for (from, action, to) in LEGAL {
                assert_eq!(
                    from.transition(action),
                    Ok(to),
                    "合法迁移被拒绝：{:?} --{:?}-->",
                    from,
                    action
                );
            }
        }

        #[test]
        fn illegal_transitions_all_rejected() {
            for from in ALL_STATUSES {
                for action in ALL_ACTIONS {
                    if LEGAL.iter().any(|(f, a, _)| *f == from && *a == action) {
                        continue;
                    }
                    let err = from.transition(action).expect_err("非法组合必须被拒绝");
                    assert_eq!(err.state, from.as_str());
                    assert_eq!(err.action, action.as_str());
                }
            }
        }

        #[test]
        fn cancel_rejected_after_outbound() {
            for status in [
                Status::Outbound,
                Status::InTransit,
                Status::Inbound,
                Status::Completed,
            ] {
                assert!(
                    status.transition(Action::Cancel).is_err(),
                    "{status:?} 已出库，不应允许取消"
                );
            }
        }
    }
}

/// 盘点单状态机（02 §2.13⑩）。
///
/// 合法路径：`created → counting → submitted → reviewed → adjusted → closed`；
/// 差异必须经 `reviewed → adjusted` 生成 `stock_log` 调整流水。
pub mod stock_count {
    use super::InvalidTransition;

    /// 盘点单状态。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Status {
        /// 已创建。
        Created,
        /// 盘点中。
        Counting,
        /// 已提交。
        Submitted,
        /// 已复核。
        Reviewed,
        /// 已调整。
        Adjusted,
        /// 已关闭。
        Closed,
    }

    impl Status {
        /// 与 `stock_count.status` 列取值一致的字符串。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Created => "created",
                Self::Counting => "counting",
                Self::Submitted => "submitted",
                Self::Reviewed => "reviewed",
                Self::Adjusted => "adjusted",
                Self::Closed => "closed",
            }
        }

        /// 执行一次迁移，非法组合返回 [`InvalidTransition`]。
        pub fn transition(self, action: Action) -> Result<Self, InvalidTransition> {
            use Action as A;
            use Status as S;
            match (self, action) {
                (S::Created, A::StartCounting) => Ok(S::Counting),
                (S::Counting, A::Submit) => Ok(S::Submitted),
                (S::Submitted, A::Review) => Ok(S::Reviewed),
                (S::Reviewed, A::Adjust) => Ok(S::Adjusted),
                (S::Adjusted, A::Close) => Ok(S::Closed),
                _ => Err(InvalidTransition {
                    state: self.as_str(),
                    action: action.as_str(),
                }),
            }
        }
    }

    /// 盘点单动作。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Action {
        /// 开始盘点。
        StartCounting,
        /// 提交盘点结果。
        Submit,
        /// 复核。
        Review,
        /// 按差异调整库存。
        Adjust,
        /// 关闭。
        Close,
    }

    impl Action {
        /// 动作名称，用于错误信息。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::StartCounting => "start_counting",
                Self::Submit => "submit",
                Self::Review => "review",
                Self::Adjust => "adjust",
                Self::Close => "close",
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{Action, Status};

        const ALL_STATUSES: [Status; 6] = [
            Status::Created,
            Status::Counting,
            Status::Submitted,
            Status::Reviewed,
            Status::Adjusted,
            Status::Closed,
        ];

        const ALL_ACTIONS: [Action; 5] = [
            Action::StartCounting,
            Action::Submit,
            Action::Review,
            Action::Adjust,
            Action::Close,
        ];

        const LEGAL: [(Status, Action, Status); 5] = [
            (Status::Created, Action::StartCounting, Status::Counting),
            (Status::Counting, Action::Submit, Status::Submitted),
            (Status::Submitted, Action::Review, Status::Reviewed),
            (Status::Reviewed, Action::Adjust, Status::Adjusted),
            (Status::Adjusted, Action::Close, Status::Closed),
        ];

        #[test]
        fn legal_transitions_all_pass() {
            for (from, action, to) in LEGAL {
                assert_eq!(
                    from.transition(action),
                    Ok(to),
                    "合法迁移被拒绝：{:?} --{:?}-->",
                    from,
                    action
                );
            }
        }

        #[test]
        fn illegal_transitions_all_rejected() {
            for from in ALL_STATUSES {
                for action in ALL_ACTIONS {
                    if LEGAL.iter().any(|(f, a, _)| *f == from && *a == action) {
                        continue;
                    }
                    let err = from.transition(action).expect_err("非法组合必须被拒绝");
                    assert_eq!(err.state, from.as_str());
                    assert_eq!(err.action, action.as_str());
                }
            }
        }

        #[test]
        fn adjust_must_follow_review() {
            for status in [Status::Created, Status::Counting, Status::Submitted] {
                assert!(
                    status.transition(Action::Adjust).is_err(),
                    "{status:?} 未经复核不应允许调整"
                );
            }
            assert_eq!(
                Status::Reviewed.transition(Action::Adjust),
                Ok(Status::Adjusted)
            );
        }
    }
}
