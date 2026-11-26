//! Caps open WebSocket connections in total and per client address; a permit is held for the socket's lifetime.

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex, MutexGuard};

use settler_island_protocol::ServerLimit;

#[derive(Debug)]
pub(crate) struct ConnectionLimiter {
    max_total: usize,
    max_per_address: usize,
    open: Mutex<OpenConnections>,
}

#[derive(Debug, Default)]
struct OpenConnections {
    total: usize,
    /// Only addresses with at least one open connection, so the map cannot grow past `max_total` entries.
    per_address: HashMap<IpAddr, usize>,
}

/// One open connection; dropping it frees the slot.
#[derive(Debug)]
pub(crate) struct ConnectionPermit {
    limiter: Arc<ConnectionLimiter>,
    address: IpAddr,
}

impl ConnectionLimiter {
    pub(crate) fn new(max_total: usize, max_per_address: usize) -> ConnectionLimiter {
        ConnectionLimiter {
            max_total,
            max_per_address,
            open: Mutex::new(OpenConnections::default()),
        }
    }

    pub(crate) fn acquire(
        self: &Arc<Self>,
        address: IpAddr,
    ) -> Result<ConnectionPermit, ServerLimit> {
        let mut open = self.lock();
        if open.total >= self.max_total {
            return Err(ServerLimit::Connections);
        }
        let from_address = open.per_address.get(&address).copied().unwrap_or(0);
        if from_address >= self.max_per_address {
            return Err(ServerLimit::ConnectionsPerIp);
        }
        open.total += 1;
        open.per_address.insert(address, from_address + 1);
        Ok(ConnectionPermit {
            limiter: self.clone(),
            address,
        })
    }

    fn release(&self, address: IpAddr) {
        let mut open = self.lock();
        open.total = open.total.saturating_sub(1);
        let Some(count) = open.per_address.get_mut(&address) else {
            return;
        };
        *count -= 1;
        if *count == 0 {
            open.per_address.remove(&address);
        }
    }

    fn lock(&self) -> MutexGuard<'_, OpenConnections> {
        // A poisoned lock only means another task panicked; the counts are still usable.
        self.open.lock().unwrap_or_else(|error| error.into_inner())
    }
}

impl Drop for ConnectionPermit {
    fn drop(&mut self) {
        self.limiter.release(self.address);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn address(last: u8) -> IpAddr {
        IpAddr::from([10, 0, 0, last])
    }

    #[test]
    fn dropped_permits_free_their_slot_and_forget_the_address() {
        let limiter = Arc::new(ConnectionLimiter::new(3, 2));
        let first = limiter.acquire(address(1)).unwrap();
        let _second = limiter.acquire(address(1)).unwrap();
        assert_eq!(
            limiter.acquire(address(1)).unwrap_err(),
            ServerLimit::ConnectionsPerIp
        );
        let other = limiter.acquire(address(2)).unwrap();
        assert_eq!(
            limiter.acquire(address(3)).unwrap_err(),
            ServerLimit::Connections
        );

        drop(first);
        drop(other);

        assert!(!limiter.lock().per_address.contains_key(&address(2)));
        assert!(limiter.acquire(address(1)).is_ok());
    }
}
