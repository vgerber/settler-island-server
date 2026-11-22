use std::fmt;
use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;

const DEFAULT_BIND: &str = "127.0.0.1:8253";
const DEFAULT_BOT_DELAY_MILLISECONDS: u64 = 600;
const DEFAULT_IDLE_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const DEFAULT_MESSAGES_PER_SECOND: u32 = 20;
/// HMAC-SHA256 gains nothing from longer keys, and shorter ones are guessable.
pub const MIN_SESSION_SECRET_BYTES: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    /// Pause before each bot move so humans can follow the game.
    pub bot_delay: Duration,
    /// A connection that sends nothing (not even a ping) for this long is closed.
    pub idle_timeout: Duration,
    pub messages_per_second: u32,
    /// Fixed game seed for tests and reproductions; `None` draws a random seed per game.
    pub seed: Option<u64>,
    pub session_secret: SessionSecret,
    /// `None` accepts guests only.
    pub keycloak: Option<KeycloakConfig>,
    /// `None` keeps games and identity links in memory only.
    pub database_url: Option<DatabaseUrl>,
}

/// A Postgres connection URL; never printed, it may carry a password.
#[derive(Clone, PartialEq, Eq)]
pub struct DatabaseUrl(pub String);

impl fmt::Debug for DatabaseUrl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("DatabaseUrl(..)")
    }
}

/// Signs guest session tokens; never printed.
#[derive(Clone, PartialEq, Eq)]
pub struct SessionSecret(Vec<u8>);

impl SessionSecret {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Result<SessionSecret, ConfigError> {
        let bytes = bytes.into();
        if bytes.len() < MIN_SESSION_SECRET_BYTES {
            return Err(ConfigError::SessionSecretTooShort);
        }
        Ok(SessionSecret(bytes))
    }

    pub(crate) fn bytes(&self) -> &[u8] {
        &self.0
    }
}

impl fmt::Debug for SessionSecret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SessionSecret(..)")
    }
}

/// The realm whose access tokens are accepted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeycloakConfig {
    /// The realm URL, e.g. `http://127.0.0.1:8086/realms/settler-island`; must equal the tokens' `iss`.
    pub issuer: String,
    /// Required in the tokens' `aud`.
    pub audience: String,
}

impl KeycloakConfig {
    pub(crate) fn jwks_url(&self) -> String {
        format!(
            "{}/protocol/openid-connect/certs",
            self.issuer.trim_end_matches('/')
        )
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("environment variable {name} has the invalid value {value:?}")]
    Invalid { name: &'static str, value: String },
    #[error("environment variable {0} is required")]
    Missing(&'static str),
    #[error("SETTLER_SESSION_SECRET needs at least {MIN_SESSION_SECRET_BYTES} bytes")]
    SessionSecretTooShort,
    #[error("set both SETTLER_KEYCLOAK_ISSUER and SETTLER_KEYCLOAK_AUDIENCE, or neither")]
    IncompleteKeycloak,
}

impl Config {
    pub fn new(session_secret: SessionSecret) -> Config {
        Config {
            bind: SocketAddr::from(([127, 0, 0, 1], 8253)),
            bot_delay: Duration::from_millis(DEFAULT_BOT_DELAY_MILLISECONDS),
            idle_timeout: DEFAULT_IDLE_TIMEOUT,
            messages_per_second: DEFAULT_MESSAGES_PER_SECOND,
            seed: None,
            session_secret,
            keycloak: None,
            database_url: None,
        }
    }

    /// Reads `SETTLER_BIND`, `SETTLER_BOT_DELAY_MILLISECONDS`, `SETTLER_SESSION_SECRET` (required),
    /// `SETTLER_KEYCLOAK_ISSUER` plus `SETTLER_KEYCLOAK_AUDIENCE` and `DATABASE_URL`; everything else keeps its default.
    pub fn from_env() -> Result<Config, ConfigError> {
        let secret = std::env::var("SETTLER_SESSION_SECRET")
            .map_err(|_| ConfigError::Missing("SETTLER_SESSION_SECRET"))?;
        let bind = parse_env("SETTLER_BIND", DEFAULT_BIND)?;
        let bot_delay_milliseconds: u64 = parse_env(
            "SETTLER_BOT_DELAY_MILLISECONDS",
            &DEFAULT_BOT_DELAY_MILLISECONDS.to_string(),
        )?;
        let keycloak = keycloak_from(
            std::env::var("SETTLER_KEYCLOAK_ISSUER").ok(),
            std::env::var("SETTLER_KEYCLOAK_AUDIENCE").ok(),
        )?;
        Ok(Config {
            bind,
            bot_delay: Duration::from_millis(bot_delay_milliseconds),
            keycloak,
            database_url: std::env::var("DATABASE_URL").ok().map(DatabaseUrl),
            ..Config::new(SessionSecret::new(secret)?)
        })
    }
}

fn keycloak_from(
    issuer: Option<String>,
    audience: Option<String>,
) -> Result<Option<KeycloakConfig>, ConfigError> {
    match (issuer, audience) {
        (Some(issuer), Some(audience)) => Ok(Some(KeycloakConfig { issuer, audience })),
        (None, None) => Ok(None),
        _ => Err(ConfigError::IncompleteKeycloak),
    }
}

fn parse_env<T: FromStr>(name: &'static str, default: &str) -> Result<T, ConfigError> {
    let value = std::env::var(name).unwrap_or_else(|_| default.to_string());
    value
        .parse()
        .map_err(|_| ConfigError::Invalid { name, value })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_session_secrets_are_refused() {
        assert!(matches!(
            SessionSecret::new(vec![7; 31]),
            Err(ConfigError::SessionSecretTooShort)
        ));
        assert!(SessionSecret::new(vec![7; 32]).is_ok());
    }

    #[test]
    fn keycloak_needs_issuer_and_audience_together() {
        assert!(matches!(
            keycloak_from(Some("http://issuer".to_string()), None),
            Err(ConfigError::IncompleteKeycloak)
        ));
        assert!(matches!(keycloak_from(None, None), Ok(None)));
    }
}
