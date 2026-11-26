//! Authoritative game server: axum hosts the WebSocket, actors own connections, the lobby list and each lobby.

mod config;
mod connection;
mod connection_limit;
mod identity;
mod lobby;
mod metrics;
mod names;
mod outbox;
mod password;
mod postgres;
mod rate_limit;
mod registry;
mod store;

use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::rejection::JsonRejection;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{ConnectInfo, DefaultBodyLimit, FromRequest, Request, State};
use axum::http::{header, Extensions, HeaderMap, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::de::DeserializeOwned;
use serde::Serialize;
use settler_island_protocol::{
    ErrorCode, GuestSession, GuestSessionRequest, HttpError, ServerLimit, UpgradeRequest, Upgraded,
    GUEST_SESSION_ROUTE, HEALTH_ROUTE, MAX_MESSAGE_BYTES, UPGRADE_SESSION_ROUTE, WEBSOCKET_ROUTE,
};
use tokio::net::TcpListener;
use tower_http::timeout::{RequestBodyTimeoutLayer, TimeoutLayer};

pub use config::{
    Config, ConfigError, DatabaseUrl, KeycloakConfig, LogFormat, SessionSecret,
    MIN_SESSION_SECRET_BYTES, VARIABLES,
};
pub use identity::{IdentityStore, IdentityStoreError, MemoryIdentityStore};
pub use metrics::MetricsError;
pub use postgres::PostgresStore;
pub use store::{
    wants_snapshot, GameId, GameStore, MemoryStore, NewGame, RebuildError, SeatPlayer, Snapshot,
    StoreError, StoredGame, SNAPSHOT_INTERVAL,
};

use connection_limit::ConnectionLimiter;
use identity::Identity;
use metrics::Metrics;
use rate_limit::IpLimiter;
use registry::RegistryHandle;

/// Messages slightly above `MAX_MESSAGE_BYTES` still arrive and get an error reply; beyond this the socket is dropped.
const MAX_FRAME_BYTES: usize = MAX_MESSAGE_BYTES + 8 * 1024;
/// tungstenite's 128 KiB defaults cost about 146 KB per idle socket; frames grow the read buffer on demand.
const SOCKET_BUFFER_BYTES: usize = 4 * 1024;
/// Session bodies are a name or two tokens; a Keycloak access token can reach a few KB.
const MAX_SESSION_BODY_BYTES: usize = 8 * 1024;
/// Whole-request and body-read deadline on the plain HTTP routes, so a stalled client cannot hold a handler.
const HTTP_REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

struct AppState<I> {
    registry: RegistryHandle,
    identity: Arc<Identity<I>>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    session_limiter: Arc<IpLimiter>,
    connection_limiter: Arc<ConnectionLimiter>,
}

// Derived `Clone` would needlessly require `I: Clone`.
impl<I> Clone for AppState<I> {
    fn clone(&self) -> AppState<I> {
        AppState {
            registry: self.registry.clone(),
            identity: self.identity.clone(),
            config: self.config.clone(),
            metrics: self.metrics.clone(),
            session_limiter: self.session_limiter.clone(),
            connection_limiter: self.connection_limiter.clone(),
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
            ErrorCode::RateLimited => StatusCode::TOO_MANY_REQUESTS,
            ErrorCode::MessageTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            ErrorCode::LimitReached {
                limit: ServerLimit::Connections | ServerLimit::RunningGames,
            } => StatusCode::SERVICE_UNAVAILABLE,
            ErrorCode::LimitReached { .. } => StatusCode::TOO_MANY_REQUESTS,
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

/// `Json` whose rejections (too large, malformed, wrong content type) answer in the `HttpError` shape.
struct JsonBody<T>(T);

impl<T: DeserializeOwned, S: Send + Sync> FromRequest<S> for JsonBody<T> {
    type Rejection = HttpFailure;

    async fn from_request(request: Request, state: &S) -> Result<JsonBody<T>, HttpFailure> {
        Json::<T>::from_request(request, state)
            .await
            .map(|Json(value)| JsonBody(value))
            .map_err(rejected_body)
    }
}

fn rejected_body(rejection: JsonRejection) -> HttpFailure {
    tracing::debug!(%rejection, "session request body rejected");
    if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
        return HttpFailure(ErrorCode::MessageTooLarge);
    }
    HttpFailure(ErrorCode::InvalidMessage)
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
        session_limiter: Arc::new(IpLimiter::new(
            config.session_requests_per_minute,
            config.session_burst,
        )),
        connection_limiter: Arc::new(ConnectionLimiter::new(
            config.max_connections,
            config.max_connections_per_ip,
        )),
        config,
        metrics,
    };
    let sessions = Router::new()
        .route(GUEST_SESSION_ROUTE, post(guest_session::<I>))
        .route(UPGRADE_SESSION_ROUTE, post(upgrade_session::<I>))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            limit_sessions::<I>,
        ))
        .layer(DefaultBodyLimit::max(MAX_SESSION_BODY_BYTES));
    // The WebSocket route stays outside the timeouts: its handler returns at once and the socket outlives it.
    let http_routes = Router::new()
        .route(HEALTH_ROUTE, get(health))
        .route("/metrics", get(metrics_page::<I>))
        .merge(sessions)
        .layer(RequestBodyTimeoutLayer::new(HTTP_REQUEST_TIMEOUT))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            HTTP_REQUEST_TIMEOUT,
        ));
    let router = Router::new()
        .route(WEBSOCKET_ROUTE, get(upgrade::<I>))
        .merge(http_routes)
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
    axum::serve(
        listener,
        router.into_make_service_with_connect_info::<SocketAddr>(),
    )
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

