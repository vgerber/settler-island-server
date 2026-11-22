use std::sync::Arc;

use settler_island_bot::{create_bot, Bot, Difficulty};
use settler_island_game::{Action, Event, Game, GameRecord, GameSettings, Phase, Seat};
use settler_island_protocol::{
    ErrorCode, LobbyDetails, LobbyId, LobbySummary, SeatOccupant, ServerMessage, User, UserId,
};
use tokio::sync::{mpsc, oneshot};
use tokio::time::{sleep_until, Instant};
use tracing::{error, info};

use crate::config::Config;
use crate::outbox::Outbox;
use crate::store::{GameId, GameStore, NewGame, SeatPlayer, StoredAction};

const COMMAND_QUEUE: usize = 64;
/// Stands in for a player who leaves a running game.
const STORE_RETRY: std::time::Duration = std::time::Duration::from_secs(1);

pub(crate) type Reply = oneshot::Sender<Result<(), ErrorCode>>;

pub(crate) enum LobbyCommand {
    Join {
        user: User,
        outbox: Outbox,
        request_id: u32,
        reply: Reply,
    },
    Leave {
        user: UserId,
        reply: Option<Reply>,
    },
    Request {
        user: UserId,
        request_id: u32,
        request: LobbyRequest,
        reply: Reply,
    },
}

pub(crate) enum LobbyRequest {
    AddBot { difficulty: Difficulty },
    RemoveBot { seat: Seat },
    StartGame,
    Act { action: Action },
    GetState,
    GetRecord,
}

/// Sent to the registry; it never answers, so the lobby never waits on it.
pub(crate) enum LobbyNotice {
    Updated(LobbySummary),
    Closed(LobbyId),
}

#[derive(Debug, Clone)]
pub(crate) struct LobbyHandle {
    sender: mpsc::Sender<LobbyCommand>,
}

impl LobbyHandle {
    /// A closed lobby answers `NotInLobby`.
    pub(crate) async fn call(
        &self,
        command: impl FnOnce(Reply) -> LobbyCommand,
    ) -> Result<(), ErrorCode> {
        let (reply, answer) = oneshot::channel();
        self.sender
            .send(command(reply))
            .await
            .map_err(|_| ErrorCode::NotInLobby)?;
        answer.await.map_err(|_| ErrorCode::NotInLobby)?
    }

    /// Fire and forget, for connections that are going away.
    pub(crate) async fn leave(&self, user: UserId) {
        let command = LobbyCommand::Leave { user, reply: None };
        // A closed lobby has nobody left to leave.
        let _ = self.sender.send(command).await;
    }
}

pub(crate) struct LobbySetup {
    pub id: LobbyId,
    pub name: String,
    pub owner: User,
    pub outbox: Outbox,
    pub request_id: u32,
    pub has_password: bool,
    pub seats: u8,
    pub points_to_win: u8,
    pub bot_difficulty: Difficulty,
}

struct Member {
    user: User,
    outbox: Outbox,
}

struct RunningGame {
    id: GameId,
    game: Game,
    record: GameRecord,
    /// Indexed by seat; `Some` where a bot plays.
    bots: Vec<Option<Box<dyn Bot>>>,
    /// Set when a bot's move was rejected; bots stop instead of retrying forever.
    stalled: bool,
    seed: u64,
}

struct Lobby<S> {
    id: LobbyId,
    name: String,
    owner: User,
    has_password: bool,
    seats: Vec<SeatOccupant>,
    points_to_win: u8,
    /// Plays for a player who leaves a running game.
    bot_difficulty: Difficulty,
    members: Vec<Member>,
    game: Option<RunningGame>,
    bot_deadline: Instant,
    store: Arc<S>,
    config: Arc<Config>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
}

