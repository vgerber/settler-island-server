use std::future::Future;
use std::time::Duration;

use axum::extract::connect_info::ConnectInfo;
use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Router};
use hyper_util::rt::{TokioExecutor, TokioIo, TokioTimer};
use hyper_util::server::conn::auto::Builder;
use hyper_util::server::graceful::GracefulShutdown;
use hyper_util::service::TowerToHyperService;
use tokio::net::TcpListener;
use tokio::sync::watch;
use tracing::{debug, info, warn};

/// A client that has not finished its request head by then is dropped (slowloris).
const HEADER_READ_TIMEOUT: Duration = Duration::from_secs(10);
/// Connections still open this long after shutdown began are abandoned.
const SHUTDOWN_GRACE: Duration = Duration::from_secs(10);

const METRICS_PATH: &str = "/metrics";

/// Serves `router` on `listener` until `shutdown` completes. With `metrics_listener`, `/metrics` is answered only
/// there and the game listener returns 404 for it.
pub async fn serve_router(
    listener: TcpListener,
    metrics_listener: Option<TcpListener>,
    router: Router,
    shutdown: impl Future<Output = ()> + Send + 'static,
) {
    let (stop_sender, stop_receiver) = watch::channel(false);
    let mut tasks = tokio::task::JoinSet::new();
    let game_router = match metrics_listener {
        Some(metrics_listener) => {
            let metrics_router = router.clone().layer(middleware::from_fn(only_metrics));
            tasks.spawn(accept_loop(
                metrics_listener,
                metrics_router,
                stop_receiver.clone(),
            ));
            router.layer(middleware::from_fn(hide_metrics))
        }
        None => router,
    };
    tasks.spawn(accept_loop(listener, game_router, stop_receiver));
    shutdown.await;
    info!("shutting down");
    stop_sender.send_replace(true);
    while tasks.join_next().await.is_some() {}
}

async fn only_metrics(request: Request, next: Next) -> Response {
    if request.uri().path() != METRICS_PATH {
        return StatusCode::NOT_FOUND.into_response();
    }
    next.run(request).await
}

async fn hide_metrics(request: Request, next: Next) -> Response {
    if request.uri().path() == METRICS_PATH {
        return StatusCode::NOT_FOUND.into_response();
    }
    next.run(request).await
}

async fn accept_loop(listener: TcpListener, router: Router, mut stop: watch::Receiver<bool>) {
    let mut builder = Builder::new(TokioExecutor::new());
    builder
        .http1()
        .timer(TokioTimer::new())
        .header_read_timeout(HEADER_READ_TIMEOUT);
    let graceful = GracefulShutdown::new();
    loop {
        let accepted = tokio::select! {
            accepted = listener.accept() => accepted,
            _ = stop.changed() => break,
        };
        let (stream, peer) = match accepted {
            Ok(accepted) => accepted,
            Err(error) => {
                warn!(%error, "accepting a connection failed");
                // Typically file descriptor exhaustion; spinning would only burn CPU.
                tokio::time::sleep(Duration::from_millis(100)).await;
                continue;
            }
        };
        let service = TowerToHyperService::new(router.clone().layer(Extension(ConnectInfo(peer))));
        let connection = builder.serve_connection_with_upgrades(TokioIo::new(stream), service);
        let connection = graceful.watch(connection.into_owned());
        tokio::spawn(async move {
            if let Err(error) = connection.await {
                debug!(%error, %peer, "connection ended with an error");
            }
        });
    }
    if tokio::time::timeout(SHUTDOWN_GRACE, graceful.shutdown())
        .await
        .is_err()
    {
        warn!("connections still open after the shutdown grace, dropping them");
    }
}
