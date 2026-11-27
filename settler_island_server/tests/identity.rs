mod common;

use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::{Json, Router};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use common::{guest_session, start, test_config, Client, TEST_SESSION_SECRET};
use hmac::{Hmac, Mac};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use rsa::pkcs1::EncodeRsaPrivateKey;
use rsa::traits::PublicKeyParts;
use rsa::RsaPrivateKey;
use serde_json::{json, Value};
use settler_island_protocol::{
    ClientMessage, ErrorCode, HttpError, SeatOccupant, ServerMessage, UpgradeRequest, Upgraded,
    UserKind,
};
use settler_island_server::{Config, KeycloakConfig};
use sha2::Sha256;

const AUDIENCE: &str = "settler-island-server";
const KID: &str = "realm-key-1";

/// Generated once per test run; the realm publishes only the first, the second plays a forger.
static KEYS: LazyLock<[RsaPrivateKey; 2]> = LazyLock::new(|| {
    let mut rng = rsa::rand_core::OsRng;
    [
        RsaPrivateKey::new(&mut rng, 2048).unwrap(),
        RsaPrivateKey::new(&mut rng, 2048).unwrap(),
    ]
});

struct Realm {
    issuer: String,
    jwks_requests: Arc<AtomicUsize>,
}

/// How the realm's JWKS endpoint misbehaves: the first `failures` requests answer 500, every answer takes `delay`.
#[derive(Default, Clone, Copy)]
struct RealmBehaviour {
    failures: usize,
    delay: Duration,
}

