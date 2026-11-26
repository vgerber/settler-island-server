use std::collections::HashMap;
use std::hash::Hash;
use std::net::IpAddr;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};

use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use rand::RngCore;
use settler_island_protocol::{LobbyId, UserId};
use tokio::sync::Semaphore;

/// Each Argon2 run takes about 19 MiB and a core; a constant because `config.rs` is shared and this bound only
/// protects the process, it is not a deployment choice.
const MAX_CONCURRENT_HASHES: usize = 4;

/// Wrong passwords allowed per window, per (user, lobby) and per client address.
const MAX_WRONG_GUESSES: u32 = 5;
const GUESS_WINDOW: Duration = Duration::from_secs(60);

/// Above this many tracked keys, expired windows are dropped so the maps cannot grow without bound.
const PRUNE_ABOVE: usize = 10_000;

static HASH_PERMITS: Semaphore = Semaphore::const_new(MAX_CONCURRENT_HASHES);

/// Process-wide, like the hash permits, so guesses spread over many connections still add up.
pub(crate) static GUESSES: LazyLock<GuessLimiter> = LazyLock::new(GuessLimiter::default);

#[derive(Debug, thiserror::Error)]
pub(crate) enum PasswordError {
    #[error("password hashing failed: {0}")]
    Hash(argon2::password_hash::Error),
    #[error("the password task failed: {0}")]
    Task(#[from] tokio::task::JoinError),
    #[error("the hash permits are closed")]
    Closed(#[from] tokio::sync::AcquireError),
}

pub(crate) async fn hash(password: String) -> Result<String, PasswordError> {
    limited(move || hash_now(&password)).await?
}

/// A malformed hash never matches.
pub(crate) async fn verify(hash: Arc<str>, password: String) -> Result<bool, PasswordError> {
    limited(move || verify_now(&hash, &password)).await
}

/// Runs CPU-heavy work off the async threads, at most `MAX_CONCURRENT_HASHES` at once.
async fn limited<Output: Send + 'static>(
    work: impl FnOnce() -> Output + Send + 'static,
) -> Result<Output, PasswordError> {
    let _permit = HASH_PERMITS.acquire().await?;
    Ok(tokio::task::spawn_blocking(work).await?)
}

fn hash_now(password: &str) -> Result<String, PasswordError> {
    let mut salt = [0u8; 16];
    rand::rng().fill_bytes(&mut salt);
    let salt = SaltString::encode_b64(&salt).map_err(PasswordError::Hash)?;
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(PasswordError::Hash)?;
    Ok(hash.to_string())
}

fn verify_now(hash: &str, password: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

/// Who is guessing: the user at one lobby, and the address they come from when it is known.
pub(crate) struct Guesser {
    pub(crate) user: UserId,
    pub(crate) lobby: LobbyId,
    pub(crate) address: Option<IpAddr>,
}

#[derive(Debug, PartialEq, Eq, thiserror::Error)]
#[error("too many wrong passwords")]
pub(crate) struct TooManyGuesses;

/// Counts wrong lobby passwords in fixed windows.
#[derive(Default)]
pub(crate) struct GuessLimiter {
    windows: Mutex<GuessWindows>,
}

#[derive(Default)]
struct GuessWindows {
    by_user: HashMap<(UserId, LobbyId), Window>,
    by_address: HashMap<IpAddr, Window>,
}

#[derive(Clone, Copy)]
struct Window {
    started: Instant,
    guesses: u32,
}

impl Window {
    fn expired(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.started) >= GUESS_WINDOW
    }
}

impl GuessLimiter {
    /// Books an attempt as wrong before Argon2 runs, so parallel guesses cannot all slip under the limit; a correct
    /// password hands it back with `forgive`.
    pub(crate) fn attempt(&self, guesser: &Guesser, now: Instant) -> Result<(), TooManyGuesses> {
        let mut windows = self.lock();
        windows.prune(now);
        let user_key = (guesser.user.clone(), guesser.lobby);
        let user_full = is_full(windows.by_user.get(&user_key), now);
        let address_full = guesser
            .address
            .is_some_and(|address| is_full(windows.by_address.get(&address), now));
        if user_full || address_full {
            return Err(TooManyGuesses);
        }
        count(&mut windows.by_user, user_key, now);
        if let Some(address) = guesser.address {
            count(&mut windows.by_address, address, now);
        }
        Ok(())
    }

