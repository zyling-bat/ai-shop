//! 交易域状态机：订单（02 §2.13①）。
//!
//! 只表达「状态 × 动作」的合法迁移，不含业务规则（金额、库存、权限）。
//! 数据库 `"order".status` 列的 CHECK 枚举与本模块枚举取值必须一致。
//!
//! 与 02 §2.13① 的两处口径（已与用户确认，见 `specs/ST-1.6.md` §7 决策点 3）：
//! - `after_sale → after_sale_done` 文档写「回原状态或 completed」；本模块统一落 `completed`，
//!   「回原状态」所需的前态由 P6 售后逻辑自行保留，不进入状态机签名。
//! - 文档未列 `partially_shipped` 的继续发货箭头，本模块严格照表，不补 `ship_all/ship_part`。

/// 非法状态迁移。
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("非法状态迁移：{state} 不接受动作 {action}")]
pub struct InvalidTransition {
    /// 迁移前的状态。
    pub state: &'static str,
    /// 被拒绝的动作。
    pub action: &'static str,
}

/// 订单状态机（02 §2.13①）。
///
/// 合法路径：`created → pending_pay → paid → shipped/partially_shipped → received → completed`；
/// 另有 `pending_pay → cancelled`、`paid/shipped/received → after_sale → completed`，
/// 以及非终态任意状态 `force_close → closed`。
pub mod order {
    use super::InvalidTransition;