/// Serves the trusted key as the realm's JWKS on an ephemeral port.
async fn start_realm(behaviour: RealmBehaviour) -> Realm {
    let public = KEYS[0].to_public_key();
    let jwks = json!({"keys": [
        {"kid": "encryption-key", "kty": "RSA", "use": "enc", "alg": "RSA-OAEP",
         "n": URL_SAFE_NO_PAD.encode(public.n().to_bytes_be()),
         "e": URL_SAFE_NO_PAD.encode(public.e().to_bytes_be())},
        {"kid": KID, "kty": "RSA", "use": "sig", "alg": "RS256",
         "n": URL_SAFE_NO_PAD.encode(public.n().to_bytes_be()),
         "e": URL_SAFE_NO_PAD.encode(public.e().to_bytes_be())},
    ]});
    let jwks_requests = Arc::new(AtomicUsize::new(0));
    let counter = jwks_requests.clone();
    let app = Router::new().route(
        "/realms/test/protocol/openid-connect/certs",
        get(move || {
            let request = counter.fetch_add(1, Ordering::SeqCst);
            let jwks = jwks.clone();
            async move {
                tokio::time::sleep(behaviour.delay).await;
                if request < behaviour.failures {
                    return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                }
                Json(jwks).into_response()
            }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    Realm {
        issuer: format!("http://{address}/realms/test"),
        jwks_requests,
    }
}

async fn start_with_realm() -> (SocketAddr, Realm) {
    start_with_misbehaving_realm(RealmBehaviour::default()).await
}

async fn start_with_misbehaving_realm(behaviour: RealmBehaviour) -> (SocketAddr, Realm) {
    let realm = start_realm(behaviour).await;
    let config = Config {
        keycloak: Some(KeycloakConfig {
            issuer: realm.issuer.clone(),
            audience: AUDIENCE.to_string(),
        }),
        ..test_config()
    };
    (start(config).await, realm)
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

impl Realm {
    fn claims(&self, subject: &str, username: &str) -> Value {
        json!({
            "sub": subject,
            "iss": self.issuer,
            "aud": ["account", AUDIENCE],
            "exp": now() + 300,
            "iat": now(),
            "preferred_username": username,
        })
    }

    fn token(&self, subject: &str, username: &str) -> String {
        sign(&KEYS[0], KID, &self.claims(subject, username))
    }
}

fn sign(key: &RsaPrivateKey, kid: &str, claims: &Value) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some(kid.to_string());
    let der = key.to_pkcs1_der().unwrap();
    encode(&header, claims, &EncodingKey::from_rsa_der(der.as_bytes())).unwrap()
}

fn authenticate(token: &str) -> impl FnOnce(u32) -> ClientMessage {
    let token = token.to_string();
    move |request_id| ClientMessage::Authenticate { request_id, token }
}

async fn rejection(address: SocketAddr, token: &str) -> ErrorCode {
    let mut client = Client::connect(address).await;
    client.expect_error(authenticate(token)).await
}

async fn upgrade(address: SocketAddr, guest_token: &str, account_token: &str) -> reqwest::Response {
    let request = UpgradeRequest {
        guest_token: guest_token.to_string(),
        account_token: account_token.to_string(),
    };
    reqwest::Client::new()
        .post(format!("http://{address}/api/v1/sessions/upgrade"))
        .json(&request)
        .send()
        .await
        .unwrap()
}

/// A guest token signed with the test secret, so the test controls every claim.
fn guest_token(claims: &Value) -> String {
    let payload = URL_SAFE_NO_PAD.encode(claims.to_string());
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(TEST_SESSION_SECRET).unwrap();
    mac.update(payload.as_bytes());
    let signature = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());
    format!("guest.{payload}.{signature}")
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn account_tokens_must_be_signed_by_the_realm_for_us_and_unexpired() {
    let (address, realm) = start_with_realm().await;

    let (_, user) = Client::authenticated(address, &realm.token("sub-1", "kim")).await;
    assert_eq!((user.name.as_str(), user.kind), ("kim", UserKind::Account));
    assert!(!user.id.0.contains("sub-1"));

    let mut expired = realm.claims("sub-1", "kim");
    expired["exp"] = json!(now() - 600);
    let mut wrong_issuer = realm.claims("sub-1", "kim");
    wrong_issuer["iss"] = json!("http://127.0.0.1:1/realms/other");
    let mut wrong_audience = realm.claims("sub-1", "kim");
    wrong_audience["aud"] = json!(["account", "some-other-api"]);
    let mut not_yet_valid = realm.claims("sub-1", "kim");
    not_yet_valid["nbf"] = json!(now() + 600);
    let forged = sign(&KEYS[1], KID, &realm.claims("sub-1", "kim"));
    let unsigned = format!(
        "{}.{}.",
        URL_SAFE_NO_PAD.encode(r#"{"alg":"none","kid":"realm-key-1"}"#),
        forged.split('.').nth(1).unwrap()
    );
    for token in [
        sign(&KEYS[0], KID, &expired),
        sign(&KEYS[0], KID, &wrong_issuer),
        sign(&KEYS[0], KID, &wrong_audience),
        sign(&KEYS[0], KID, &not_yet_valid),
        forged,
        unsigned,
    ] {
        assert_eq!(rejection(address, &token).await, ErrorCode::InvalidToken);
    }

    let guests_only = start(test_config()).await;
    assert_eq!(
        rejection(guests_only, &realm.token("sub-1", "kim")).await,
        ErrorCode::AccountsDisabled
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn realm_keys_are_cached_and_unknown_key_ids_cannot_force_refetches() {
    let (address, realm) = start_with_realm().await;
    let unknown = sign(&KEYS[0], "rotated-key", &realm.claims("sub-1", "kim"));

    assert_eq!(rejection(address, &unknown).await, ErrorCode::InvalidToken);
    Client::authenticated(address, &realm.token("sub-1", "kim")).await;
    assert_eq!(rejection(address, &unknown).await, ErrorCode::InvalidToken);

    assert_eq!(realm.jwks_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_failed_key_fetch_is_a_server_error_and_backs_off_further_fetches() {
    let (address, realm) = start_with_misbehaving_realm(RealmBehaviour {
        failures: 1,
        ..RealmBehaviour::default()
    })
    .await;
    let token = realm.token("sub-1", "kim");

    assert_eq!(rejection(address, &token).await, ErrorCode::Internal);
    assert_eq!(rejection(address, &token).await, ErrorCode::Internal);

    assert_eq!(realm.jwks_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn concurrent_first_logins_share_one_key_fetch() {
    let (address, realm) = start_with_misbehaving_realm(RealmBehaviour {
        delay: Duration::from_millis(300),
        ..RealmBehaviour::default()
    })
    .await;
    let token = realm.token("sub-1", "kim");

    let logins = (0..4).map(|_| Client::authenticated(address, &token));
    futures_util::future::join_all(logins).await;

    assert_eq!(realm.jwks_requests.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tampered_and_expired_guest_tokens_are_rejected() {
    let address = start(test_config()).await;
    let session = guest_session(address, "Ada").await;
    let valid = json!({"id": guest_user_id(&session.token), "name": "Ada", "kind": "Guest", "expires": now() + 60});
    assert_eq!(
        Client::authenticated(address, &guest_token(&valid)).await.1,
        session.user
    );

    let mut expired = valid.clone();
    expired["expires"] = json!(now() - 1);
    let (payload, signature) = session.token["guest.".len()..].split_once('.').unwrap();
    let mut claims: Value =
        serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload).unwrap()).unwrap();
    claims["id"] = json!("someone-else");
    let tampered = format!(
        "guest.{}.{signature}",
        URL_SAFE_NO_PAD.encode(claims.to_string())
    );
    for token in [guest_token(&expired), tampered] {
        assert_eq!(rejection(address, &token).await, ErrorCode::InvalidToken);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_blank_guest_name_is_refused() {
    let address = start(test_config()).await;
    let response = reqwest::Client::new()
        .post(format!("http://{address}/api/v1/sessions/guest"))
        .json(&json!({"name": "   "}))
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
    let error: HttpError = response.json().await.unwrap();
    assert_eq!(error.code, ErrorCode::InvalidName);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_guest_and_an_account_play_in_one_lobby() {
    let (address, realm) = start_with_realm().await;
    let (mut guest, guest_user) = Client::welcomed(address, "Ada").await;
    let (mut account, account_user) =
        Client::authenticated(address, &realm.token("sub-2", "kim")).await;
    let lobby = guest.create_lobby("Mixed", 3, None).await;
    account.try_join(lobby, None).await.unwrap();
    guest
        .expect_lobby(|request_id| ClientMessage::AddBot {
            request_id,
            difficulty: settler_island_protocol::Difficulty::Random,
        })
        .await;

    let details = guest
        .expect_lobby(|request_id| ClientMessage::StartGame { request_id })
        .await;
    assert_eq!(details.seats[0], SeatOccupant::Human { user: guest_user });
    assert_eq!(details.seats[1], SeatOccupant::Human { user: account_user });
    let action = guest.next_game_started().await.legal_actions[0].clone();
    guest
        .send(|request_id| ClientMessage::Act { request_id, action })
        .await;
    loop {
        if let ServerMessage::GameUpdate { events, .. } = account.receive().await {
            assert!(!events.is_empty());
            break;
        }
    }
}

/// The user id a guest token carries; only its holder may know it.
fn guest_user_id(token: &str) -> String {
    let (payload, _) = token["guest.".len()..].split_once('.').unwrap();
    let claims: Value = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload).unwrap()).unwrap();
    claims["id"].as_str().unwrap().to_string()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn players_see_each_other_only_by_public_id() {
    let (address, realm) = start_with_realm().await;
    let session = guest_session(address, "Ada").await;
    let guest_id = guest_user_id(&session.token);
    let subject = "subject-never-shown";
    let (mut guest, guest_user) = Client::authenticated(address, &session.token).await;
    let (mut account, account_user) =
        Client::authenticated(address, &realm.token(subject, "kim")).await;
    assert_eq!(guest_user, session.user);
    assert_ne!(guest_user.id, account_user.id);

    let lobby = guest.create_lobby("Masked", 3, None).await;
    let listed = account
        .request(|request_id| ClientMessage::ListLobbies {
            request_id,
            page: 0,
            per_page: 10,
        })
        .await;
    let ServerMessage::Lobbies { lobbies, .. } = listed else {
        panic!("expected Lobbies, got {listed:?}");
    };
    assert_eq!(lobbies[0].info.owner, guest_user);
    let joined = account.try_join(lobby, None).await.unwrap();
    assert_eq!(
        joined.seats[0],
        SeatOccupant::Human {
            user: guest_user.clone()
        }
    );
    guest
        .expect_lobby(|request_id| ClientMessage::AddBot {
            request_id,
            difficulty: settler_island_protocol::Difficulty::Random,
        })
        .await;
    let started = guest
        .expect_lobby(|request_id| ClientMessage::StartGame { request_id })
        .await;
    assert_eq!(
        started.seats[1],
        SeatOccupant::Human {
            user: account_user.clone()
        }
    );
    account.next_game_started().await;
    for client in [&mut guest, &mut account] {
        client
            .request(|request_id| ClientMessage::GetRecord { request_id })
            .await;
    }

    for text in guest.received.iter().chain(&account.received) {
        assert!(!text.contains(&guest_id), "a guest id leaked: {text}");
        assert!(!text.contains(subject), "an account id leaked: {text}");
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_upgraded_guest_keeps_its_user_id_as_an_account() {
    let (address, realm) = start_with_realm().await;
    let session = guest_session(address, "Ada").await;
    let account_token = realm.token("sub-3", "ada-account");

    let response = upgrade(address, &session.token, &account_token).await;
    assert_eq!(response.status(), reqwest::StatusCode::OK);
    let upgraded: Upgraded = response.json().await.unwrap();
    assert_eq!(upgraded.user.id, session.user.id);
    assert_eq!(upgraded.user.kind, UserKind::Account);
    let (_, user) = Client::authenticated(address, &account_token).await;
    assert_eq!(user, upgraded.user);

    let other_guest = guest_session(address, "Eve").await;
    let response = upgrade(address, &other_guest.token, &account_token).await;
    assert_eq!(response.status(), reqwest::StatusCode::CONFLICT);
    let response = upgrade(address, "guest.forged.token", &account_token).await;
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_upgraded_guests_token_no_longer_authenticates_nor_upgrades_again() {
    let (address, realm) = start_with_realm().await;
    let session = guest_session(address, "Ada").await;
    let response = upgrade(address, &session.token, &realm.token("sub-owner", "ada")).await;
    assert_eq!(response.status(), reqwest::StatusCode::OK);

    assert_eq!(
        rejection(address, &session.token).await,
        ErrorCode::InvalidToken
    );
    let response = upgrade(address, &session.token, &realm.token("sub-thief", "eve")).await;
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
    let (_, user) = Client::authenticated(address, &realm.token("sub-thief", "eve")).await;
    assert_ne!(user.id, session.user.id);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_new_connection_takes_over_the_running_game() {
    let address = start(test_config()).await;
    let session = guest_session(address, "Ada").await;
    let (mut first, user) = Client::authenticated(address, &session.token).await;
    let (mut other, _) = Client::welcomed(address, "Bob").await;
    let lobby = first.create_lobby("Rejoin", 3, None).await;
    other.try_join(lobby, None).await.unwrap();
    first
        .expect_lobby(|request_id| ClientMessage::AddBot {
            request_id,
            difficulty: settler_island_protocol::Difficulty::Random,
        })
        .await;
    first
        .expect_lobby(|request_id| ClientMessage::StartGame { request_id })
        .await;

    let (mut second, same_user) = Client::authenticated(address, &session.token).await;
    assert_eq!(same_user, user);
    second.try_join(lobby, None).await.unwrap();
    assert_eq!(second.next_game_started().await.seat, 0);

    // The replaced connection closing must not hand the seat to a bot.
    drop(first);
    // Deliberate wait: there is no event when the server does nothing, so give a wrong handover time to show.
    tokio::time::sleep(Duration::from_millis(300)).await;
    let details = second
        .expect_lobby(|request_id| ClientMessage::GetState { request_id })
        .await;
    assert_eq!(details.seats[0], SeatOccupant::Human { user });
}