/// Starts the lobby task with the owner seated and returns its handle plus the first summary.
pub(crate) fn spawn<S: GameStore>(
    setup: LobbySetup,
    store: Arc<S>,
    config: Arc<Config>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
) -> (LobbyHandle, LobbySummary) {
    let mut seats = vec![SeatOccupant::Open; usize::from(setup.seats)];
    seats[0] = SeatOccupant::Human {
        user: setup.owner.clone(),
    };
    let lobby = Lobby {
        id: setup.id,
        name: setup.name,
        owner: setup.owner.clone(),
        has_password: setup.has_password,
        seats,
        points_to_win: setup.points_to_win,
        bot_difficulty: setup.bot_difficulty,
        members: vec![Member {
            user: setup.owner,
            outbox: setup.outbox,
        }],
        game: None,
        bot_deadline: Instant::now(),
        store,
        config,
        notices,
    };
    let summary = lobby.summary();
    let (sender, receiver) = mpsc::channel(COMMAND_QUEUE);
    tokio::spawn(lobby.run(receiver, setup.request_id));
    (LobbyHandle { sender }, summary)
}

impl<S: GameStore> Lobby<S> {
    async fn run(mut self, mut commands: mpsc::Receiver<LobbyCommand>, request_id: u32) {
        info!(lobby = self.id.0, "lobby opened");
        let owner = self.owner.id.clone();
        self.send_state_to(&owner, Some(request_id));
        while !self.members.is_empty() {
            let bot_due = self.bot_seat_to_move().is_some();
            tokio::select! {
                command = commands.recv() => {
                    let Some(command) = command else { break };
                    self.handle(command).await;
                }
                () = sleep_until(self.bot_deadline), if bot_due => self.play_bot().await,
            }
        }
        info!(lobby = self.id.0, "lobby closed");
        // The registry is gone only during shutdown.
        let _ = self.notices.send(LobbyNotice::Closed(self.id));
    }

    async fn handle(&mut self, command: LobbyCommand) {
        match command {
            LobbyCommand::Join {
                user,
                outbox,
                request_id,
                reply,
            } => {
                let result = self.join(user, outbox, request_id);
                // The connection may have closed while waiting.
                let _ = reply.send(result);
            }
            LobbyCommand::Leave { user, reply } => {
                self.leave(&user);
                if let Some(reply) = reply {
                    // The connection may have closed while waiting.
                    let _ = reply.send(Ok(()));
                }
            }
            LobbyCommand::Request {
                user,
                request_id,
                request,
                reply,
            } => {
                let result = self.request(&user, request_id, request).await;
                // The connection may have closed while waiting.
                let _ = reply.send(result);
            }
        }
    }

    fn join(&mut self, user: User, outbox: Outbox, request_id: u32) -> Result<(), ErrorCode> {
        if self.member(&user.id).is_some() {
            return Err(ErrorCode::AlreadyInLobby);
        }
        let seat = match &self.game {
            Some(_) => self
                .reserved_seat(&user.id)
                .ok_or(ErrorCode::GameAlreadyStarted)?,
            None => self.open_seat().ok_or(ErrorCode::LobbyFull)?,
        };
        self.seats[seat] = SeatOccupant::Human { user: user.clone() };
        if let Some(running) = &mut self.game {
            running.bots[seat] = None;
        }
        let user_id = user.id.clone();
        self.members.push(Member { user, outbox });
        self.broadcast_state(Some((&user_id, request_id)));
        self.send_game_started(&user_id, Some(request_id));
        Ok(())
    }

    fn leave(&mut self, user: &UserId) {
        let Some(index) = self
            .members
            .iter()
            .position(|member| member.user.id == *user)
        else {
            return;
        };
        let member = self.members.remove(index);
        let Some(seat) = self.seat_of(user) else {
            return;
        };
        self.seats[seat] = match &mut self.game {
            Some(running) => {
                let seed = bot_seed(running.seed, seat);
                running.bots[seat] = Some(create_bot(self.bot_difficulty, seed));
                self.bot_deadline = Instant::now() + self.config.bot_delay;
                SeatOccupant::Bot {
                    difficulty: self.bot_difficulty,
                    reserved_for: Some(member.user),
                }
            }
            None => SeatOccupant::Open,
        };
        if self.owner.id == *user {
            if let Some(next) = self.first_human() {
                self.owner = next;
            }
        }
        if !self.members.is_empty() {
            self.broadcast_state(None);
        }
    }

