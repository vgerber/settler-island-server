use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use jsonwebtoken::jwk::{JwkSet, PublicKeyUse};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::time::Instant;
use tracing::{info, warn};

use crate::config::KeycloakConfig;

/// Bounds how often an unknown `kid` (rotation, or a forger guessing) makes us refetch the realm keys.
const MIN_REFRESH_INTERVAL: Duration = Duration::from_secs(60);
const FETCH_TIMEOUT: Duration = Duration::from_secs(10);

/// The claims we read from a Keycloak access token.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AccountClaims {
    pub sub: String,
    pub preferred_username: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum AccountTokenError {
    #[error("the account token is invalid: {0}")]
    Invalid(String),
    #[error("fetching the realm keys failed: {0}")]
    KeysUnavailable(#[from] reqwest::Error),
}

#[derive(Default)]
struct KeyCache {
    keys: HashMap<String, DecodingKey>,
    last_fetch: Option<Instant>,
}

/// Checks RS256 access tokens against the realm's JWKS, issuer, audience and expiry.
pub(crate) struct KeycloakVerifier {
    jwks_url: String,
    validation: Validation,
    http: reqwest::Client,
    // A plain mutex: it is never held across an await.
    cache: Mutex<KeyCache>,
}

impl KeycloakVerifier {
    pub(crate) fn new(config: &KeycloakConfig) -> KeycloakVerifier {
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&[&config.issuer]);
        validation.set_audience(&[&config.audience]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        KeycloakVerifier {
            jwks_url: config.jwks_url(),
            validation,
            http: reqwest::Client::new(),
            cache: Mutex::new(KeyCache::default()),
        }
    }

    pub(crate) async fn verify(&self, token: &str) -> Result<AccountClaims, AccountTokenError> {
        let header = decode_header(token).map_err(invalid)?;
        let kid = header
            .kid
            .ok_or_else(|| AccountTokenError::Invalid("no kid".to_string()))?;
        let key = self
            .key(&kid)
            .await?
            .ok_or_else(|| AccountTokenError::Invalid(format!("unknown kid {kid}")))?;
        let data = decode::<AccountClaims>(token, &key, &self.validation).map_err(invalid)?;
        Ok(data.claims)
    }

    async fn key(&self, kid: &str) -> Result<Option<DecodingKey>, AccountTokenError> {
        if let Some(key) = self.cached(kid) {
            return Ok(Some(key));
        }
        if !self.claim_refresh() {
            return Ok(None);
        }
        let keys = self.fetch().await?;
        let mut cache = self.lock();
        cache.keys = keys;
        Ok(cache.keys.get(kid).cloned())
    }

    fn cached(&self, kid: &str) -> Option<DecodingKey> {
        self.lock().keys.get(kid).cloned()
    }

    /// Records a fetch attempt now unless the last one was too recent.
    fn claim_refresh(&self) -> bool {
        let mut cache = self.lock();
        let now = Instant::now();
        let recent = cache
            .last_fetch
            .is_some_and(|last| now.duration_since(last) < MIN_REFRESH_INTERVAL);
        if !recent {
            cache.last_fetch = Some(now);
        }
        !recent
    }

    async fn fetch(&self) -> Result<HashMap<String, DecodingKey>, AccountTokenError> {
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

fn invalid(error: jsonwebtoken::errors::Error) -> AccountTokenError {
    AccountTokenError::Invalid(error.to_string())
}
