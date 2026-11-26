//! Runs the real binary: the serving loop lives in `main.rs`, not in the library.

use std::net::{SocketAddr, TcpListener as StdListener};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

struct Server {
    child: Child,
    game: SocketAddr,
    metrics: SocketAddr,
}

impl Drop for Server {
    fn drop(&mut self) {
        // The process is ours and may already be gone; there is nothing to do about a failed kill.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn free_address() -> SocketAddr {
    let listener = StdListener::bind("127.0.0.1:0").unwrap();
    listener.local_addr().unwrap()
}

async fn start() -> Server {
    let (game, metrics) = (free_address(), free_address());
    let child = Command::new(env!("CARGO_BIN_EXE_settler_island_server"))
        .env_clear()
        .env(
            "SETTLER_SESSION_SECRET",
            "http-server-test-secret-0123456789abcdef",
        )
        .env("SETTLER_BIND", game.to_string())
        .env("SETTLER_METRICS_BIND", metrics.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let server = Server {
        child,
        game,
        metrics,
    };
    let deadline = Instant::now() + Duration::from_secs(30);
    while TcpStream::connect(metrics).await.is_err() || TcpStream::connect(game).await.is_err() {
        assert!(Instant::now() < deadline, "the server did not start");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    server
}

async fn status_of(address: SocketAddr, path: &str) -> u16 {
    let response = reqwest::get(format!("http://{address}{path}"))
        .await
        .unwrap();
    response.status().as_u16()
}

#[tokio::test]
async fn metrics_are_served_only_on_the_metrics_listener() {
    let server = start().await;
    assert_eq!(status_of(server.metrics, "/metrics").await, 200);
    assert_eq!(status_of(server.game, "/metrics").await, 404);
    assert_eq!(status_of(server.game, "/api/v1/health").await, 200);
}

#[tokio::test]
async fn a_half_sent_request_line_is_closed_after_the_header_timeout() {
    let server = start().await;
    let mut socket = TcpStream::connect(server.game).await.unwrap();
    socket.write_all(b"GET /hea").await.unwrap();
    let started = Instant::now();
    let mut buffer = Vec::new();
    let outcome =
        tokio::time::timeout(Duration::from_secs(20), socket.read_to_end(&mut buffer)).await;
    assert!(
        outcome.is_ok(),
        "the stalled socket was still open after 20 s"
    );
    let waited = started.elapsed();
    assert!(
        waited >= Duration::from_secs(8),
        "closed after only {waited:?}"
    );
}