    async fn request(
        &mut self,
        user: &UserId,
        request_id: u32,
        request: LobbyRequest,
    ) -> Result<(), ErrorCode> {
        let seat = self.seat_of(user).ok_or(ErrorCode::NotInLobby)?;
        match request {
            LobbyRequest::AddBot { difficulty } => self.add_bot(user, request_id, difficulty),
            LobbyRequest::RemoveBot { seat } => self.remove_bot(user, request_id, seat),
            LobbyRequest::StartGame => self.start(user, request_id).await,
            LobbyRequest::Act { action } => self.act(seat, request_id, action).await,
            LobbyRequest::GetState => {
                self.send_state_to(user, Some(request_id));
                self.send_game_started(user, Some(request_id));
                Ok(())
            }
            LobbyRequest::GetRecord => self.send_record(seat, user, request_id),
        }
    }

    fn check_owner_before_start(&self, user: &UserId) -> Result<(), ErrorCode> {
        if self.owner.id != *user {
            return Err(ErrorCode::NotOwner);
        }
        if self.game.is_some() {
            return Err(ErrorCode::GameAlreadyStarted);
        }
        Ok(())
    }

    fn add_bot(
        &mut self,
        user: &UserId,
        request_id: u32,
        difficulty: Difficulty,
    ) -> Result<(), ErrorCode> {
        self.check_owner_before_start(user)?;
        let seat = self.open_seat().ok_or(ErrorCode::LobbyFull)?;
        self.seats[seat] = SeatOccupant::Bot {
            difficulty,
            reserved_for: None,
        };
        self.broadcast_state(Some((user, request_id)));
        Ok(())
    }

    fn remove_bot(&mut self, user: &UserId, request_id: u32, seat: Seat) -> Result<(), ErrorCode> {
        self.check_owner_before_start(user)?;
        let index = usize::from(seat);
        let Some(SeatOccupant::Bot { .. }) = self.seats.get(index) else {
            return Err(ErrorCode::NotABot);
        };
        self.seats[index] = SeatOccupant::Open;
        self.broadcast_state(Some((user, request_id)));
        Ok(())
    }

    async fn start(&mut self, user: &UserId, request_id: u32) -> Result<(), ErrorCode> {
        self.check_owner_before_start(user)?;
        if self.open_seat().is_some() {
            return Err(ErrorCode::SeatsNotFilled);
        }
        let settings = GameSettings {
            seats: self.seats.len() as u8,
            points_to_win: self.points_to_win,
            seed: self.config.seed.unwrap_or_else(rand::random),
        };
        let game = Game::new(settings.clone()).map_err(|error| ErrorCode::Game { error })?;
        let new_game = NewGame {
            settings: settings.clone(),
            seats: self
                .seats
                .iter()
                .map(|occupant| seat_player(occupant, self.bot_difficulty))
                .collect(),
        };
        let id = self.store.create_game(new_game).await.map_err(|error| {
            error!(lobby = self.id.0, %error, "storing the new game failed");
            ErrorCode::Internal
        })?;
        let bots = self
            .seats
            .iter()
            .enumerate()
            .map(|(seat, occupant)| match occupant {
                SeatOccupant::Bot { difficulty, .. } => {
                    Some(create_bot(*difficulty, bot_seed(settings.seed, seat)))
                }
                _ => None,
            })
            .collect();
        self.game = Some(RunningGame {
            id,
            record: GameRecord::new(&game),
            game,
            bots,
            stalled: false,
            seed: settings.seed,
        });
        self.bot_deadline = Instant::now() + self.config.bot_delay;
        info!(lobby = self.id.0, game = id.0, "game started");
        self.broadcast_state(Some((user, request_id)));
        let members: Vec<UserId> = self
            .members
            .iter()
            .map(|member| member.user.id.clone())
            .collect();
        for member in members {
            let echo = (member == *user).then_some(request_id);
            self.send_game_started(&member, echo);
        }
        Ok(())
    }

