//! Authoritative game server: axum hosts the WebSocket, actors own connections, the lobby list and each lobby.

mod config;
mod connection;
mod identity;
mod lobby;
mod metrics;
mod names;
mod outbox;
mod password;
mod postgres;
mod registry;
mod store;

use std::future::Future;
use std::sync::Arc;

use axum::extract::ws::WebSocketUpgrade;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Serialize;
use settler_island_protocol::{
    ErrorCode, GuestSession, GuestSessionRequest, HttpError, UpgradeRequest, Upgraded,
};
use tokio::net::TcpListener;

pub use config::{
    Config, ConfigError, DatabaseUrl, KeycloakConfig, SessionSecret, MIN_SESSION_SECRET_BYTES,
};
pub use identity::{IdentityStore, IdentityStoreError, MemoryIdentityStore};
pub use metrics::MetricsError;
pub use postgres::PostgresStore;
pub use store::{
    GameId, GameStore, MemoryStore, NewGame, RebuildError, SeatPlayer, Snapshot, StoreError,
    StoredAction, StoredGame, SNAPSHOT_INTERVAL,
};

use identity::Identity;
use metrics::Metrics;
use registry::RegistryHandle;

/// Frames above our 64 KiB limit still arrive and get an error reply; beyond this the socket is dropped.
const MAX_FRAME_BYTES: usize = 1024 * 1024;

struct AppState<I> {
    registry: RegistryHandle,
    identity: Arc<Identity<I>>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
}

// Derived `Clone` would needlessly require `I: Clone`.
impl<I> Clone for AppState<I> {
    fn clone(&self) -> AppState<I> {
        AppState {
            registry: self.registry.clone(),
            identity: self.identity.clone(),
            config: self.config.clone(),
            metrics: self.metrics.clone(),
        }
    }
}

/// An `ErrorCode` as an HTTP reply.
struct HttpFailure(ErrorCode);

impl IntoResponse for HttpFailure {
    fn into_response(self) -> Response {
        let status = match self.0 {
            ErrorCode::InvalidToken => StatusCode::UNAUTHORIZED,
            ErrorCode::AccountAlreadyLinked => StatusCode::CONFLICT,
            ErrorCode::Internal => StatusCode::INTERNAL_SERVER_ERROR,
            _ => StatusCode::BAD_REQUEST,
        };
        let body = HttpError {
            code: self.0,
            message: self.0.description(),
        };
        (status, Json(body)).into_response()
    }
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
}

#[derive(Debug, thiserror::Error)]
pub enum ServeError {
    #[error("network: {0}")]
    Io(#[from] std::io::Error),
    #[error("loading the running games: {0}")]
    Store(#[from] StoreError),
    #[error(transparent)]
    Metrics(#[from] MetricsError),
}

/// The app with the lobbies of every game `store` holds as running.
pub async fn router<S: GameStore, I: IdentityStore>(
    config: Config,
    store: S,
    identities: I,
) -> Result<Router, ServeError> {
    let running = store.load_running().await?;
    let config = Arc::new(config);
    let metrics = Arc::new(Metrics::new()?);
    let state = AppState {
        registry: registry::spawn(Arc::new(store), config.clone(), metrics.clone(), running),
        identity: Arc::new(Identity::new(&config, identities)),
        config,
        metrics,
    };
    let router = Router::new()
        .route("/api/v1/health", get(health))
        .route("/metrics", get(metrics_page::<I>))
        .route("/api/v1/ws", get(upgrade::<I>))
        .route("/api/v1/sessions/guest", post(guest_session::<I>))
        .route("/api/v1/sessions/upgrade", post(upgrade_session::<I>))
        .with_state(state);
    Ok(router)
}

/// Serves until `shutdown` completes.
pub async fn serve<S: GameStore, I: IdentityStore>(
    listener: TcpListener,
    config: Config,
    store: S,
    identities: I,
    shutdown: impl Future<Output = ()> + Send + 'static,
) -> Result<(), ServeError> {
    let router = router(config, store, identities).await?;
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown)
        .await?;
    Ok(())
}

async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

async fn metrics_page<I>(State(state): State<AppState<I>>) -> Result<String, HttpFailure> {
    state.metrics.render().map_err(|error| {
        tracing::error!(%error, "rendering the metrics failed");
        HttpFailure(ErrorCode::Internal)
    })
}

async fn upgrade<I: IdentityStore>(
    State(state): State<AppState<I>>,
    upgrade: WebSocketUpgrade,
) -> Response {
    upgrade
        .max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .on_upgrade(move |socket| {
            connection::run(
                socket,
                state.registry,
                state.identity,
                state.config,
                state.metrics,
            )
        })
}

async fn guest_session<I: IdentityStore>(
    State(state): State<AppState<I>>,
    Json(request): Json<GuestSessionRequest>,
) -> Result<Json<GuestSession>, HttpFailure> {
    state
        .identity
        .guest_session(&request.name)
        .map(Json)
        .map_err(HttpFailure)
}

async fn upgrade_session<I: IdentityStore>(
    State(state): State<AppState<I>>,
    Json(request): Json<UpgradeRequest>,
) -> Result<Json<Upgraded>, HttpFailure> {
    let user = state
        .identity
        .upgrade(&request.guest_token, &request.account_token)
        .await
        .map_err(HttpFailure)?;
    Ok(Json(Upgraded { user }))
}
