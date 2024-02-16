use std::sync::Arc;

use crate::game::board::trade_contract::TradeContract;

#[derive(Clone)]
pub struct SeaportLocation {
    trade_contract: Arc<dyn TradeContract>,
}

impl SeaportLocation {
    pub fn new(trade_contract: Arc<dyn TradeContract>) -> Self {
        SeaportLocation {
            trade_contract: trade_contract,
        }
    }

    pub fn get_trade_contract(&self) -> &Arc<dyn TradeContract> {
        &self.trade_contract
    }
}
