//! Authoritative game server: axum hosts the WebSocket, actors own connections, the lobby list and each lobby.

mod config;
mod connection;
mod lobby;
mod outbox;
mod password;
mod registry;
mod store;

use std::future::Future;
use std::sync::Arc;

use axum::extract::ws::WebSocketUpgrade;
use axum::extract::State;
use axum::response::Response;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;
use tokio::net::TcpListener;

pub use config::{Config, ConfigError};
pub use store::{
    GameId, GameStore, MemoryStore, NewGame, SeatPlayer, StoreError, StoredAction, StoredGame,
};

use registry::RegistryHandle;

/// Frames above our 64 KiB limit still arrive and get an error reply; beyond this the socket is dropped.
const MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Clone)]
struct AppState {
    registry: RegistryHandle,
    config: Arc<Config>,
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
}

pub fn router<S: GameStore>(config: Config, store: S) -> Router {
    let config = Arc::new(config);
    let state = AppState {
        registry: registry::spawn(Arc::new(store), config.clone()),
        config,
    };
    Router::new()
        .route("/api/v1/health", get(health))
        .route("/api/v1/ws", get(upgrade))
        .with_state(state)
}

/// Serves until `shutdown` completes.
pub async fn serve<S: GameStore>(
    listener: TcpListener,
    config: Config,
    store: S,
    shutdown: impl Future<Output = ()> + Send + 'static,
) -> std::io::Result<()> {
    axum::serve(listener, router(config, store))
        .with_graceful_shutdown(shutdown)
        .await
}

async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

async fn upgrade(State(state): State<AppState>, upgrade: WebSocketUpgrade) -> Response {
    upgrade
        .max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .on_upgrade(move |socket| connection::run(socket, state.registry, state.config))
}