    async fn act(&mut self, seat: usize, request_id: u32, action: Action) -> Result<(), ErrorCode> {
        let running = self.game.as_mut().ok_or(ErrorCode::NoGame)?;
        let seat = seat as Seat;
        let events = apply_and_store(running, self.store.as_ref(), seat, action).await?;
        self.bot_deadline = Instant::now() + self.config.bot_delay;
        self.broadcast_update(&events, Some((seat, request_id)));
        Ok(())
    }

    fn bot_seat_to_move(&self) -> Option<Seat> {
        let running = self.game.as_ref().filter(|running| !running.stalled)?;
        running
            .game
            .pending_seats()
            .into_iter()
            .find(|seat| running.bots[usize::from(*seat)].is_some())
    }

    async fn play_bot(&mut self) {
        let Some(seat) = self.bot_seat_to_move() else {
            return;
        };
        let Some(running) = self.game.as_mut() else {
            return;
        };
        let view = running.game.view(Some(seat));
        let legal = running.game.legal_actions(seat);
        let Some(bot) = running.bots[usize::from(seat)].as_mut() else {
            return;
        };
        if legal.is_empty() {
            error!(lobby = self.id.0, seat, "bot has no legal action");
            running.stalled = true;
            return;
        }
        let action = bot.choose(&view, &legal);
        match apply_and_store(running, self.store.as_ref(), seat, action).await {
            Ok(events) => {
                self.bot_deadline = Instant::now() + self.config.bot_delay;
                self.broadcast_update(&events, None);
            }
            Err(ErrorCode::Internal) => self.bot_deadline = Instant::now() + STORE_RETRY,
            Err(code) => {
                error!(
                    lobby = self.id.0,
                    seat,
                    ?code,
                    "bot move rejected, bots stop"
                );
                running.stalled = true;
            }
        }
    }

    fn send_record(&self, seat: usize, user: &UserId, request_id: u32) -> Result<(), ErrorCode> {
        let running = self.game.as_ref().ok_or(ErrorCode::NoGame)?;
        let mut record = running.record.clone();
        if !matches!(running.game.phase(), Phase::Finished { .. }) {
            let viewer = Some(seat as Seat);
            for entry in &mut record.entries {
                entry.events = entry
                    .events
                    .iter()
                    .map(|event| event.visible_to(viewer))
                    .collect();
            }
        }
        if let Some(member) = self.member(user) {
            member
                .outbox
                .send(ServerMessage::Record { request_id, record });
        }
        Ok(())
    }

    fn broadcast_update(&self, events: &[Event], cause: Option<(Seat, u32)>) {
        let Some(running) = &self.game else {
            return;
        };
        for member in &self.members {
            let Some(seat) = self.seat_of(&member.user.id) else {
                continue;
            };
            let seat = seat as Seat;
            let request_id = cause
                .filter(|(cause_seat, _)| *cause_seat == seat)
                .map(|(_, request_id)| request_id);
            member.outbox.send(ServerMessage::GameUpdate {
                request_id,
                events: events
                    .iter()
                    .map(|event| event.visible_to(Some(seat)))
                    .collect(),
                view: running.game.view(Some(seat)),
                legal_actions: running.game.legal_actions(seat),
            });
        }
    }

    /// Sends the lobby to every member, echoing the request id to its sender, and tells the registry.
    fn broadcast_state(&self, cause: Option<(&UserId, u32)>) {
        for member in &self.members {
            let echo = cause
                .filter(|(requester, _)| **requester == member.user.id)
                .map(|(_, request_id)| request_id);
            member.outbox.send(ServerMessage::LobbyState {
                request_id: echo,
                lobby: self.details(),
            });
        }
        // The registry is gone only during shutdown.
        let _ = self.notices.send(LobbyNotice::Updated(self.summary()));
    }

    fn send_state_to(&self, user: &UserId, request_id: Option<u32>) {
        if let Some(member) = self.member(user) {
            member.outbox.send(ServerMessage::LobbyState {
                request_id,
                lobby: self.details(),
            });
        }
    }

