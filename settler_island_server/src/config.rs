use std::fmt;
use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;

const DEFAULT_BOT_DELAY_MILLISECONDS: u64 = 600;
const DEFAULT_IDLE_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const DEFAULT_LOG_FILTER: &str = "info";
const DEFAULT_ABANDON_AFTER_HOURS: u64 = 168;
const DEFAULT_TRADE_ANSWER_SECONDS: u64 = 20;
const DEFAULT_MESSAGES_PER_SECOND: u32 = 20;
const DEFAULT_SESSION_REQUESTS_PER_MINUTE: u32 = 10;
const DEFAULT_SESSION_BURST: u32 = 5;
/// HMAC-SHA256 gains nothing from longer keys, and shorter ones are guessable.
pub const MIN_SESSION_SECRET_BYTES: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    /// Pause before each bot move so humans can follow the game.
    pub bot_delay: Duration,
    /// How long a bot that offered a trade waits for the humans it asked before it confirms or withdraws.
    pub trade_answer_time: Duration,
    /// A connection that sends nothing (not even a ping) for this long is closed.
    pub idle_timeout: Duration,
    pub messages_per_second: u32,
    /// A running game whose lobby had no connected human for this long is closed and never restored.
    pub abandon_after: Duration,
    /// Sustained rate of `/api/v1/sessions/*` requests per client address.
    pub session_requests_per_minute: u32,
    /// Session requests a client address may send at once before the rate applies.
    pub session_burst: u32,
    /// Take the client address from `X-Forwarded-For` (set only behind a proxy that overwrites it).
    pub trust_forwarded_for: bool,
    /// Fixed game seed for tests and reproductions; `None` draws a random seed per game.
    pub seed: Option<u64>,
    pub session_secret: SessionSecret,
    /// `None` accepts guests only.
    pub keycloak: Option<KeycloakConfig>,
    /// `None` keeps games and identity links in memory only.
    pub database_url: Option<DatabaseUrl>,
    /// A `tracing` filter directive such as `info` or `settler_island_server=debug`.
    pub log_filter: String,
    pub log_format: LogFormat,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogFormat {
    Text,
    Json,
}

impl FromStr for LogFormat {
    type Err = ();

    fn from_str(text: &str) -> Result<LogFormat, ()> {
        match text {
            "text" => Ok(LogFormat::Text),
            "json" => Ok(LogFormat::Json),
            _ => Err(()),
        }
    }
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
            trade_answer_time: Duration::from_secs(DEFAULT_TRADE_ANSWER_SECONDS),
            idle_timeout: DEFAULT_IDLE_TIMEOUT,
            messages_per_second: DEFAULT_MESSAGES_PER_SECOND,
            abandon_after: Duration::from_secs(DEFAULT_ABANDON_AFTER_HOURS * 3600),
            session_requests_per_minute: DEFAULT_SESSION_REQUESTS_PER_MINUTE,
            session_burst: DEFAULT_SESSION_BURST,
            trust_forwarded_for: false,
            log_filter: DEFAULT_LOG_FILTER.to_string(),
            log_format: LogFormat::Text,
            seed: None,
            session_secret,
            keycloak: None,
            database_url: None,
        }
    }

    /// Reads the configuration from the process environment; `.env.example` lists every variable.
    pub fn from_env() -> Result<Config, ConfigError> {
        Config::from_vars(|name| std::env::var(name).ok())
    }

    /// `lookup` returns a variable's value; unset and empty both count as absent, so a blank line in an env file
    /// keeps the default.
    pub fn from_vars(lookup: impl Fn(&str) -> Option<String>) -> Result<Config, ConfigError> {
        let vars = Vars { lookup: &lookup };
        let secret = vars
            .text("SETTLER_SESSION_SECRET")
            .ok_or(ConfigError::Missing("SETTLER_SESSION_SECRET"))?;
        let defaults = Config::new(SessionSecret::new(secret)?);
        let abandon_after_hours: u64 =
            vars.number("SETTLER_ABANDON_AFTER_HOURS", DEFAULT_ABANDON_AFTER_HOURS)?;
        let bot_delay_milliseconds: u64 = vars.parsed(
            "SETTLER_BOT_DELAY_MILLISECONDS",
            DEFAULT_BOT_DELAY_MILLISECONDS,
        )?;
        Ok(Config {
            bind: vars.parsed("SETTLER_BIND", defaults.bind)?,
            bot_delay: Duration::from_millis(bot_delay_milliseconds),
            trade_answer_time: Duration::from_secs(
                vars.number("SETTLER_TRADE_ANSWER_SECONDS", DEFAULT_TRADE_ANSWER_SECONDS)?,
            ),
            abandon_after: Duration::from_secs(abandon_after_hours.saturating_mul(3600)),
            session_requests_per_minute: vars.number(
                "SETTLER_SESSION_REQUESTS_PER_MINUTE",
                DEFAULT_SESSION_REQUESTS_PER_MINUTE,
            )?,
            session_burst: vars.number("SETTLER_SESSION_BURST", DEFAULT_SESSION_BURST)?,
            trust_forwarded_for: vars.parsed("SETTLER_TRUST_FORWARDED_FOR", false)?,
            keycloak: keycloak_from(
                vars.text("SETTLER_KEYCLOAK_ISSUER"),
                vars.text("SETTLER_KEYCLOAK_AUDIENCE"),
            )?,
            database_url: vars.text("DATABASE_URL").map(DatabaseUrl),
            log_filter: vars.text("RUST_LOG").unwrap_or(defaults.log_filter),
            log_format: vars.parsed("SETTLER_LOG_FORMAT", LogFormat::Text)?,
            ..defaults
        })
    }
}