    pub(crate) fn forgive(&self, guesser: &Guesser) {
        let mut windows = self.lock();
        uncount(&mut windows.by_user, &(guesser.user.clone(), guesser.lobby));
        if let Some(address) = guesser.address {
            uncount(&mut windows.by_address, &address);
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, GuessWindows> {
        // A poisoned lock only means another task panicked; the counts are still usable.
        self.windows
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl GuessWindows {
    fn prune(&mut self, now: Instant) {
        if self.by_user.len() > PRUNE_ABOVE {
            self.by_user.retain(|_, window| !window.expired(now));
        }
        if self.by_address.len() > PRUNE_ABOVE {
            self.by_address.retain(|_, window| !window.expired(now));
        }
    }
}

fn is_full(window: Option<&Window>, now: Instant) -> bool {
    window.is_some_and(|window| !window.expired(now) && window.guesses >= MAX_WRONG_GUESSES)
}

fn count<Key: Hash + Eq>(windows: &mut HashMap<Key, Window>, key: Key, now: Instant) {
    let window = windows.entry(key).or_insert(Window {
        started: now,
        guesses: 0,
    });
    if window.expired(now) {
        *window = Window {
            started: now,
            guesses: 0,
        };
    }
    window.guesses += 1;
}

fn uncount<Key: Hash + Eq>(windows: &mut HashMap<Key, Window>, key: &Key) {
    if let Some(window) = windows.get_mut(key) {
        window.guesses = window.guesses.saturating_sub(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[tokio::test]
    async fn only_the_original_password_verifies_and_salts_differ() {
        let first = hash("open sesame".to_string()).await.unwrap();
        let second = hash("open sesame".to_string()).await.unwrap();

        assert_ne!(first, second);
        assert!(!first.contains("open sesame"));
        assert!(verify(Arc::from(first.as_str()), "open sesame".to_string())
            .await
            .unwrap());
        assert!(
            !verify(Arc::from(first.as_str()), "open sesame ".to_string())
                .await
                .unwrap()
        );
        assert!(!verify(Arc::from("not a hash"), "open sesame".to_string())
            .await
            .unwrap());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_hash_work_never_exceeds_the_permits() {
        let running = Arc::new(AtomicUsize::new(0));
        let most = Arc::new(AtomicUsize::new(0));
        let tasks: Vec<_> = (0..4 * MAX_CONCURRENT_HASHES)
            .map(|_| {
                let running = running.clone();
                let most = most.clone();
                tokio::spawn(limited(move || {
                    let now = running.fetch_add(1, Ordering::SeqCst) + 1;
                    most.fetch_max(now, Ordering::SeqCst);
                    std::thread::sleep(Duration::from_millis(30));
                    running.fetch_sub(1, Ordering::SeqCst);
                }))
            })
            .collect();
        for task in tasks {
            task.await.unwrap().unwrap();
        }

        let most = most.load(Ordering::SeqCst);
        assert!(most <= MAX_CONCURRENT_HASHES, "{most} ran at once");
    }

    fn guesser(user: &str, lobby: u32, address: Option<[u8; 4]>) -> Guesser {
        Guesser {
            user: UserId(user.to_string()),
            lobby: LobbyId(lobby),
            address: address.map(IpAddr::from),
        }
    }

    #[test]
    fn the_sixth_guess_in_a_window_is_refused_and_the_next_window_allows_one() {
        let limiter = GuessLimiter::default();
        let start = Instant::now();
        let mallory = guesser("mallory", 1, None);
        for _ in 0..MAX_WRONG_GUESSES {
            assert_eq!(limiter.attempt(&mallory, start), Ok(()));
        }

        assert_eq!(limiter.attempt(&mallory, start), Err(TooManyGuesses));
        assert_eq!(limiter.attempt(&guesser("mallory", 2, None), start), Ok(()));
        assert_eq!(limiter.attempt(&mallory, start + GUESS_WINDOW), Ok(()));
    }

    #[test]
    fn guesses_from_one_address_add_up_across_users_and_a_correct_password_is_forgiven() {
        let limiter = GuessLimiter::default();
        let now = Instant::now();
        let address = Some([10, 0, 0, 1]);
        let honest = guesser("honest", 1, address);
        assert_eq!(limiter.attempt(&honest, now), Ok(()));
        limiter.forgive(&honest);
        for index in 0..MAX_WRONG_GUESSES {
            let user = format!("sybil {index}");
            assert_eq!(limiter.attempt(&guesser(&user, 1, address), now), Ok(()));
        }

        assert_eq!(
            limiter.attempt(&guesser("sybil next", 1, address), now),
            Err(TooManyGuesses)
        );
        assert_eq!(
            limiter.attempt(&guesser("elsewhere", 1, Some([10, 0, 0, 2])), now),
            Ok(())
        );
    }
}
