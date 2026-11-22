use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Above this many tracked addresses, idle ones are dropped so the map cannot grow without bound.
const PRUNE_ABOVE: usize = 10_000;

#[derive(Debug)]
struct Bucket {
    tokens: f64,
    updated: Instant,
}

/// A token bucket per client address: `burst` requests at once, refilled at `per_minute`.
#[derive(Debug)]
pub(crate) struct IpLimiter {
    per_minute: u32,
    burst: u32,
    buckets: Mutex<HashMap<IpAddr, Bucket>>,
}

impl IpLimiter {
    pub(crate) fn new(per_minute: u32, burst: u32) -> IpLimiter {
        IpLimiter {
            per_minute,
            burst,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// `Err` carries how long until a token is free.
    pub(crate) fn check(&self, address: IpAddr, now: Instant) -> Result<(), Duration> {
        let per_second = f64::from(self.per_minute) / 60.0;
        let capacity = f64::from(self.burst);
        // A poisoned lock only means another request panicked; the counts are still usable.
        let mut buckets = self
            .buckets
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if buckets.len() > PRUNE_ABOVE {
            buckets.retain(|_, bucket| {
                let idle = now.duration_since(bucket.updated).as_secs_f64();
                bucket.tokens + idle * per_second < capacity
            });
        }
        let bucket = buckets.entry(address).or_insert(Bucket {
            tokens: capacity,
            updated: now,
        });
        let elapsed = now.duration_since(bucket.updated).as_secs_f64();
        bucket.tokens = (bucket.tokens + elapsed * per_second).min(capacity);
        bucket.updated = now;
        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0;
            return Ok(());
        }
        let missing = 1.0 - bucket.tokens;
        Err(Duration::from_secs_f64(
            missing / per_second.max(f64::MIN_POSITIVE),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn address(last: u8) -> IpAddr {
        IpAddr::from([10, 0, 0, last])
    }

    #[test]
    fn burst_then_refill_per_address() {
        let limiter = IpLimiter::new(10, 5);
        let start = Instant::now();

        assert!((0..5).all(|_| limiter.check(address(1), start).is_ok()));
        let retry = limiter.check(address(1), start).unwrap_err();
        assert!(retry <= Duration::from_secs(6) && retry > Duration::from_secs(5));
        assert!(limiter.check(address(2), start).is_ok());
        let later = start + Duration::from_secs(6);
        assert!(limiter.check(address(1), later).is_ok());
        assert!(limiter.check(address(1), later).is_err());
    }
}
