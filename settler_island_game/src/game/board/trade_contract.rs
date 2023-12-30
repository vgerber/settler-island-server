use std::fmt::Debug;

use super::resource::{
    base_resource::ResourcedId,
    player_resources::{get_total_resources, ResourceCollection},
};

pub trait TradeContract {
    fn accepts_offer(&self, receive: ResourceCollection, send: ResourceCollection) -> bool;
}

#[derive(Debug, Clone)]
pub struct AcceptsNAnyTradeContract {
    receive_count: usize,
    send_count: usize,
}

impl AcceptsNAnyTradeContract {
    pub fn new(receive_count: usize, send_count: usize) -> Self {
        if receive_count == 0 || send_count == 0 {
            panic!("Invalid trade contract");
        }

        AcceptsNAnyTradeContract {
            receive_count: receive_count,
            send_count: send_count,
        }
    }
}

impl TradeContract for AcceptsNAnyTradeContract {
    pub fn accepts_offer(&self, receive: ResourceCollection, send: ResourceCollection) -> bool {
        let receive_count = get_total_resources(&receive);
        let send_count = get_total_resources(&send);

        if receive_count == 0 || send_count == 0 {
            return false;
        }

        if receive_count % self.receive_count != 0 {
            return false;
        }

        let trade_times = receive_count / self.receive_count;
        (trade_times * self.send_count) == send_count
    }
}

#[derive(Debug, Clone)]
pub struct AcceptsNSingleResourceTradeContract {
    receive_count: usize,
    send_count: usize,
    resource: ResourcedId,
}

impl AcceptsNSingleResourceTradeContract {
    fn new(receive_count: usize, send_count: usize, resource: ResourcedId) -> Self {
        if receive_count == 0 || send_count == 0 {
            panic!("Invalid trade contract");
        }

        AcceptsNSingleResourceTradeContract {
            receive_count: receive_count,
            send_count: send_count,
            resource: resource,
        }
    }
}

impl TradeContract for AcceptsNSingleResourceTradeContract {
    fn accepts_offer(&self, receive: ResourceCollection, send: ResourceCollection) -> bool {
        let receive_count = get_total_resources(&receive);
        let send_count = get_total_resources(&send);

        if receive_count == 0 || send_count == 0 {
            return false;
        }

        if receive_count % self.receive_count != 0 {
            return false;
        }

        let trade_times = receive_count / self.receive_count;
        let is_ratio_correct = (trade_times * self.send_count) == send_count;
        if !is_ratio_correct {
            return false;
        }

        receive.get(&self.resource).unwrap_or(&0) == &receive_count
    }
}
