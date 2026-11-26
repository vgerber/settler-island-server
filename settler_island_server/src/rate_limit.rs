use std::collections::HashMap;
use std::net::{IpAddr, Ipv6Addr};
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

/// The address a client is rate limited by: IPv6 clients share one bucket per /64 (a host owns the whole prefix),
/// IPv4 clients get one per address.
fn bucket_key(address: IpAddr) -> IpAddr {
    match address {
        IpAddr::V4(_) => address,
        IpAddr::V6(v6) => IpAddr::V6(Ipv6Addr::from(u128::from(v6) & (u128::MAX << 64))),
    }
}

/// The real client behind `peer`: the last `X-Forwarded-For` entry (the one the proxy appended; earlier entries come
/// from the client and can be forged), but only when `peer` is a trusted proxy. Otherwise the peer itself.
pub(crate) fn forwarded_client(
    peer: IpAddr,
    forwarded_for: Option<&str>,
    trusted_proxies: &[IpAddr],
) -> IpAddr {
    if !trusted_proxies.contains(&peer) {
        return peer;
    }
    forwarded_for
        .and_then(|value| value.rsplit(',').next())
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(peer)
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
            .entry(bucket_key(address))
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

    fn v6(last: u16, prefix: u16) -> IpAddr {
        IpAddr::V6(Ipv6Addr::new(0x2001, 0xdb8, 0, prefix, 0, 0, 0, last))
    }

    #[test]
    fn addresses_in_one_v6_prefix_share_a_bucket_other_prefixes_do_not() {
        let limiter = IpLimiter::new(10, 1);
        let start = Instant::now();

        assert!(limiter.check(v6(1, 1), start).is_ok());
        assert!(limiter.check(v6(2, 1), start).is_err());
        assert!(limiter.check(v6(1, 2), start).is_ok());
    }

    #[test]
    fn forwarded_for_is_used_only_from_a_trusted_peer() {
        let proxy = address(1);
        let stranger = address(2);
        let header = Some("6.6.6.6, 203.0.113.9");
        let trusted = [proxy];

        assert_eq!(forwarded_client(stranger, header, &trusted), stranger);
        assert_eq!(
            forwarded_client(proxy, header, &trusted),
            address_of("203.0.113.9")
        );
        assert_eq!(forwarded_client(proxy, Some("junk"), &trusted), proxy);
        assert_eq!(forwarded_client(proxy, header, &[]), proxy);
    }

    fn address_of(text: &str) -> IpAddr {
        text.parse().unwrap()
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
