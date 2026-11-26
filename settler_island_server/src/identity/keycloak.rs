use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use jsonwebtoken::jwk::{JwkSet, PublicKeyUse};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::time::Instant;
use tracing::{info, warn};

use crate::config::KeycloakConfig;

/// Bounds how often an unknown `kid` (rotation, or a forger guessing) makes us refetch the realm keys.
const MIN_REFRESH_INTERVAL: Duration = Duration::from_secs(60);
/// After a failed fetch every request gets the same error for this long, so a down realm is not hammered.
const FAILURE_BACKOFF: Duration = Duration::from_secs(5);
const FETCH_TIMEOUT: Duration = Duration::from_secs(10);

/// The claims we read from a Keycloak access token.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AccountClaims {
    pub sub: String,
    pub preferred_username: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum AccountTokenError {
    #[error("the account token names no key id")]
    MissingKeyId,
    #[error("the realm has no key with id {0}")]
    UnknownKeyId(String),
    #[error("the account token is invalid: {0}")]
    Rejected(#[from] jsonwebtoken::errors::Error),
    #[error("fetching the realm keys failed: {0}")]
    KeysUnavailable(Arc<reqwest::Error>),
}

#[derive(Default)]
struct KeyCache {
    keys: HashMap<String, DecodingKey>,
    /// Set only by a successful fetch, so a failed one never blocks the next attempt.
    last_fetch: Option<Instant>,
}

/// Held by the refresh lock, so requests during the back-off get the last failure instead of fetching again.
#[derive(Default)]
struct RefreshState {
    last_failure: Option<(Instant, Arc<reqwest::Error>)>,
}

/// Checks RS256 access tokens against the realm's JWKS, issuer, audience and expiry.
pub(crate) struct KeycloakVerifier {
    jwks_url: String,
    validation: Validation,
    http: reqwest::Client,
    // A plain mutex: it is never held across an await.
    cache: Mutex<KeyCache>,
    // Serialises fetches, so concurrent misses wait for one fetch instead of each starting their own.
    refresh: tokio::sync::Mutex<RefreshState>,
}

impl KeycloakVerifier {
    pub(crate) fn new(config: &KeycloakConfig) -> KeycloakVerifier {
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&[&config.issuer]);
        validation.set_audience(&[&config.audience]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.validate_nbf = true;
        KeycloakVerifier {
            jwks_url: config.jwks_url(),
            validation,
            http: reqwest::Client::new(),
            cache: Mutex::new(KeyCache::default()),
            refresh: tokio::sync::Mutex::new(RefreshState::default()),
        }
    }

    pub(crate) async fn verify(&self, token: &str) -> Result<AccountClaims, AccountTokenError> {
        let header = decode_header(token)?;
        let kid = header.kid.ok_or(AccountTokenError::MissingKeyId)?;
        let key = self.key(&kid).await?;
        let data = decode::<AccountClaims>(token, &key, &self.validation)?;
        Ok(data.claims)
    }

    async fn key(&self, kid: &str) -> Result<DecodingKey, AccountTokenError> {
        if let Some(key) = self.cached(kid) {
            return Ok(key);
        }
        let mut refresh = self.refresh.lock().await;
        if let Some(key) = self.cached(kid) {
            return Ok(key);
        }
        if let Some((failed_at, error)) = &refresh.last_failure {
            if failed_at.elapsed() < FAILURE_BACKOFF {
                return Err(AccountTokenError::KeysUnavailable(error.clone()));
            }
        }
        if self.fetched_recently() {
            return Err(AccountTokenError::UnknownKeyId(kid.to_string()));
        }
        let keys = match self.fetch().await {
            Ok(keys) => keys,
            Err(error) => {
                let error = Arc::new(error);
                refresh.last_failure = Some((Instant::now(), error.clone()));
                return Err(AccountTokenError::KeysUnavailable(error));
            }
        };
        refresh.last_failure = None;
        let mut cache = self.lock();
        cache.keys = keys;
        cache.last_fetch = Some(Instant::now());
        cache
            .keys
            .get(kid)
            .cloned()
            .ok_or_else(|| AccountTokenError::UnknownKeyId(kid.to_string()))
    }

    fn cached(&self, kid: &str) -> Option<DecodingKey> {
        self.lock().keys.get(kid).cloned()
    }

    fn fetched_recently(&self) -> bool {
        self.lock()
            .last_fetch
            .is_some_and(|last| last.elapsed() < MIN_REFRESH_INTERVAL)
    }

    async fn fetch(&self) -> Result<HashMap<String, DecodingKey>, reqwest::Error> {
        let set: JwkSet = self
            .http
            .get(&self.jwks_url)
            .timeout(FETCH_TIMEOUT)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let keys: HashMap<String, DecodingKey> = set
            .keys
            .iter()
            .filter(|jwk| jwk.common.public_key_use != Some(PublicKeyUse::Encryption))
            .filter_map(|jwk| {
                let kid = jwk.common.key_id.clone()?;
                match DecodingKey::from_jwk(jwk) {
                    Ok(key) => Some((kid, key)),
                    Err(error) => {
                        warn!(%kid, %error, "skipping an unusable realm key");
                        None
                    }
                }
            })
            .collect();
        info!(count = keys.len(), "fetched the realm keys");
        Ok(keys)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, KeyCache> {
        // The cache holds no invariant a panicking holder could break, so a poisoned lock is still usable.
        self.cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}
