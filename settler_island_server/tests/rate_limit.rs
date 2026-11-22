mod common;

use std::net::SocketAddr;

use common::{start, test_config};
use settler_island_protocol::{ErrorCode, GuestSessionRequest, HttpError};
use settler_island_server::Config;

async fn post_guest(address: SocketAddr, forwarded_for: Option<&str>) -> reqwest::Response {
    let request = GuestSessionRequest {
        name: "Ada".to_string(),
    };
    let mut builder = reqwest::Client::new()
        .post(format!("http://{address}/api/v1/sessions/guest"))
        .json(&request);
    if let Some(forwarded_for) = forwarded_for {
        builder = builder.header("x-forwarded-for", forwarded_for);
    }
    builder.send().await.unwrap()
}

#[tokio::test]
async fn session_routes_answer_429_past_the_burst_but_health_is_unlimited() {
    let config = Config {
        session_burst: 2,
        session_requests_per_minute: 1,
        ..test_config()
    };
    let address = start(config).await;

    assert_eq!(post_guest(address, None).await.status(), 200);
    assert_eq!(post_guest(address, None).await.status(), 200);
    let limited = post_guest(address, None).await;
    assert_eq!(limited.status(), 429);
    assert!(limited.headers().contains_key("retry-after"));
    let body: HttpError = limited.json().await.unwrap();
    assert_eq!(body.code, ErrorCode::RateLimited);

    for _ in 0..5 {
        let health = reqwest::get(format!("http://{address}/api/v1/health"))
            .await
            .unwrap();
        assert_eq!(health.status(), 200);
    }
}

#[tokio::test]
async fn forwarded_for_is_ignored_unless_trusted_and_then_separates_clients() {
    let limits = Config {
        session_burst: 1,
        session_requests_per_minute: 1,
        ..test_config()
    };
    let untrusted = start(limits.clone()).await;
    assert_eq!(post_guest(untrusted, Some("1.1.1.1")).await.status(), 200);
    assert_eq!(post_guest(untrusted, Some("2.2.2.2")).await.status(), 429);

    let trusted = start(Config {
        trust_forwarded_for: true,
        ..limits
    })
    .await;
    assert_eq!(post_guest(trusted, Some("1.1.1.1")).await.status(), 200);
    assert_eq!(post_guest(trusted, Some("2.2.2.2")).await.status(), 200);
    assert_eq!(post_guest(trusted, Some("1.1.1.1")).await.status(), 429);
}

#[tokio::test]
async fn forged_forwarded_for_entries_do_not_escape_the_limit() {
    let address = start(Config {
        trust_forwarded_for: true,
        session_burst: 1,
        session_requests_per_minute: 1,
        ..test_config()
    })
    .await;
    // The proxy appends the real client last; the client controls everything before it.
    let first = post_guest(address, Some("9.9.9.1, 3.3.3.3")).await;
    let forged = post_guest(address, Some("9.9.9.2, 3.3.3.3")).await;
    assert_eq!(first.status(), 200);
    assert_eq!(forged.status(), 429);
}
