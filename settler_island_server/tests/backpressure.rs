mod common;

use common::{echoed_request_id, guest_session, start, test_config, Client};
use settler_island_protocol::{ClientMessage, Difficulty, SeatOccupant, ServerMessage};
use settler_island_server::Config;

/// The server's byte budget per connection.
const OUTBOX_BUDGET_BYTES: usize = 256 * 1024;

/// What the kernel buffers between the server and a client with a 4 KiB receive buffer (about
/// 1.5 MB measured on loopback), on top of the outbox.
const SOCKET_BUFFER_SLACK_BYTES: usize = 2 * 1024 * 1024;

fn get_state(request_id: u32) -> ClientMessage {
    ClientMessage::GetState { request_id }
}

/// The serialized size of a `GetState` answer (lobby state and game state), which the attack below
/// multiplies.
async fn state_reply_bytes(client: &mut Client) -> usize {
    let request_id = client.send(get_state).await;
    let mut bytes = 0;
    loop {
        let message = client.receive().await;
        if echoed_request_id(&message) != Some(request_id) {
            continue;
        }
        bytes += serde_json::to_string(&message).unwrap().len();
        if matches!(message, ServerMessage::GameStarted { .. }) {
            return bytes;
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_client_that_never_reads_is_dropped_while_the_rest_of_its_game_plays_on() {
    let config = Config {
        // The flood must reach the outbox, not the rate limiter.
        messages_per_second: 100_000,
        ..test_config()
    };
    let address = start(config).await;
    let session = guest_session(address, "Staller").await;
    let mut staller = Client::connect_with_receive_buffer(address, 4096).await;
    staller.authenticate(&session.token).await;
    let (mut reader, _) = Client::welcomed(address, "Reader").await;
    let lobby = staller.create_lobby("Table", 3, None).await;
    reader.try_join(lobby, None).await.unwrap();
    staller.next_lobby_state().await;
    staller
        .expect_lobby(|request_id| ClientMessage::AddBot {
            request_id,
            difficulty: Difficulty::Random,
        })
        .await;
    staller
        .request(|request_id| ClientMessage::StartGame { request_id })
        .await;
    reader.next_game_started().await;
    let reply_bytes = state_reply_bytes(&mut reader).await;

    let sent = staller
        .send_unread_until_closed(5_000, get_state)
        .await
        .expect("the server never dropped the client that does not read");
    let requested_bytes = sent * reply_bytes;
    assert!(
        requested_bytes < OUTBOX_BUDGET_BYTES + SOCKET_BUFFER_SLACK_BYTES,
        "dropped only after {requested_bytes} bytes of answers"
    );

    // Seat 0 moves first; the bot that replaces the dropped client must play it.
    let details = reader.next_lobby_state().await;
    assert!(matches!(details.seats[0], SeatOccupant::Bot { .. }));
    reader.next_game_update().await;
    assert!(state_reply_bytes(&mut reader).await > 0);
}
