mod common;

use common::{guest_session, start, test_config, Client};
use settler_island_protocol::{
    AwayPolicy, ClientMessage, Difficulty, ErrorCode, Event, SeatOccupant, ServerLimit,
    ServerMessage,
};

fn create_with(
    points_to_win: Option<u8>,
    bot_difficulty: Option<Difficulty>,
) -> impl Fn(u32) -> ClientMessage {
    move |request_id| ClientMessage::CreateLobby {
        request_id,
        name: "Table".to_string(),
        password: None,
        seats: 3,
        points_to_win,
        bot_difficulty,
        away_policy: None,
    }
}

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
    guest.try_join(lobby, None).await.unwrap();

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
    assert!(lobby_after.info.started);
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
    assert_eq!(
        outsider.try_join(lobby, None).await,
        Err(ErrorCode::LobbyFull)
    );

    let started = owner.expect_lobby(start_game).await;
    assert!(started.info.started);
    assert_eq!(
        outsider.try_join(lobby, None).await,
        Err(ErrorCode::GameAlreadyStarted)
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn the_next_member_owns_the_lobby_when_the_owner_leaves() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guest, guest_user) = Client::welcomed(address, "Guest").await;
    let lobby = owner.create_lobby("Table", 4, None).await;
    guest.try_join(lobby, None).await.unwrap();

    let left = owner.request(leave).await;
    assert!(matches!(left, ServerMessage::LobbyLeft { .. }));
    let details = guest.next_lobby_state().await;
    assert_eq!(details.info.owner, guest_user);
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
    guest.try_join(lobby, None).await.unwrap();
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
    // The lobby default is Heuristic, so Random proves the lobby's setting is used.
    let lobby = owner
        .expect_lobby(create_with(None, Some(Difficulty::Random)))
        .await
        .info
        .id;
    guest.try_join(lobby, None).await.unwrap();
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
    assert_eq!(
        outsider.try_join(lobby, None).await,
        Err(ErrorCode::GameAlreadyStarted)
    );

    // Seat 0 places its first settlement and road, then the replacement bot on seat 1 must move.
    owner
        .send(|request_id| ClientMessage::GetState { request_id })
        .await;
    let mut legal = owner.next_game_started().await.legal_actions;
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

    let rejoined = guest.try_join(lobby, None).await.unwrap();
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
        assert_eq!(
            guest.try_join(lobby, wrong).await,
            Err(ErrorCode::WrongPassword)
        );
    }
    let details = guest.try_join(lobby, Some("hunter2")).await.unwrap();
    assert!(details.info.has_password);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn password_guessing_is_refused_after_five_wrong_guesses_in_a_minute() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let (mut guesser, _) = Client::welcomed(address, "Guesser").await;
    let lobby = owner.create_lobby("Secret", 3, Some("hunter2")).await;

    for guess in 0..5 {
        let wrong = format!("guess {guess}");
        assert_eq!(
            guesser.try_join(lobby, Some(&wrong)).await,
            Err(ErrorCode::WrongPassword)
        );
    }
    // Even the right password is refused, so the sixth attempt never reaches Argon2.
    assert_eq!(
        guesser.try_join(lobby, Some("hunter2")).await,
        Err(ErrorCode::LimitReached {
            limit: ServerLimit::PasswordGuesses
        })
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn wrong_guesses_from_one_address_add_up_across_guest_accounts() {
    let address = start(test_config()).await;
    let (mut owner, _) = Client::welcomed(address, "Owner").await;
    let lobby = owner.create_lobby("Secret", 3, Some("hunter2")).await;

    // A fresh guest per guess: only the per-address count can stop this.
    for guess in 0..5 {
        let (mut guesser, _) = Client::welcomed(address, &format!("Guesser{guess}")).await;
        let wrong = format!("guess {guess}");
        assert_eq!(
            guesser.try_join(lobby, Some(&wrong)).await,
            Err(ErrorCode::WrongPassword)
        );
    }
    let (mut last, _) = Client::welcomed(address, "Guesser5").await;
    assert_eq!(
        last.try_join(lobby, Some("hunter2")).await,
        Err(ErrorCode::LimitReached {
            limit: ServerLimit::PasswordGuesses
        })
    );
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
        points_to_win: None,
        bot_difficulty: None,
        away_policy: None,
    };
    assert_eq!(first.expect_error(create).await, ErrorCode::AlreadyInLobby);
    assert_eq!(
        first.try_join(other, None).await,
        Err(ErrorCode::AlreadyInLobby)
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn one_user_on_two_connections_is_still_in_at_most_one_lobby() {
    let address = start(test_config()).await;
    let session = guest_session(address, "Twin").await;
    let (mut first, _) = Client::authenticated(address, &session.token).await;
    let (mut second, _) = Client::authenticated(address, &session.token).await;
    let (mut other, _) = Client::welcomed(address, "Other").await;
    let elsewhere = other.create_lobby("Elsewhere", 3, None).await;
    let mine = first.create_lobby("Mine", 3, None).await;

    let code = second.expect_error(create_with(None, None)).await;
    assert_eq!(code, ErrorCode::AlreadyInLobby);
    assert_eq!(
        second.try_join(elsewhere, None).await,
        Err(ErrorCode::AlreadyInLobby)
    );

    // The user's own lobby on the second connection is a takeover, not a second lobby.
    second.try_join(mine, None).await.unwrap();
    second
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    let fresh = second.expect_lobby(create_with(None, None)).await;
    assert_ne!(fresh.info.id, mine);
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
    assert_eq!(lobbies[0].info.name, "C");
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
    let names: Vec<&str> = lobbies
        .iter()
        .map(|lobby| lobby.info.name.as_str())
        .collect();
    assert_eq!(names, ["A", "C"]);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn requests_need_authenticate_first_and_valid_names() {
    let address = start(test_config()).await;
    let mut client = Client::connect(address).await;

    let list = |request_id| ClientMessage::ListLobbies {
        request_id,
        page: 0,
        per_page: 10,
    };
    assert_eq!(client.expect_error(list).await, ErrorCode::NotWelcomed);
    let authenticate = |token: &str| {
        let token = token.to_string();
        move |request_id| ClientMessage::Authenticate { request_id, token }
    };
    assert_eq!(
        client.expect_error(authenticate("guest.not.signed")).await,
        ErrorCode::InvalidToken
    );
    let token = common::guest_session(address, "Ada").await.token;
    assert!(matches!(
        client.authenticate(&token).await,
        ServerMessage::Welcome { .. }
    ));
    assert_eq!(
        client.expect_error(authenticate(&token)).await,
        ErrorCode::AlreadyWelcomed
    );
    let long_lobby = |request_id| ClientMessage::CreateLobby {
        request_id,
        name: "x".repeat(41),
        password: None,
        seats: 3,
        points_to_win: None,
        bot_difficulty: None,
        away_policy: None,
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
        points_to_win: None,
        bot_difficulty: None,
        away_policy: None,
    };
    assert_eq!(
        client.expect_error(five_seats).await,
        ErrorCode::InvalidSeatCount
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn lobby_settings_default_and_reach_the_game() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Ada").await;
    let defaults = client.expect_lobby(create_with(None, None)).await;
    assert_eq!(defaults.info.points_to_win, 10);
    assert_eq!(defaults.info.bot_difficulty, Difficulty::Heuristic);
    assert_eq!(defaults.info.away_policy, AwayPolicy::BotTakesOver);
    client.request(leave).await;

    let custom = client
        .expect_lobby(create_with(Some(4), Some(Difficulty::Random)))
        .await;
    assert_eq!(custom.info.points_to_win, 4);
    assert_eq!(custom.info.bot_difficulty, Difficulty::Random);
    client.expect_lobby(add_bot).await;
    client.expect_lobby(add_bot).await;
    client.expect_lobby(start_game).await;
    client
        .send(|request_id| ClientMessage::GetState { request_id })
        .await;
    assert_eq!(client.next_game_started().await.view.points_to_win, 4);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn points_to_win_outside_three_to_fifteen_is_rejected() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Ada").await;
    for points in [0, 2, 16, 255] {
        assert_eq!(
            client.expect_error(create_with(Some(points), None)).await,
            ErrorCode::InvalidPointsToWin
        );
    }
    for points in [3, 15] {
        client.expect_lobby(create_with(Some(points), None)).await;
        client.request(leave).await;
    }
}

fn running_lobby_of(welcome: ServerMessage) -> Option<settler_island_protocol::LobbyId> {
    let ServerMessage::Welcome { running_lobby, .. } = welcome else {
        panic!("expected Welcome, got {welcome:?}");
    };
    running_lobby
}

#[tokio::test]
async fn welcome_names_the_running_game_a_returning_player_holds_a_seat_in() {
    let address = start(test_config()).await;
    let session = guest_session(address, "Ada").await;
    let mut first = Client::connect(address).await;
    assert_eq!(
        running_lobby_of(first.authenticate(&session.token).await),
        None
    );

    let lobby = first.create_lobby("Table", 3, None).await;
    for _ in 0..2 {
        first
            .expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty: Difficulty::Random,
            })
            .await;
    }
    let mut waiting = Client::connect(address).await;
    assert_eq!(
        running_lobby_of(waiting.authenticate(&session.token).await),
        None,
        "a lobby that has not started holds no seat"
    );
    first
        .request(|request_id| ClientMessage::StartGame { request_id })
        .await;

    // The same player on a fresh connection, as after a client restart.
    let mut returning = Client::connect(address).await;
    assert_eq!(
        running_lobby_of(returning.authenticate(&session.token).await),
        Some(lobby)
    );
    let mut stranger = Client::connect(address).await;
    let other = guest_session(address, "Bob").await;
    assert_eq!(
        running_lobby_of(stranger.authenticate(&other.token).await),
        None
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_second_login_with_the_same_token_closes_the_first_socket_after_a_notice() {
    let address = start(test_config()).await;
    let session = guest_session(address, "Alice").await;
    let (mut first, _) = Client::authenticated(address, &session.token).await;
    let lobby = first.create_lobby("Table", 3, None).await;

    let (mut second, _) = Client::authenticated(address, &session.token).await;
    second.try_join(lobby, None).await.expect("takeover join");

    let notice = first.receive().await;
    assert!(matches!(
        notice,
        ServerMessage::Error {
            code: ErrorCode::TakenOver,
            ..
        }
    ));
    assert!(first.closed_by_server().await);
}
