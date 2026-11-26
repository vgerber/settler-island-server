use prometheus::{Encoder, IntCounter, IntCounterVec, IntGauge, Opts, Registry, TextEncoder};
use settler_island_protocol::ErrorCode;

#[derive(Debug, thiserror::Error)]
pub enum MetricsError {
    #[error("registering a metric: {0}")]
    Prometheus(#[from] prometheus::Error),
    #[error("encoding the metrics: {0}")]
    Encoding(#[from] std::string::FromUtf8Error),
}

/// The server's counters and gauges; one set per app, so tests do not see each other's numbers.
#[derive(Debug)]
pub(crate) struct Metrics {
    registry: Registry,
    pub connections: IntGauge,
    pub authenticated_connections: IntGauge,
    pub lobbies: IntGauge,
    running_games: IntGauge,
    pub actions_applied: IntCounter,
    pub bot_actions: IntCounter,
    errors: IntCounterVec,
}

impl Metrics {
    pub(crate) fn new() -> Result<Metrics, MetricsError> {
        let registry = Registry::new();
        let connections = gauge(
            &registry,
            "settler_connections",
            "Open WebSocket connections",
        )?;
        let authenticated_connections = gauge(
            &registry,
            "settler_authenticated_connections",
            "Open WebSocket connections that sent a valid Authenticate",
        )?;
        let lobbies = gauge(&registry, "settler_lobbies", "Open lobbies")?;
        let running_games = gauge(&registry, "settler_running_games", "Games in progress")?;
        let actions_applied = counter(
            &registry,
            "settler_actions_applied_total",
            "Game actions applied, human and bot",
        )?;
        let bot_actions = counter(
            &registry,
            "settler_bot_actions_total",
            "Game actions chosen by bots",
        )?;
        let errors = IntCounterVec::new(
            Opts::new("settler_errors_total", "Errors sent to clients by code"),
            &["code"],
        )?;
        registry.register(Box::new(errors.clone()))?;
        Ok(Metrics {
            registry,
            connections,
            authenticated_connections,
            lobbies,
            running_games,
            actions_applied,
            bot_actions,
            errors,
        })
    }

    /// Counts a game as running until the returned mark ends or is dropped.
    pub(crate) fn game_started(&self) -> GameInProgress {
        self.running_games.inc();
        GameInProgress {
            gauge: Some(self.running_games.clone()),
        }
    }

    pub(crate) fn error(&self, code: &ErrorCode) {
        // `Game` errors collapse into one label; the variants are many and the tag is what an alert needs.
        let label = serde_json::to_value(code)
            .ok()
            .and_then(|value| value["type"].as_str().map(str::to_string))
            .unwrap_or_else(|| "Unknown".to_string());
        self.errors.with_label_values(&[&label]).inc();
    }

    pub(crate) fn render(&self) -> Result<String, MetricsError> {
        let mut buffer = Vec::new();
        TextEncoder::new().encode(&self.registry.gather(), &mut buffer)?;
        Ok(String::from_utf8(buffer)?)
    }
}

/// One running game on the gauge; however often it ends, it is counted down once.
#[derive(Debug)]
pub(crate) struct GameInProgress {
    gauge: Option<IntGauge>,
}

impl GameInProgress {
    pub(crate) fn end(&mut self) {
        if let Some(gauge) = self.gauge.take() {
            gauge.dec();
        }
    }
}

impl Drop for GameInProgress {
    fn drop(&mut self) {
        self.end();
    }
}

fn gauge(registry: &Registry, name: &str, help: &str) -> Result<IntGauge, prometheus::Error> {
    let gauge = IntGauge::new(name, help)?;
    registry.register(Box::new(gauge.clone()))?;
    Ok(gauge)
}

fn counter(registry: &Registry, name: &str, help: &str) -> Result<IntCounter, prometheus::Error> {
    let counter = IntCounter::new(name, help)?;
    registry.register(Box::new(counter.clone()))?;
    Ok(counter)
}

#[cfg(test)]
mod tests {
    use super::Metrics;

    #[test]
    fn a_game_that_ends_twice_and_is_dropped_counts_down_once() {
        let metrics = Metrics::new().unwrap();
        let mut finished = metrics.game_started();
        let running = metrics.game_started();
        finished.end();
        finished.end();
        drop(finished);
        assert_eq!(metrics.running_games.get(), 1);
        drop(running);
        assert_eq!(metrics.running_games.get(), 0);
    }
}