struct Vars<'a> {
    lookup: &'a dyn Fn(&str) -> Option<String>,
}

impl Vars<'_> {
    fn text(&self, name: &str) -> Option<String> {
        (self.lookup)(name).filter(|value| !value.is_empty())
    }

    fn parsed<T: FromStr>(&self, name: &'static str, default: T) -> Result<T, ConfigError> {
        let Some(value) = self.text(name) else {
            return Ok(default);
        };
        value
            .parse()
            .map_err(|_| ConfigError::Invalid { name, value })
    }

    /// A count that must be above zero: a zero rate or burst would refuse every request.
    fn number<T: FromStr + Default + PartialEq>(
        &self,
        name: &'static str,
        default: T,
    ) -> Result<T, ConfigError> {
        let number = self.parsed(name, default)?;
        if number == T::default() {
            return Err(ConfigError::Invalid {
                name,
                value: "0".to_string(),
            });
        }
        Ok(number)
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

    fn load(pairs: &[(&str, &str)]) -> Result<Config, ConfigError> {
        let vars: Vec<(String, String)> = pairs
            .iter()
            .map(|(name, value)| (name.to_string(), value.to_string()))
            .collect();
        Config::from_vars(|name| {
            vars.iter()
                .rev()
                .find(|(key, _)| key == name)
                .map(|(_, value)| value.clone())
        })
    }

    const SECRET: (&str, &str) = ("SETTLER_SESSION_SECRET", "0123456789abcdef0123456789abcdef");

    #[test]
    fn only_the_session_secret_is_required_and_the_rest_defaults() {
        let config = load(&[SECRET]).unwrap();

        assert_eq!(config.bind, "127.0.0.1:8253".parse().unwrap());
        assert_eq!(config.abandon_after, Duration::from_secs(168 * 3600));
        assert_eq!(config.session_burst, 5);
        assert_eq!(config.log_format, LogFormat::Text);
        assert_eq!(config.database_url, None);
        assert!(
            matches!(load(&[]), Err(ConfigError::Missing(name)) if name == "SETTLER_SESSION_SECRET")
        );
    }

    #[test]
    fn every_variable_is_read_and_blank_ones_keep_the_default() {
        let config = load(&[
            SECRET,
            ("SETTLER_BIND", "0.0.0.0:9000"),
            ("DATABASE_URL", "postgres://u:p@db/x"),
            ("SETTLER_KEYCLOAK_ISSUER", "http://kc/realms/r"),
            ("SETTLER_KEYCLOAK_AUDIENCE", "game"),
            ("SETTLER_BOT_DELAY_MILLISECONDS", "50"),
            ("SETTLER_ABANDON_AFTER_HOURS", "2"),
            ("SETTLER_SESSION_REQUESTS_PER_MINUTE", "30"),
            ("SETTLER_SESSION_BURST", "9"),
            ("SETTLER_TRUST_FORWARDED_FOR", "true"),
            ("RUST_LOG", "debug"),
            ("SETTLER_LOG_FORMAT", "json"),
        ])
        .unwrap();

        assert_eq!(config.bind.port(), 9000);
        assert_eq!(config.bot_delay, Duration::from_millis(50));
        assert_eq!(config.abandon_after, Duration::from_secs(7200));
        assert_eq!(
            (config.session_requests_per_minute, config.session_burst),
            (30, 9)
        );
        assert!(config.trust_forwarded_for);
        assert_eq!(
            config.keycloak.map(|keycloak| keycloak.audience),
            Some("game".to_string())
        );
        assert!(config.database_url.is_some());
        assert_eq!(
            (config.log_filter.as_str(), config.log_format),
            ("debug", LogFormat::Json)
        );
        let blank = load(&[SECRET, ("SETTLER_BIND", "")]).unwrap();
        assert_eq!(blank.bind.port(), 8253);
    }

    #[test]
    fn the_example_env_file_loads_and_documents_the_defaults() {
        let example = include_str!("../../.env.example");
        let pairs: Vec<(&str, &str)> = example
            .lines()
            .filter(|line| !line.starts_with('#') && line.contains('='))
            .filter_map(|line| line.split_once('='))
            .collect();

        let config = load(&pairs).unwrap();

        let defaults = Config::new(SessionSecret::new(vec![0; 32]).unwrap());
        assert_eq!(config.bind, defaults.bind);
        assert_eq!(config.bot_delay, defaults.bot_delay);
        assert_eq!(config.abandon_after, defaults.abandon_after);
        assert_eq!(
            config.session_requests_per_minute,
            defaults.session_requests_per_minute
        );
        assert_eq!(config.session_burst, defaults.session_burst);
        assert_eq!(config.keycloak, None);
    }

    #[test]
    fn invalid_values_name_the_variable() {
        for (name, value) in [
            ("SETTLER_BIND", "nowhere"),
            ("SETTLER_ABANDON_AFTER_HOURS", "soon"),
            ("SETTLER_SESSION_BURST", "0"),
            ("SETTLER_LOG_FORMAT", "xml"),
            ("SETTLER_TRUST_FORWARDED_FOR", "maybe"),
        ] {
            let error = load(&[SECRET, (name, value)]).unwrap_err();
            assert!(
                matches!(&error, ConfigError::Invalid { name: reported, .. } if *reported == name),
                "{name}: {error}"
            );
        }
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
