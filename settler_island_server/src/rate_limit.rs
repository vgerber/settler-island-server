use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Above this many tracked addresses, idle ones are dropped so the map cannot grow without bound.
const PRUNE_ABOVE: usize = 10_000;

/// One token bucket: `capacity` actions at once, refilled at `per_second`.
#[derive(Debug)]
pub(crate) struct TokenBucket {
    per_second: f64,
    capacity: f64,
    tokens: f64,
    updated: Instant,
}

impl TokenBucket {
    pub(crate) fn new(per_second: f64, capacity: u32, now: Instant) -> TokenBucket {
        TokenBucket {
            per_second,
            capacity: f64::from(capacity),
            tokens: f64::from(capacity),
            updated: now,
        }
    }

    fn refilled(&self, now: Instant) -> f64 {
        let elapsed = now.saturating_duration_since(self.updated).as_secs_f64();
        (self.tokens + elapsed * self.per_second).min(self.capacity)
    }

    fn is_full(&self, now: Instant) -> bool {
        self.refilled(now) >= self.capacity
    }

    /// `Err` carries how long until a token is free.
    pub(crate) fn take(&mut self, now: Instant) -> Result<(), Duration> {
        self.tokens = self.refilled(now);
        self.updated = now;
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            return Ok(());
        }
        let missing = 1.0 - self.tokens;
        Err(Duration::from_secs_f64(
            missing / self.per_second.max(f64::MIN_POSITIVE),
        ))
    }
}

/// A token bucket per client address: `burst` requests at once, refilled at `per_minute`.
#[derive(Debug)]
pub(crate) struct IpLimiter {
    per_minute: u32,
    burst: u32,
    buckets: Mutex<HashMap<IpAddr, TokenBucket>>,
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
        // A poisoned lock only means another request panicked; the counts are still usable.
        let mut buckets = self
            .buckets
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if buckets.len() > PRUNE_ABOVE {
            buckets.retain(|_, bucket| !bucket.is_full(now));
        }
        buckets
            .entry(address)
            .or_insert_with(|| TokenBucket::new(f64::from(self.per_minute) / 60.0, self.burst, now))
            .take(now)
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

    #[test]
    fn bucket_allows_the_burst_then_reports_retry_after() {
        let start = Instant::now();
        let mut bucket = TokenBucket::new(2.0, 3, start);

        assert!((0..3).all(|_| bucket.take(start).is_ok()));
        assert_eq!(bucket.take(start).unwrap_err(), Duration::from_millis(500));
    }

    #[test]
    fn bucket_refills_gradually_and_never_above_capacity() {
        let start = Instant::now();
        let mut bucket = TokenBucket::new(2.0, 3, start);
        assert!((0..3).all(|_| bucket.take(start).is_ok()));

        let later = start + Duration::from_millis(500);
        assert!(bucket.take(later).is_ok());
        assert!(bucket.take(later).is_err());
        let much_later = later + Duration::from_secs(3600);
        assert!((0..3).all(|_| bucket.take(much_later).is_ok()));
        assert!(bucket.take(much_later).is_err());
    }
}
