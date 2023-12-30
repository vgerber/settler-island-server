use std::rc::Rc;

use crate::game::board::trade_contract::TradeContract;

#[derive(Clone)]
pub struct SeaportLocation {
    trade_contract: Rc<dyn TradeContract>,
}

impl SeaportLocation {
    pub fn new(trade_contract: Rc<dyn TradeContract>) -> Self {
        SeaportLocation {
            trade_contract: trade_contract,
        }
    }

    pub fn get_trade_contract(&self) -> &Rc<dyn TradeContract> {
        &self.trade_contract
    }
}
