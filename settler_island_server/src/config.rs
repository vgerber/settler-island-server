use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;

const DEFAULT_BIND: &str = "127.0.0.1:8253";
const DEFAULT_BOT_DELAY_MILLISECONDS: u64 = 600;
const DEFAULT_IDLE_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const DEFAULT_MESSAGES_PER_SECOND: u32 = 20;
const DEFAULT_POINTS_TO_WIN: u8 = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    /// Pause before each bot move so humans can follow the game.
    pub bot_delay: Duration,
    /// A connection that sends nothing (not even a ping) for this long is closed.
    pub idle_timeout: Duration,
    pub messages_per_second: u32,
    pub points_to_win: u8,
    /// Fixed game seed for tests and reproductions; `None` draws a random seed per game.
    pub seed: Option<u64>,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("environment variable {name} has the invalid value {value:?}")]
    Invalid { name: &'static str, value: String },
}

impl Default for Config {
    fn default() -> Config {
        Config {
            bind: SocketAddr::from(([127, 0, 0, 1], 8253)),
            bot_delay: Duration::from_millis(DEFAULT_BOT_DELAY_MILLISECONDS),
            idle_timeout: DEFAULT_IDLE_TIMEOUT,
            messages_per_second: DEFAULT_MESSAGES_PER_SECOND,
            points_to_win: DEFAULT_POINTS_TO_WIN,
            seed: None,
        }
    }
}

impl Config {
    /// Reads `SETTLER_BIND` and `SETTLER_BOT_DELAY_MILLISECONDS`; everything else keeps its default.
    pub fn from_env() -> Result<Config, ConfigError> {
        let bind = parse_env("SETTLER_BIND", DEFAULT_BIND)?;
        let bot_delay_milliseconds: u64 = parse_env(
            "SETTLER_BOT_DELAY_MILLISECONDS",
            &DEFAULT_BOT_DELAY_MILLISECONDS.to_string(),
        )?;
        Ok(Config {
            bind,
            bot_delay: Duration::from_millis(bot_delay_milliseconds),
            ..Config::default()
        })
    }
}

fn parse_env<T: FromStr>(name: &'static str, default: &str) -> Result<T, ConfigError> {
    let value = std::env::var(name).unwrap_or_else(|_| default.to_string());
    value
        .parse()
        .map_err(|_| ConfigError::Invalid { name, value })
}
