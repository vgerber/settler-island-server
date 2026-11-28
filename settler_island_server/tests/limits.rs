mod common;

use std::net::SocketAddr;

use common::{eventually, start, test_config, Client};
use settler_island_protocol::{ErrorCode, HttpError, ServerLimit};
use settler_island_server::Config;
use tokio_tungstenite::tungstenite;

/// The refused upgrade's HTTP status and JSON body; panics when the upgrade succeeded.
async fn refused_upgrade(address: SocketAddr) -> (u16, HttpError) {
    let Err(error) = Client::try_connect(address).await else {
        panic!("the upgrade was accepted");
    };
    let tungstenite::Error::Http(response) = *error else {
        panic!("expected an HTTP refusal, got {error:?}");
    };
    let body = response.body().as_deref().unwrap_or_default();
    (
        response.status().as_u16(),
        serde_json::from_slice(body).unwrap(),
    )
}

async fn post_guest_body(address: SocketAddr, body: String) -> reqwest::Response {
    reqwest::Client::new()
        .post(format!("http://{address}/api/v1/sessions/guest"))
        .header("content-type", "application/json")
        .body(body)
        .send()
        .await
        .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_frame_far_above_the_message_limit_closes_the_socket() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Flooder").await;

    client.send_raw_unchecked("x".repeat(200 * 1024)).await;

    assert!(client.closed_by_server().await);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_connection_beyond_the_per_address_limit_is_refused_until_one_closes() {
    let config = Config {
        max_connections_per_ip: 2,
        ..test_config()
    };
    let address = start(config).await;
    let first = Client::connect(address).await;
    let _second = Client::connect(address).await;

    let (status, error) = refused_upgrade(address).await;
    assert_eq!(status, 429);
    let per_address = ServerLimit::ConnectionsPerIp;
    assert_eq!(error.code, ErrorCode::LimitReached { limit: per_address });

    drop(first);
    eventually("the closed connection's slot", || async {
        Client::try_connect(address).await.ok()
    })
    .await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_connection_beyond_the_server_limit_is_refused() {
    let config = Config {
        max_connections: 1,
        ..test_config()
    };
    let address = start(config).await;
    let _first = Client::connect(address).await;

    let (status, error) = refused_upgrade(address).await;
    assert_eq!(status, 503);
    let server = ServerLimit::Connections;
    assert_eq!(error.code, ErrorCode::LimitReached { limit: server });
}

#[tokio::test]
async fn a_guest_body_above_the_limit_gets_a_json_413() {
    let address = start(test_config()).await;

    let body = format!(r#"{{"name":"{}"}}"#, "x".repeat(10 * 1024));
    let response = post_guest_body(address, body).await;

    assert_eq!(response.status().as_u16(), 413);
    let error: HttpError = response.json().await.unwrap();
    assert_eq!(error.code, ErrorCode::MessageTooLarge);
}

#[tokio::test]
async fn a_malformed_guest_body_gets_a_json_error() {
    let address = start(test_config()).await;

    let response = post_guest_body(address, r#"{"name":5}"#.to_string()).await;

    assert_eq!(response.status().as_u16(), 400);
    let error: HttpError = response.json().await.unwrap();
    assert_eq!(error.code, ErrorCode::InvalidMessage);
}