    fn send_game_started(&self, user: &UserId, request_id: Option<u32>) {
        let (Some(running), Some(member), Some(seat)) =
            (&self.game, self.member(user), self.seat_of(user))
        else {
            return;
        };
        let seat = seat as Seat;
        member.outbox.send(ServerMessage::GameStarted {
            request_id,
            seat,
            view: running.game.view(Some(seat)),
            legal_actions: running.game.legal_actions(seat),
        });
    }

    fn member(&self, user: &UserId) -> Option<&Member> {
        self.members.iter().find(|member| member.user.id == *user)
    }

    fn seat_of(&self, user: &UserId) -> Option<usize> {
        self.seats.iter().position(
            |occupant| matches!(occupant, SeatOccupant::Human { user: seated } if seated.id == *user),
        )
    }

    fn reserved_seat(&self, user: &UserId) -> Option<usize> {
        self.seats.iter().position(|occupant| {
            matches!(occupant, SeatOccupant::Bot { reserved_for: Some(reserved), .. } if reserved.id == *user)
        })
    }

    fn open_seat(&self) -> Option<usize> {
        self.seats
            .iter()
            .position(|occupant| *occupant == SeatOccupant::Open)
    }

    fn first_human(&self) -> Option<User> {
        self.seats.iter().find_map(|occupant| match occupant {
            SeatOccupant::Human { user } => Some(user.clone()),
            _ => None,
        })
    }

    fn details(&self) -> LobbyDetails {
        LobbyDetails {
            id: self.id,
            name: self.name.clone(),
            owner: self.owner.clone(),
            has_password: self.has_password,
            started: self.game.is_some(),
            points_to_win: self.points_to_win,
            bot_difficulty: self.bot_difficulty,
            seats: self.seats.clone(),
        }
    }

    fn summary(&self) -> LobbySummary {
        let open_seats = self
            .seats
            .iter()
            .filter(|occupant| **occupant == SeatOccupant::Open)
            .count();
        LobbySummary {
            id: self.id,
            name: self.name.clone(),
            owner: self.owner.clone(),
            seats: self.seats.len() as u8,
            open_seats: open_seats as u8,
            has_password: self.has_password,
            started: self.game.is_some(),
            points_to_win: self.points_to_win,
            bot_difficulty: self.bot_difficulty,
        }
    }
}

/// Validates on a copy, stores the action, then commits, so a store failure leaves the game unchanged.
async fn apply_and_store<S: GameStore>(
    running: &mut RunningGame,
    store: &S,
    seat: Seat,
    action: Action,
) -> Result<Vec<Event>, ErrorCode> {
    let mut next = running.game.clone();
    let events = next
        .apply(seat, action.clone())
        .map_err(|error| ErrorCode::Game { error })?;
    let stored = StoredAction {
        index: running.record.entries.len() as u32,
        seat,
        action: action.clone(),
        events: events.clone(),
    };
    store
        .append_action(running.id, stored)
        .await
        .map_err(|error| {
            error!(game = running.id.0, %error, "storing an action failed");
            ErrorCode::Internal
        })?;
    if let Phase::Finished { winner } = next.phase() {
        info!(game = running.id.0, winner, "game finished");
        if let Err(error) = store.finish(running.id, *winner).await {
            error!(game = running.id.0, %error, "marking the game finished failed");
        }
    }
    running.game = next;
    running.record.push(seat, action, events.clone());
    Ok(events)
}

fn seat_player(occupant: &SeatOccupant, fallback: Difficulty) -> SeatPlayer {
    match occupant {
        SeatOccupant::Human { user } => SeatPlayer::Human(user.id.clone()),
        SeatOccupant::Bot { difficulty, .. } => SeatPlayer::Bot(*difficulty),
        // Start requires every seat filled.
        SeatOccupant::Open => SeatPlayer::Bot(fallback),
    }
}

/// Distinct per seat and per game, reproducible from the game seed.
fn bot_seed(game_seed: u64, seat: usize) -> u64 {
    game_seed.wrapping_add(seat as u64 + 1)
}
