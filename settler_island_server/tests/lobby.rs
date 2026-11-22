mod common;

use common::{start, test_config, Client};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, Event, SeatOccupant, ServerMessage,
};

fn add_bot(request_id: u32) -> ClientMessage {
    ClientMessage::AddBot {
        request_id,
        difficulty: Difficulty::Random,
    }
}

fn start_game(request_id: u32) -> ClientMessage {
    ClientMessage::StartGame { request_id }
}

fn leave(request_id: u32) -> ClientMessage {
    ClientMessage::LeaveLobby { request_id }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn only_the_owner_manages_bots_and_starts_and_every_member_gets_their_own_seat() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, guest_user) = Client::welcomed(address, "Guest").await;
    let lobby = owner.create_lobby("Table", 3, None).await;
    assert!(matches!(
        guest.join(lobby, None).await,
        ServerMessage::LobbyState { .. }
    ));

    assert_eq!(guest.expect_error(add_bot).await, ErrorCode::NotOwner);
    assert_eq!(guest.expect_error(start_game).await, ErrorCode::NotOwner);
    let details = owner.expect_lobby(add_bot).await;
    assert!(matches!(details.seats[2], SeatOccupant::Bot { .. }));
    assert_eq!(guest.next_lobby_state().await, details);
    let remove = |request_id| ClientMessage::RemoveBot {
        request_id,
        seat: 2,
    };
    assert_eq!(guest.expect_error(remove).await, ErrorCode::NotOwner);
    let remove_human = |request_id| ClientMessage::RemoveBot {
        request_id,
        seat: 1,
    };
    assert_eq!(owner.expect_error(remove_human).await, ErrorCode::NotABot);

    let start_id = owner.send(start_game).await;
    let owner_seat = loop {
        if let ServerMessage::GameStarted {
            request_id,
            seat,
            view,
            legal_actions,
        } = owner.receive().await
        {
            assert_eq!(request_id, Some(start_id));
            assert_eq!(view.own.map(|own| own.seat), Some(seat));
            assert!(!legal_actions.is_empty(), "seat 0 opens the setup");
            break seat;
        }
    };
    let guest_seat = loop {
        if let ServerMessage::GameStarted {
            request_id,
            seat,
            view,
            legal_actions,
        } = guest.receive().await
        {
            assert_eq!(request_id, None);
            assert_eq!(view.own.map(|own| own.seat), Some(seat));
            assert!(legal_actions.is_empty(), "the guest waits for seat 0");
            break seat;
        }
    };
    assert_eq!((owner_seat, guest_seat), (0, 1));
    assert_eq!(
        owner.expect_error(add_bot).await,
        ErrorCode::GameAlreadyStarted
    );
    let lobby_after = guest
        .expect_lobby(|request_id| ClientMessage::GetState { request_id })
        .await;
    assert!(lobby_after.started);
    assert_eq!(
        lobby_after.seats[1],
        SeatOccupant::Human { user: guest_user }
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn start_needs_every_seat_and_join_fails_when_full_or_started() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut outsider, _) = Client::welcomed(address, "Outsider").await;
    let lobby = owner.create_lobby("Table", 3, None).await;

    owner.expect_lobby(add_bot).await;
    assert_eq!(
        owner.expect_error(start_game).await,
        ErrorCode::SeatsNotFilled
    );
    owner.expect_lobby(add_bot).await;
    assert_eq!(owner.expect_error(add_bot).await, ErrorCode::LobbyFull);
    let ServerMessage::Error { code, .. } = outsider.join(lobby, None).await else {
        panic!("joining a full lobby must fail");
    };
    assert_eq!(code, ErrorCode::LobbyFull);

    let started = owner.expect_lobby(start_game).await;
    assert!(started.started);
    let ServerMessage::Error { code, .. } = outsider.join(lobby, None).await else {
        panic!("joining a started lobby must fail");
    };
    assert_eq!(code, ErrorCode::GameAlreadyStarted);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn the_next_member_owns_the_lobby_when_the_owner_leaves() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, guest_user) = Client::welcomed(address, "Guest").await;
    let lobby = owner.create_lobby("Table", 4, None).await;
    guest.join(lobby, None).await;

    let left = owner.request(leave).await;
    assert!(matches!(left, ServerMessage::LobbyLeft { .. }));
    let details = guest.next_lobby_state().await;
    assert_eq!(details.owner, guest_user);
    assert_eq!(details.seats[0], SeatOccupant::Open);
    guest.expect_lobby(add_bot).await;
    assert_eq!(owner.expect_error(add_bot).await, ErrorCode::NotInLobby);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_disconnected_member_frees_the_seat() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, _) = Client::welcomed(address, "Guest").await;
    let lobby = owner.create_lobby("Table", 3, None).await;
    guest.join(lobby, None).await;
    assert!(matches!(
        owner.next_lobby_state().await.seats[1],
        SeatOccupant::Human { .. }
    ));

    drop(guest);
    assert_eq!(owner.next_lobby_state().await.seats[1], SeatOccupant::Open);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_bot_plays_for_a_player_who_left_until_they_rejoin() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, guest_user) = Client::welcomed(address, "Guest").await;
    let (mut outsider, _) = Client::welcomed(address, "Outsider").await;
    let lobby = owner.create_lobby("Table", 3, None).await;
    guest.join(lobby, None).await;
    owner.expect_lobby(add_bot).await;
    owner.expect_lobby(start_game).await;

    guest.request(leave).await;
    let details = owner.next_lobby_state().await;
    assert_eq!(
        details.seats[1],
        SeatOccupant::Bot {
            difficulty: Difficulty::Random,
            reserved_for: Some(guest_user.clone()),
        }
    );
    let ServerMessage::Error { code, .. } = outsider.join(lobby, None).await else {
        panic!("only the reserved player may take the seat");
    };
    assert_eq!(code, ErrorCode::GameAlreadyStarted);

    // Seat 0 places its first settlement and road, then the replacement bot on seat 1 must move.
    owner
        .send(|request_id| ClientMessage::GetState { request_id })
        .await;
    let mut legal = loop {
        if let ServerMessage::GameStarted { legal_actions, .. } = owner.receive().await {
            break legal_actions;
        }
    };
    let mut bot_moved = false;
    while !bot_moved {
        if let Some(action) = legal.first().cloned() {
            owner
                .send(|request_id| ClientMessage::Act { request_id, action })
                .await;
            legal.clear();
        }
        if let ServerMessage::GameUpdate {
            events,
            legal_actions,
            ..
        } = owner.receive().await
        {
            bot_moved |= events
                .iter()
                .any(|event| matches!(event, Event::SettlementPlaced { seat: 1, .. }));
            legal = legal_actions;
        }
    }

    let ServerMessage::LobbyState {
        lobby: rejoined, ..
    } = guest.join(lobby, None).await
    else {
        panic!("the reserved player rejoins");
    };
    assert_eq!(rejoined.seats[1], SeatOccupant::Human { user: guest_user });
    let ServerMessage::GameStarted { seat, view, .. } = guest.receive().await else {
        panic!("a rejoining player gets the game");
    };
    assert_eq!(seat, 1);
    assert!(
        view.players[1].settlements_left < 5,
        "the bot's settlement is kept"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_password_lobby_admits_only_the_right_password() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, _) = Client::welcomed(address, "Guest").await;
    let lobby = owner.create_lobby("Secret", 3, Some("hunter2")).await;

    for wrong in [None, Some("hunter3")] {
        let ServerMessage::Error { code, .. } = guest.join(lobby, wrong).await else {
            panic!("a wrong password must not join");
        };
        assert_eq!(code, ErrorCode::WrongPassword);
    }
    let ServerMessage::LobbyState { lobby: details, .. } = guest.join(lobby, Some("hunter2")).await
    else {
        panic!("the right password joins");
    };
    assert!(details.has_password);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_user_is_in_at_most_one_lobby() {
    let address = start(test_config()).await;
    let (mut first, _) = Client::welcomed(address, "First").await;
    let (mut second, _) = Client::welcomed(address, "Second").await;
    let other = second.create_lobby("Other", 3, None).await;
    first.create_lobby("Mine", 3, None).await;

    let create = |request_id| ClientMessage::CreateLobby {
        request_id,
        name: "Another".to_string(),
        password: None,
        seats: 3,
    };
    assert_eq!(first.expect_error(create).await, ErrorCode::AlreadyInLobby);
    let ServerMessage::Error { code, .. } = first.join(other, None).await else {
        panic!("joining a second lobby must fail");
    };
    assert_eq!(code, ErrorCode::AlreadyInLobby);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn listing_pages_through_open_lobbies_and_drops_empty_ones() {
    let address = start(test_config()).await;
    let mut owners = Vec::new();
    for name in ["A", "B", "C"] {
        let (mut client, _) = Client::welcomed(address, name).await;
        client.create_lobby(name, 3, None).await;
        owners.push(client);
    }
    let list = |page, per_page| {
        move |request_id| ClientMessage::ListLobbies {
            request_id,
            page,
            per_page,
        }
    };
    let viewer = &mut owners[0];

    let ServerMessage::Lobbies { total, lobbies, .. } = viewer.request(list(1, 2)).await else {
        panic!("expected Lobbies");
    };
    assert_eq!(total, 3);
    assert_eq!(lobbies.len(), 1);
    assert_eq!(lobbies[0].name, "C");
    assert_eq!(
        viewer.expect_error(list(0, 51)).await,
        ErrorCode::InvalidPage
    );
    assert_eq!(
        viewer.expect_error(list(0, 0)).await,
        ErrorCode::InvalidPage
    );

    owners[1].request(leave).await;
    let ServerMessage::Lobbies { total, lobbies, .. } = owners[0].request(list(0, 50)).await else {
        panic!("expected Lobbies");
    };
    assert_eq!(total, 2);
    let names: Vec<&str> = lobbies.iter().map(|lobby| lobby.name.as_str()).collect();
    assert_eq!(names, ["A", "C"]);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn requests_need_hello_first_and_valid_names() {
    let address = start(test_config()).await;
    let mut client = Client::connect(address).await;

    let list = |request_id| ClientMessage::ListLobbies {
        request_id,
        page: 0,
        per_page: 10,
    };
    assert_eq!(client.expect_error(list).await, ErrorCode::NotWelcomed);
    let blank = |request_id| ClientMessage::Hello {
        request_id,
        name: "   ".to_string(),
    };
    assert_eq!(client.expect_error(blank).await, ErrorCode::InvalidName);
    let hello = |request_id| ClientMessage::Hello {
        request_id,
        name: "Ada".to_string(),
    };
    assert!(matches!(
        client.request(hello).await,
        ServerMessage::Welcome { .. }
    ));
    assert_eq!(client.expect_error(hello).await, ErrorCode::AlreadyWelcomed);
    let long_lobby = |request_id| ClientMessage::CreateLobby {
        request_id,
        name: "x".repeat(41),
        password: None,
        seats: 3,
    };
    assert_eq!(
        client.expect_error(long_lobby).await,
        ErrorCode::InvalidLobbyName
    );
    let five_seats = |request_id| ClientMessage::CreateLobby {
        request_id,
        name: "Table".to_string(),
        password: None,
        seats: 5,
    };
    assert_eq!(
        client.expect_error(five_seats).await,
        ErrorCode::InvalidSeatCount
    );
}