    /// 订单状态。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Status {
        /// 已创建（待库存预占）。
        Created,
        /// 待支付。
        PendingPay,
        /// 已支付。
        Paid,
        /// 部分发货。
        PartiallyShipped,
        /// 已全部发货。
        Shipped,
        /// 已收货。
        Received,
        /// 售后中。
        AfterSale,
        /// 已完成。
        Completed,
        /// 已取消。
        Cancelled,
        /// 已关闭（运营强制关单）。
        Closed,
    }

    impl Status {
        /// 与 `"order".status` 列取值一致的字符串。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::Created => "created",
                Self::PendingPay => "pending_pay",
                Self::Paid => "paid",
                Self::PartiallyShipped => "partially_shipped",
                Self::Shipped => "shipped",
                Self::Received => "received",
                Self::AfterSale => "after_sale",
                Self::Completed => "completed",
                Self::Cancelled => "cancelled",
                Self::Closed => "closed",
            }
        }

        /// 是否终态（不再接受任何动作）。
        pub const fn is_terminal(self) -> bool {
            matches!(self, Self::Completed | Self::Cancelled | Self::Closed)
        }

        /// 执行一次迁移，非法组合返回 [`InvalidTransition`]。
        pub fn transition(self, action: Action) -> Result<Self, InvalidTransition> {
            use Action as A;
            use Status as S;
            match (self, action) {
                (S::Created, A::ReserveOk) => Ok(S::PendingPay),
                (S::PendingPay, A::PaySuccess) => Ok(S::Paid),
                (S::PendingPay, A::Cancel | A::Timeout) => Ok(S::Cancelled),
                (S::Paid, A::ShipAll) => Ok(S::Shipped),
                (S::Paid, A::ShipPart) => Ok(S::PartiallyShipped),
                (S::Shipped | S::PartiallyShipped, A::ReceiveAll) => Ok(S::Received),
                (S::Received, A::AutoComplete | A::Confirm) => Ok(S::Completed),
                (S::Paid | S::Shipped | S::Received, A::ApplyAfterSale) => Ok(S::AfterSale),
                (S::AfterSale, A::AfterSaleDone) => Ok(S::Completed),
                (_, A::ForceClose) if !self.is_terminal() => Ok(S::Closed),
                _ => Err(InvalidTransition {
                    state: self.as_str(),
                    action: action.as_str(),
                }),
            }
        }
    }

    /// 订单动作。
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Action {
        /// 库存预占成功。
        ReserveOk,
        /// 支付成功。
        PaySuccess,
        /// 用户取消。
        Cancel,
        /// 支付超时。
        Timeout,
        /// 全部发货。
        ShipAll,
        /// 部分发货。
        ShipPart,
        /// 全部收货。
        ReceiveAll,
        /// 自动确认收货。
        AutoComplete,
        /// 用户确认收货。
        Confirm,
        /// 发起售后。
        ApplyAfterSale,
        /// 售后完成。
        AfterSaleDone,
        /// 运营强制关单。
        ForceClose,
    }

    impl Action {
        /// 动作名称，用于错误信息。
        pub const fn as_str(self) -> &'static str {
            match self {
                Self::ReserveOk => "reserve_ok",
                Self::PaySuccess => "pay_success",
                Self::Cancel => "cancel",
                Self::Timeout => "timeout",
                Self::ShipAll => "ship_all",
                Self::ShipPart => "ship_part",
                Self::ReceiveAll => "receive_all",
                Self::AutoComplete => "auto_complete",
                Self::Confirm => "confirm",
                Self::ApplyAfterSale => "apply_after_sale",
                Self::AfterSaleDone => "after_sale_done",
                Self::ForceClose => "force_close",
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{Action, Status};

        const ALL_STATUSES: [Status; 10] = [
            Status::Created,
            Status::PendingPay,
            Status::Paid,
            Status::PartiallyShipped,
            Status::Shipped,
            Status::Received,
            Status::AfterSale,
            Status::Completed,
            Status::Cancelled,
            Status::Closed,
        ];

        const ALL_ACTIONS: [Action; 12] = [
            Action::ReserveOk,
            Action::PaySuccess,
            Action::Cancel,
            Action::Timeout,
            Action::ShipAll,
            Action::ShipPart,
            Action::ReceiveAll,
            Action::AutoComplete,
            Action::Confirm,
            Action::ApplyAfterSale,
            Action::AfterSaleDone,
            Action::ForceClose,
        ];

        const LEGAL: [(Status, Action, Status); 21] = [
            (Status::Created, Action::ReserveOk, Status::PendingPay),
            (Status::PendingPay, Action::PaySuccess, Status::Paid),
            (Status::PendingPay, Action::Cancel, Status::Cancelled),
            (Status::PendingPay, Action::Timeout, Status::Cancelled),
            (Status::Paid, Action::ShipAll, Status::Shipped),
            (Status::Paid, Action::ShipPart, Status::PartiallyShipped),
            (Status::Shipped, Action::ReceiveAll, Status::Received),
            (
                Status::PartiallyShipped,
                Action::ReceiveAll,
                Status::Received,
            ),
            (Status::Received, Action::AutoComplete, Status::Completed),
            (Status::Received, Action::Confirm, Status::Completed),
            (Status::Paid, Action::ApplyAfterSale, Status::AfterSale),
            (Status::Shipped, Action::ApplyAfterSale, Status::AfterSale),
            (Status::Received, Action::ApplyAfterSale, Status::AfterSale),
            (Status::AfterSale, Action::AfterSaleDone, Status::Completed),
            (Status::Created, Action::ForceClose, Status::Closed),
            (Status::PendingPay, Action::ForceClose, Status::Closed),
            (Status::Paid, Action::ForceClose, Status::Closed),
            (Status::PartiallyShipped, Action::ForceClose, Status::Closed),
            (Status::Shipped, Action::ForceClose, Status::Closed),
            (Status::Received, Action::ForceClose, Status::Closed),
            (Status::AfterSale, Action::ForceClose, Status::Closed),
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
        fn pay_success_only_from_pending_pay() {
            for status in ALL_STATUSES {
                let result = status.transition(Action::PaySuccess);
                if status == Status::PendingPay {
                    assert_eq!(result, Ok(Status::Paid));
                } else {
                    assert!(result.is_err(), "{status:?} 不应允许支付成功");
                }
            }
        }

        #[test]
        fn terminal_states_reject_all_actions() {
            for status in [Status::Completed, Status::Cancelled, Status::Closed] {
                assert!(status.is_terminal(), "{status:?} 应为终态");
                for action in ALL_ACTIONS {
                    assert!(
                        status.transition(action).is_err(),
                        "{status:?} 是终态，不应接受 {:?}",
                        action
                    );
                }
            }
        }

        #[test]
        fn after_sale_done_goes_to_completed() {
            assert_eq!(
                Status::AfterSale.transition(Action::AfterSaleDone),
                Ok(Status::Completed)
            );
            for status in ALL_STATUSES {
                if status != Status::AfterSale {
                    assert!(
                        status.transition(Action::AfterSaleDone).is_err(),
                        "{status:?} 不在售后中，不应接受 after_sale_done"
                    );
                }
            }
        }

        #[test]
        fn partially_shipped_cannot_ship_again() {
            assert!(
                Status::PartiallyShipped
                    .transition(Action::ShipAll)
                    .is_err(),
                "严格照 02 §2.13①，未列部分发货后再发货"
            );
            assert!(
                Status::PartiallyShipped
                    .transition(Action::ShipPart)
                    .is_err(),
                "严格照 02 §2.13①，未列部分发货后再发货"
            );
        }
    }
}
