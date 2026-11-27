mod common;

use std::time::Duration;

use common::{
    guest_session, server_runtime, start, start_with, test_config, test_database, Client,
    SharedStore,
};
use settler_island_protocol::{
    AwayPolicy, ClientMessage, Difficulty, LobbyId, SeatOccupant, ServerMessage, User,
};
use settler_island_server::{GameStore, MemoryIdentityStore, PoolSettings, PostgresStore};

/// Long enough for a bot with no delay to have moved many times.
const QUIET: Duration = Duration::from_millis(300);

fn create_waiting(request_id: u32) -> ClientMessage {
    ClientMessage::CreateLobby {
        request_id,
        name: "Patient".to_string(),
        password: None,
        seats: 3,
        points_to_win: None,
        bot_difficulty: None,
        away_policy: Some(AwayPolicy::WaitForPlayer),
    }
}

/// Fails on any game update within `QUIET`: the game must stand still.
async fn assert_no_move(client: &mut Client) {
    let deadline = tokio::time::Instant::now() + QUIET;
    while let Ok(message) = tokio::time::timeout_at(deadline, client.receive()).await {
        assert!(
            !matches!(message, ServerMessage::GameUpdate { .. }),
            "a seat moved while the game waited: {message:?}"
        );
    }
}

/// Owner (seat 0) and guest (seat 1) plus a bot start a `WaitForPlayer` game; returns the lobby.
async fn start_waiting_game(owner: &mut Client, guest: &mut Client) -> LobbyId {
    let lobby = owner.expect_lobby(create_waiting).await.info.id;
    guest.try_join(lobby, None).await.unwrap();
    owner
        .expect_lobby(|request_id| ClientMessage::AddBot {
            request_id,
            difficulty: Difficulty::Random,
        })
        .await;
    owner
        .expect_lobby(|request_id| ClientMessage::StartGame { request_id })
        .await;
    assert_eq!(guest.next_game_started().await.seat, 1);
    lobby
}

/// The away owner rejoins, gets seat 0 with its first placement to make, and the guest sees the move.
async fn rejoin_and_continue(
    owner: &mut Client,
    owner_user: User,
    guest: &mut Client,
    lobby: LobbyId,
) {
    let rejoined = owner.try_join(lobby, None).await.unwrap();
    assert_eq!(rejoined.seats[0], SeatOccupant::Human { user: owner_user });
    let dealt = owner.next_game_started().await;
    assert_eq!(dealt.seat, 0);
    let action = dealt.legal_actions[0].clone();
    owner
        .send(|request_id| ClientMessage::Act { request_id, action })
        .await;
    guest.next_game_update().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn wait_for_player_stops_the_game_while_the_pending_seat_is_away_until_they_rejoin() {
    let address = start(test_config()).await;
    let (mut owner, owner_user) = Client::welcomed(address, "Owner").await;
    let (mut guest, _) = Client::welcomed(address, "Guest").await;
    let lobby = start_waiting_game(&mut owner, &mut guest).await;

    // Seat 0 must place first; its player leaves.
    owner
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    let details = guest.next_lobby_state().await;
    assert_eq!(details.info.away_policy, AwayPolicy::WaitForPlayer);
    assert_eq!(
        details.seats[0],
        SeatOccupant::Away {
            user: owner_user.clone()
        }
    );
    assert_no_move(&mut guest).await;

    rejoin_and_continue(&mut owner, owner_user, &mut guest, lobby).await;
}

fn pool_settings() -> PoolSettings {
    PoolSettings {
        max_connections: 4,
        acquire_timeout: Duration::from_secs(2),
    }
}

/// Starts a `WaitForPlayer` game on one server, stops it, and checks the restored game still waits for seat 0.
fn restart_keeps_waiting_for_the_player(store: impl GameStore + Clone) {
    let client_runtime = server_runtime();
    let server_a = server_runtime();
    let address_a = server_a.block_on(start_with(
        test_config(),
        store.clone(),
        MemoryIdentityStore::default(),
    ));
    let (owner_token, guest_token, lobby) = client_runtime.block_on(async {
        let owner_session = guest_session(address_a, "Owner").await;
        let guest_session = guest_session(address_a, "Guest").await;
        let (mut owner, _) = Client::authenticated(address_a, &owner_session.token).await;
        let (mut guest, _) = Client::authenticated(address_a, &guest_session.token).await;
        let lobby = start_waiting_game(&mut owner, &mut guest).await;
        (owner_session.token, guest_session.token, lobby)
    });
    drop(server_a);

    let server_b = server_runtime();
    // Guest tokens are signed, so a fresh identity store accepts them.
    let address_b = server_b.block_on(start_with(
        test_config(),
        store,
        MemoryIdentityStore::default(),
    ));
    client_runtime.block_on(async {
        let (mut guest, _) = Client::authenticated(address_b, &guest_token).await;
        let details = guest.try_join(lobby, None).await.unwrap();
        assert_eq!(details.info.away_policy, AwayPolicy::WaitForPlayer);
        let SeatOccupant::Away { user: owner_user } = details.seats[0].clone() else {
            panic!(
                "a restored human seat must wait, got {:?}",
                details.seats[0]
            );
        };
        guest.next_game_started().await;
        assert_no_move(&mut guest).await;

        let (mut owner, _) = Client::authenticated(address_b, &owner_token).await;
        rejoin_and_continue(&mut owner, owner_user, &mut guest, lobby).await;
    });
}

#[test]
fn a_restored_game_keeps_waiting_for_its_away_player() {
    restart_keeps_waiting_for_the_player(SharedStore::default());
}

#[test]
fn postgres_a_restored_game_keeps_waiting_for_its_away_player() {
    let client_runtime = server_runtime();
    let Some(database) = client_runtime.block_on(test_database()) else {
        return;
    };
    let store = client_runtime
        .block_on(PostgresStore::connect(database.options(), pool_settings()))
        .unwrap();
    restart_keeps_waiting_for_the_player(store);
}