/// Refuses a connection over the caps with an HTTP error before upgrading, so a refused client costs no socket state.
async fn upgrade<I: IdentityStore>(
    State(state): State<AppState<I>>,
    headers: HeaderMap,
    extensions: Extensions,
    upgrade: WebSocketUpgrade,
) -> Response {
    let Some(address) = client_address(&headers, &extensions, state.config.trust_forwarded_for)
    else {
        // Only reachable when the router is served without connect info.
        tracing::error!("upgrade request without a client address");
        return HttpFailure(ErrorCode::Internal).into_response();
    };
    let permit = match state.connection_limiter.acquire(address) {
        Ok(permit) => permit,
        Err(limit) => {
            let code = ErrorCode::LimitReached { limit };
            state.metrics.error(&code);
            return HttpFailure(code).into_response();
        }
    };
    upgrade
        .max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .read_buffer_size(SOCKET_BUFFER_BYTES)
        .write_buffer_size(SOCKET_BUFFER_BYTES)
        .on_upgrade(move |socket| async move {
            connection::run(
                socket,
                state.registry,
                state.identity,
                state.config,
                state.metrics,
            )
            .await;
            // Moved in and dropped here so the slot stays taken for the socket's whole lifetime.
            drop(permit);
        })
}

async fn guest_session<I: IdentityStore>(
    State(state): State<AppState<I>>,
    JsonBody(request): JsonBody<GuestSessionRequest>,
) -> Result<Json<GuestSession>, HttpFailure> {
    state
        .identity
        .guest_session(&request.name)
        .map(Json)
        .map_err(HttpFailure)
}

async fn upgrade_session<I: IdentityStore>(
    State(state): State<AppState<I>>,
    JsonBody(request): JsonBody<UpgradeRequest>,
) -> Result<Json<Upgraded>, HttpFailure> {
    let user = state
        .identity
        .upgrade(&request.guest_token, &request.account_token)
        .await
        .map_err(HttpFailure)?;
    Ok(Json(Upgraded { user }))
}

/// The caller's address: the socket peer, or the last `X-Forwarded-For` entry (the one the trusted proxy appended;
/// earlier entries come from the client and can be forged).
fn client_address(
    headers: &HeaderMap,
    extensions: &Extensions,
    trust_forwarded_for: bool,
) -> Option<IpAddr> {
    if trust_forwarded_for {
        let forwarded = headers
            .get("x-forwarded-for")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.rsplit(',').next())
            .and_then(|value| value.trim().parse().ok());
        if forwarded.is_some() {
            return forwarded;
        }
    }
    extensions
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ConnectInfo(peer)| peer.ip())
}

async fn limit_sessions<I: IdentityStore>(
    State(state): State<AppState<I>>,
    request: Request,
    next: Next,
) -> Response {
    let trust_forwarded_for = state.config.trust_forwarded_for;
    let Some(address) =
        client_address(request.headers(), request.extensions(), trust_forwarded_for)
    else {
        // Only reachable when the router is served without connect info.
        tracing::error!("session request without a client address");
        return HttpFailure(ErrorCode::Internal).into_response();
    };
    let Err(retry_after) = state.session_limiter.check(address, Instant::now()) else {
        return next.run(request).await;
    };
    state.metrics.error(&ErrorCode::RateLimited);
    let mut response = HttpFailure(ErrorCode::RateLimited).into_response();
    let seconds = retry_after.as_secs() + 1;
    if let Ok(value) = HeaderValue::from_str(&seconds.to_string()) {
        response.headers_mut().insert(header::RETRY_AFTER, value);
    }
    response
}
