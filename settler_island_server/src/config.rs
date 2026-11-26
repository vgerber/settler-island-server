use std::fmt;
use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;

use sqlx::postgres::PgConnectOptions;

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
/// Every environment variable the server reads; a test keeps `.env.example` in step with it.
pub const VARIABLES: [&str; 13] = [
    "SETTLER_SESSION_SECRET",
    "SETTLER_BIND",
    "DATABASE_URL",
    "SETTLER_KEYCLOAK_ISSUER",
    "SETTLER_KEYCLOAK_AUDIENCE",
    "SETTLER_BOT_DELAY_MILLISECONDS",
    "SETTLER_ABANDON_AFTER_HOURS",
    "SETTLER_SESSION_REQUESTS_PER_MINUTE",
    "SETTLER_SESSION_BURST",
    "SETTLER_TRUST_FORWARDED_FOR",
    "RUST_LOG",
    "SETTLER_LOG_FORMAT",
    "SETTLER_TRADE_ANSWER_SECONDS",
];

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

/// A validated Postgres connection URL; never printed, it may carry a password.
#[derive(Clone)]
pub struct DatabaseUrl {
    url: String,
    options: PgConnectOptions,
}

impl DatabaseUrl {
    pub fn options(&self) -> PgConnectOptions {
        self.options.clone()
    }
}

impl FromStr for DatabaseUrl {
    type Err = sqlx::Error;

    fn from_str(url: &str) -> Result<DatabaseUrl, sqlx::Error> {
        Ok(DatabaseUrl {
            url: url.to_string(),
            options: url.parse()?,
        })
    }
}

impl PartialEq for DatabaseUrl {
    fn eq(&self, other: &DatabaseUrl) -> bool {
        self.url == other.url
    }
}

impl Eq for DatabaseUrl {}

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
    #[error("DATABASE_URL is not a valid Postgres URL: {0}")]
    InvalidDatabaseUrl(#[source] sqlx::Error),
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
            database_url: vars
                .text("DATABASE_URL")
                .map(|url| url.parse().map_err(ConfigError::InvalidDatabaseUrl))
                .transpose()?,
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

    fn with_secret(vars: &[(&str, &str)]) -> Config {
        let mut all = vec![SECRET];
        all.extend_from_slice(vars);
        load(&all).unwrap()
    }

    fn defaults() -> Config {
        Config::new(SessionSecret::new(SECRET.1).unwrap())
    }

    #[test]
    fn only_the_session_secret_is_required_and_the_rest_defaults() {
        assert_eq!(with_secret(&[]), defaults());
        assert!(
            matches!(load(&[]), Err(ConfigError::Missing(name)) if name == "SETTLER_SESSION_SECRET")
        );
    }

    #[test]
    fn every_variable_is_read_and_blank_ones_keep_the_default() {
        let config = with_secret(&[
            ("SETTLER_BIND", "0.0.0.0:9000"),
            ("DATABASE_URL", "postgres://u:p@db/x"),
            ("SETTLER_KEYCLOAK_ISSUER", "http://kc/realms/r"),
            ("SETTLER_KEYCLOAK_AUDIENCE", "game"),
            ("SETTLER_BOT_DELAY_MILLISECONDS", "50"),
            ("SETTLER_TRADE_ANSWER_SECONDS", "7"),
            ("SETTLER_ABANDON_AFTER_HOURS", "2"),
            ("SETTLER_SESSION_REQUESTS_PER_MINUTE", "30"),
            ("SETTLER_SESSION_BURST", "9"),
            ("SETTLER_TRUST_FORWARDED_FOR", "true"),
            ("RUST_LOG", "debug"),
            ("SETTLER_LOG_FORMAT", "json"),
        ]);

        assert_eq!(
            config,
            Config {
                bind: "0.0.0.0:9000".parse().unwrap(),
                bot_delay: Duration::from_millis(50),
                trade_answer_time: Duration::from_secs(7),
                abandon_after: Duration::from_secs(7200),
                session_requests_per_minute: 30,
                session_burst: 9,
                trust_forwarded_for: true,
                keycloak: Some(KeycloakConfig {
                    issuer: "http://kc/realms/r".to_string(),
                    audience: "game".to_string(),
                }),
                database_url: Some("postgres://u:p@db/x".parse().unwrap()),
                log_filter: "debug".to_string(),
                log_format: LogFormat::Json,
                ..defaults()
            }
        );
        assert_eq!(with_secret(&[("SETTLER_BIND", "")]), defaults());
    }

    #[test]
    fn a_malformed_database_url_is_refused_without_echoing_it() {
        let error = load(&[SECRET, ("DATABASE_URL", "not a url:hunter2")]).unwrap_err();

        assert!(matches!(error, ConfigError::InvalidDatabaseUrl(_)));
        assert!(!error.to_string().contains("hunter2"), "{error}");
    }

    /// Variables `.env.example` documents that the server itself never reads.
    const NOT_READ_BY_SERVER: [&str; 2] = ["SQLX_OFFLINE", "SETTLER_TEST_DATABASE_URL"];

    fn example_pairs() -> Vec<(&'static str, &'static str)> {
        include_str!("../../.env.example")
            .lines()
            .map(|line| line.strip_prefix('#').unwrap_or(line))
            .filter_map(|line| line.split_once('='))
            .filter(|(name, _)| {
                !name.is_empty()
                    && name
                        .chars()
                        .all(|letter| letter.is_ascii_uppercase() || letter == '_')
            })
            .collect()
    }

    #[test]
    fn the_example_env_file_names_exactly_the_variables_the_server_reads() {
        let mut documented: Vec<&str> = example_pairs().iter().map(|(name, _)| *name).collect();
        documented.sort_unstable();
        documented.dedup();
        let mut expected: Vec<&str> = VARIABLES.into_iter().chain(NOT_READ_BY_SERVER).collect();
        expected.sort_unstable();

        assert_eq!(documented, expected);
    }

    #[test]
    fn from_vars_looks_up_only_listed_variables_and_all_of_them() {
        let asked = std::cell::RefCell::new(Vec::new());
        let _ = Config::from_vars(|name| {
            asked.borrow_mut().push(name.to_string());
            Some(SECRET.1.to_string()).filter(|_| name == SECRET.0)
        });

        let mut asked = asked.into_inner();
        asked.sort_unstable();
        let mut listed: Vec<String> = VARIABLES.iter().map(|name| name.to_string()).collect();
        listed.sort_unstable();
        assert_eq!(asked, listed);
    }

    #[test]
    fn the_example_env_file_loads_and_documents_the_defaults() {
        let uncommented: Vec<(&str, &str)> = include_str!("../../.env.example")
            .lines()
            .filter(|line| !line.starts_with('#') && line.contains('='))
            .filter_map(|line| line.split_once('='))
            .filter(|(name, _)| VARIABLES.contains(name))
            .collect();

        let config = load(&uncommented).unwrap();

        assert_eq!(
            config,
            Config {
                session_secret: config.session_secret.clone(),
                database_url: config.database_url.clone(),
                ..defaults()
            }
        );
        assert!(config.database_url.is_some());
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
