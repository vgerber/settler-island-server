use std::sync::Arc;

use settler_island_bot::{bot_seed, create_bot, Bot, Difficulty};
use settler_island_game::{
    Action, Event, Game, GameRecord, GameSettings, RecordEntry, Seat, MAX_SEATS, MIN_SEATS,
};

use crate::store::StoredGame;
use settler_island_protocol::{
    ErrorCode, LobbyDetails, LobbyId, LobbySummary, SeatOccupant, ServerMessage, User, UserId,
};
use tokio::sync::{mpsc, oneshot};
use tokio::time::{sleep_until, Instant};
use tracing::{error, info, warn};

use crate::config::Config;
use crate::metrics::{GameInProgress, Metrics};
use crate::outbox::Outbox;
use crate::store::{wants_snapshot, GameId, GameStore, NewGame, SeatPlayer, StoreError};

const COMMAND_QUEUE: usize = 64;
/// How long to wait before retrying a store write that failed.
const STORE_RETRY: std::time::Duration = std::time::Duration::from_secs(1);

pub(crate) type Reply = oneshot::Sender<Result<(), ErrorCode>>;

pub(crate) enum LobbyCommand {
    Join {
        user: User,
        outbox: Outbox,
        request_id: u32,
        reply: Reply,
    },
    /// Ignored unless `outbox` is the member's current connection, so a replaced connection cannot evict its successor.
    Leave {
        user: UserId,
        outbox: Outbox,
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
    Joined {
        lobby: LobbyId,
        user: UserId,
    },
    Left {
        lobby: LobbyId,
        user: UserId,
    },
    /// Who holds a seat in the lobby's running game; empty once the game ends.
    Seated {
        lobby: LobbyId,
        users: Vec<UserId>,
    },
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
    pub(crate) async fn leave(&self, user: UserId, outbox: Outbox) {
        let command = LobbyCommand::Leave {
            user,
            outbox,
            reply: None,
        };
        // A closed lobby has nobody left to leave.
        let _ = self.sender.send(command).await;
    }
}

/// A lobby's number of seats, within the bounds the game supports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct SeatCount(u8);

impl SeatCount {
    pub(crate) fn new(seats: u8) -> Result<SeatCount, ErrorCode> {
        if !(MIN_SEATS..=MAX_SEATS).contains(&seats) {
            return Err(ErrorCode::InvalidSeatCount);
        }
        Ok(SeatCount(seats))
    }
}

pub(crate) struct LobbySetup {
    pub id: LobbyId,
    pub name: String,
    pub owner: User,
    pub outbox: Outbox,
    pub request_id: u32,
    pub has_password: bool,
    pub seats: SeatCount,
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
    /// Set when neither a bot's move nor its fallback was accepted; bots stop instead of retrying forever.
    stalled: bool,
    seed: u64,
    in_progress: GameInProgress,
}

/// How a running game ends.
enum GameEnd {
    Finished { winner: Seat },
    Abandoned,
}

impl RunningGame {
    /// A human asked in the open trade who has not answered yet.
    fn human_answer_pending(&self) -> bool {
        let Some(offer) = self.game.phase().trade_offer() else {
            return false;
        };
        (0..)
            .zip(&self.bots)
            .any(|(seat, bot)| bot.is_none() && offer.awaits_answer_from(seat))
    }
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
    /// Until when a bot that offered a trade waits for the humans it asked; `None` without an open offer.
    answers_due: Option<Instant>,
    /// When a running game with no connected human is closed; `None` while a human is connected.
    abandon_at: Option<Instant>,
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
}

/// Starts the lobby task with the owner seated and returns its handle plus the first summary.
pub(crate) fn spawn<S: GameStore>(
    setup: LobbySetup,
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
) -> (LobbyHandle, LobbySummary) {
    let request_id = setup.request_id;
    open(setup, store, config, metrics, notices).spawn(Some(request_id))
}

/// A new lobby with the owner in the first seat and the others open.
fn open<S: GameStore>(
    setup: LobbySetup,
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
) -> Lobby<S> {
    let owner_seat = SeatOccupant::Human {
        user: setup.owner.clone(),
    };
    let open_seats = std::iter::repeat_n(SeatOccupant::Open, usize::from(setup.seats.0) - 1);
    let seats = std::iter::once(owner_seat).chain(open_seats).collect();
    Lobby {
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
        answers_due: None,
        abandon_at: None,
        store,
        config,
        metrics,
        notices,
    }
}

/// Recreates the lobby of a game that was running when the server stopped: every human seat waits for its
/// player under a bot, which only moves once a human is back.
pub(crate) fn restore<S: GameStore>(
    stored: &StoredGame,
    game: Game,
    record: GameRecord,
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
) -> Option<(LobbyHandle, LobbySummary)> {
    let away = stored.game.bot_difficulty;
    let seed = stored.game.settings.seed;
    let mut seats = Vec::with_capacity(stored.game.seats.len());
    let mut bots = Vec::with_capacity(stored.game.seats.len());
    for (seat, player) in stored.game.seats.iter().enumerate() {
        let (difficulty, reserved_for) = match player {
            SeatPlayer::Human(user) => (away, Some(user.clone())),
            SeatPlayer::Bot(difficulty) => (*difficulty, None),
        };
        bots.push(Some(create_bot(difficulty, bot_seed(seed, seat))));
        seats.push(SeatOccupant::Bot {
            difficulty,
            reserved_for,
        });
    }
    let owner = stored.game.seats.iter().find_map(|player| match player {
        SeatPlayer::Human(user) => Some(user.clone()),
        SeatPlayer::Bot(_) => None,
    })?;
    let lobby = Lobby {
        id: stored.game.lobby,
        name: stored.game.lobby_name.clone(),
        owner,
        has_password: false,
        seats,
        points_to_win: stored.game.settings.points_to_win,
        bot_difficulty: away,
        members: Vec::new(),
        game: Some(RunningGame {
            id: stored.id,
            game,
            record,
            bots,
            stalled: false,
            seed,
            in_progress: metrics.game_started(),
        }),
        bot_deadline: Instant::now(),
        answers_due: None,
        // The time nobody was connected before the restart counts toward the deadline.
        abandon_at: Some(
            Instant::now()
                + config
                    .abandon_after
                    .saturating_sub(stored.unattended_for.unwrap_or_default()),
        ),
        store,
        config,
        metrics,
        notices,
    };
    Some(lobby.spawn(None))
}

impl<S: GameStore> Lobby<S> {
    fn spawn(self, request_id: Option<u32>) -> (LobbyHandle, LobbySummary) {
        let summary = self.summary();
        let (sender, receiver) = mpsc::channel(COMMAND_QUEUE);
        tokio::spawn(self.run(receiver, request_id));
        (LobbyHandle { sender }, summary)
    }

    async fn run(mut self, mut commands: mpsc::Receiver<LobbyCommand>, request_id: Option<u32>) {
        info!(lobby = self.id.0, "lobby opened");
        let owner = self.owner.id.clone();
        if request_id.is_some() {
            self.send_state_to(&owner, request_id);
        }
        // A restored game starts without humans; the store keeps the time it was first left alone.
        if self.game_running() && self.members.is_empty() {
            self.save_attendance().await;
        }
        // A running game keeps its lobby open for its players to come back.
        while !self.members.is_empty() || self.game_running() {
            let bot_move_at = self.bot_move().map(|(_, at)| at);
            let abandon_at = self.abandon_at.filter(|_| self.game_running());
            tokio::select! {
                command = commands.recv() => {
                    let Some(command) = command else { break };
                    self.handle(command).await;
                }
                () = sleep_until(bot_move_at.unwrap_or_else(Instant::now)), if bot_move_at.is_some() => {
                    self.play_bot().await;
                }
                () = sleep_until(abandon_at.unwrap_or_else(Instant::now)), if abandon_at.is_some() => {
                    if self.abandon().await {
                        break;
                    }
                }
            }
        }
        info!(lobby = self.id.0, "lobby closed");
        // The registry is gone only during shutdown.
        let _ = self.notices.send(LobbyNotice::Closed(self.id));
    }

    async fn handle(&mut self, command: LobbyCommand) {
        let attended_before = !self.members.is_empty();
        self.dispatch(command).await;
        if self.game_running() && attended_before == self.members.is_empty() {
            self.save_attendance().await;
        }
    }

    /// Stores whether a human is connected, so a restart keeps the abandon deadline.
    async fn save_attendance(&mut self) {
        let Some(game) = self.game.as_ref().map(|running| running.id) else {
            return;
        };
        let attended = !self.members.is_empty();
        // Losing this only moves the deadline after a restart; the game itself is unaffected.
        if let Err(error) = self.store.set_attended(game, attended).await {
            warn!(lobby = self.id.0, game = game.0, %error, "storing attendance failed");
        }
    }

    async fn dispatch(&mut self, command: LobbyCommand) {
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
            LobbyCommand::Leave {
                user,
                outbox,
                reply,
            } => {
                self.leave(&user, &outbox);
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
        if let Some(member) = self
            .members
            .iter_mut()
            .find(|member| member.user.id == user.id)
        {
            // The same user on a new connection: the newest connection takes over.
            member.outbox = outbox;
            self.abandon_at = None;
            self.note_membership(LobbyNotice::Joined {
                lobby: self.id,
                user: user.id.clone(),
            });
            self.send_state_to(&user.id, Some(request_id));
            self.send_game_started(&user.id, Some(request_id));
            return Ok(());
        }
        let seat = match &self.game {
            Some(_) => self
                .reserved_seat(&user.id)
                .ok_or(ErrorCode::GameAlreadyStarted)?,
            None => self.open_seat().ok_or(ErrorCode::LobbyFull)?,
        };
        self.seats[usize::from(seat)] = SeatOccupant::Human { user: user.clone() };
        if let Some(running) = &mut self.game {
            running.bots[usize::from(seat)] = None;
        }
        let user_id = user.id.clone();
        self.members.push(Member { user, outbox });
        self.abandon_at = None;
        self.note_membership(LobbyNotice::Joined {
            lobby: self.id,
            user: user_id.clone(),
        });
        self.broadcast_state(Some((&user_id, request_id)));
        self.send_game_started(&user_id, Some(request_id));
        Ok(())
    }

    fn leave(&mut self, user: &UserId, outbox: &Outbox) {
        let Some(index) = self
            .members
            .iter()
            .position(|member| member.user.id == *user && member.outbox.same_connection(outbox))
        else {
            return;
        };
        let member = self.members.remove(index);
        if self.members.is_empty() {
            self.abandon_at = Some(Instant::now() + self.config.abandon_after);
        }
        self.note_membership(LobbyNotice::Left {
            lobby: self.id,
            user: user.clone(),
        });
        let Some(seat) = self.seat_of(user) else {
            return;
        };
        let index = usize::from(seat);
        self.seats[index] = match &mut self.game {
            Some(running) => {
                let seed = bot_seed(running.seed, index);
                running.bots[index] = Some(create_bot(self.bot_difficulty, seed));
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
        self.seats[usize::from(seat)] = SeatOccupant::Bot {
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
            seats: self.seat_count(),
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
            lobby: self.id,
            lobby_name: self.name.clone(),
            bot_difficulty: self.bot_difficulty,
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
            in_progress: self.metrics.game_started(),
        });
        self.bot_deadline = Instant::now() + self.config.bot_delay;
        self.note_membership(LobbyNotice::Seated {
            lobby: self.id,
            users: self
                .members
                .iter()
                .map(|member| member.user.id.clone())
                .collect(),
        });
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

    async fn act(&mut self, seat: Seat, request_id: u32, action: Action) -> Result<(), ErrorCode> {
        let running = self.game.as_mut().ok_or(ErrorCode::NoGame)?;
        let events =
            apply_and_store(running, self.store.as_ref(), &self.metrics, seat, action).await?;
        self.bot_deadline = Instant::now() + self.config.bot_delay;
        self.track_trade();
        self.note_game_end();
        self.broadcast_update(&events, Some((seat, request_id)));
        Ok(())
    }

    /// The bot seat to move next and when. Bots wait while no human is connected, so a restored or abandoned game
    /// does not play itself out; a bot that offered a trade waits for the humans it asked, up to `answers_due`.
    fn bot_move(&self) -> Option<(Seat, Instant)> {
        if self.members.is_empty() {
            return None;
        }
        let running = self.game.as_ref().filter(|running| !running.stalled)?;
        let seat = running
            .game
            .pending_seats()
            .into_iter()
            .find(|seat| running.bots[usize::from(*seat)].is_some())?;
        let offering = running
            .game
            .phase()
            .trade_offer()
            .is_some_and(|offer| offer.offerer == seat);
        let at = match self.answers_due {
            Some(due) if offering && running.human_answer_pending() => due.max(self.bot_deadline),
            _ => self.bot_deadline,
        };
        Some((seat, at))
    }

    /// Starts the answer window when a trade opens and ends it when the trade closes.
    fn track_trade(&mut self) {
        let open = self
            .game
            .as_ref()
            .is_some_and(|running| running.game.phase().trade_offer().is_some());
        self.answers_due = open.then(|| {
            self.answers_due
                .unwrap_or_else(|| Instant::now() + self.config.trade_answer_time)
        });
    }

    /// Closes the game in the store; `false` when that failed and the lobby must stay open for a retry.
    async fn abandon(&mut self) -> bool {
        let Some(running) = self
            .game
            .as_mut()
            .filter(|running| !running.game.is_finished())
        else {
            return true;
        };
        let game = running.id;
        if let Err(error) = end_game(running, self.store.as_ref(), GameEnd::Abandoned).await {
            error!(lobby = self.id.0, game = game.0, %error, "abandoning the game failed, retrying");
            self.abandon_at = Some(Instant::now() + STORE_RETRY);
            return false;
        }
        info!(lobby = self.id.0, game = game.0, "game abandoned");
        true
    }

    async fn play_bot(&mut self) {
        let Some((seat, _)) = self.bot_move() else {
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
        let store = self.store.as_ref();
        match apply_bot_choice(running, store, &self.metrics, seat, action, &legal).await {
            Ok(events) => {
                self.metrics.bot_actions.inc();
                self.bot_deadline = Instant::now() + self.config.bot_delay;
                self.track_trade();
                self.note_game_end();
                self.broadcast_update(&events, None);
            }
            Err(ErrorCode::Internal) => self.bot_deadline = Instant::now() + STORE_RETRY,
            Err(code) => {
                error!(
                    lobby = self.id.0,
                    seat,
                    ?code,
                    "bot move and its fallback rejected, bots stop"
                );
                running.stalled = true;
            }
        }
    }

    fn send_record(&self, seat: Seat, user: &UserId, request_id: u32) -> Result<(), ErrorCode> {
        let running = self.game.as_ref().ok_or(ErrorCode::NoGame)?;
        let mut record = running.record.clone();
        if !running.game.is_finished() {
            let viewer = Some(seat);
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
        member.outbox.send(ServerMessage::GameStarted {
            request_id,
            seat,
            view: running.game.view(Some(seat)),
            legal_actions: running.game.legal_actions(seat),
        });
    }

    fn game_running(&self) -> bool {
        self.game
            .as_ref()
            .is_some_and(|running| !running.game.is_finished())
    }

    /// Tells the registry that nobody holds a seat any more once the game has ended.
    fn note_game_end(&self) {
        if self.game.is_some() && !self.game_running() {
            self.note_membership(LobbyNotice::Seated {
                lobby: self.id,
                users: Vec::new(),
            });
        }
    }

    fn note_membership(&self, notice: LobbyNotice) {
        // The registry is gone only during shutdown.
        let _ = self.notices.send(notice);
    }

    fn member(&self, user: &UserId) -> Option<&Member> {
        self.members.iter().find(|member| member.user.id == *user)
    }

    fn seat_of(&self, user: &UserId) -> Option<Seat> {
        self.find_seat(
            |occupant| matches!(occupant, SeatOccupant::Human { user: seated } if seated.id == *user),
        )
    }

    fn reserved_seat(&self, user: &UserId) -> Option<Seat> {
        self.find_seat(|occupant| {
            matches!(occupant, SeatOccupant::Bot { reserved_for: Some(reserved), .. } if reserved.id == *user)
        })
    }

    fn open_seat(&self) -> Option<Seat> {
        self.find_seat(|occupant| *occupant == SeatOccupant::Open)
    }

    fn find_seat(&self, wanted: impl Fn(&SeatOccupant) -> bool) -> Option<Seat> {
        let index = self.seats.iter().position(wanted)?;
        Seat::try_from(index).ok()
    }

    /// The seats were built from a `SeatCount`, so they always fit.
    fn seat_count(&self) -> u8 {
        u8::try_from(self.seats.len()).unwrap_or(MAX_SEATS)
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
            seats: self.seat_count(),
            open_seats: u8::try_from(open_seats).unwrap_or(MAX_SEATS),
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
    metrics: &Metrics,
    seat: Seat,
    action: Action,
) -> Result<Vec<Event>, ErrorCode> {
    let mut next = running.game.clone();
    let events = next
        .apply(seat, action.clone())
        .map_err(|error| ErrorCode::Game { error })?;
    let index = running.record.entries.len() as u32;
    let snapshot = wants_snapshot(index).then(|| next.clone());
    let entry = RecordEntry {
        index,
        seat,
        action,
        events: events.clone(),
    };
    store
        .append_action(running.id, entry.clone(), snapshot)
        .await
        .map_err(|error| {
            error!(game = running.id.0, %error, "storing an action failed");
            ErrorCode::Internal
        })?;
    metrics.actions_applied.inc();
    running.game = next;
    running.record.push_entry(entry);
    if let Some(winner) = running.game.winner() {
        info!(game = running.id.0, winner, "game finished");
        if let Err(error) = end_game(running, store, GameEnd::Finished { winner }).await {
            error!(game = running.id.0, %error, "marking the game finished failed");
        }
    }
    Ok(events)
}

/// Applies a bot's choice; one the game rejects is replaced by ending the turn, or else the first legal action, so a
/// bot's mistake does not stall the game.
async fn apply_bot_choice<S: GameStore>(
    running: &mut RunningGame,
    store: &S,
    metrics: &Metrics,
    seat: Seat,
    action: Action,
    legal: &[Action],
) -> Result<Vec<Event>, ErrorCode> {
    let error = match apply_and_store(running, store, metrics, seat, action).await {
        Err(ErrorCode::Game { error }) => error,
        result => return result,
    };
    warn!(
        game = running.id.0,
        seat,
        ?error,
        "bot move rejected, falling back"
    );
    let fallback = legal
        .iter()
        .find(|candidate| **candidate == Action::EndTurn)
        .or_else(|| legal.first())
        .cloned()
        .ok_or(ErrorCode::Game { error })?;
    apply_and_store(running, store, metrics, seat, fallback).await
}

/// The one way a running game ends: stores the end and stops counting the game as running, at most once. A finished
/// game stops counting even when the store fails; an abandoned one only once the store has it, as the lobby retries.
async fn end_game<S: GameStore>(
    running: &mut RunningGame,
    store: &S,
    end: GameEnd,
) -> Result<(), StoreError> {
    match end {
        GameEnd::Finished { winner } => {
            running.in_progress.end();
            store.finish(running.id, winner).await
        }
        GameEnd::Abandoned => {
            store.abandon(running.id).await?;
            running.in_progress.end();
            Ok(())
        }
    }
}

fn seat_player(occupant: &SeatOccupant, fallback: Difficulty) -> SeatPlayer {
    match occupant {
        SeatOccupant::Human { user } => SeatPlayer::Human(user.clone()),
        SeatOccupant::Bot { difficulty, .. } => SeatPlayer::Bot(*difficulty),
        // Start requires every seat filled.
        SeatOccupant::Open => SeatPlayer::Bot(fallback),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use settler_island_bot::{Bot, Difficulty};
    use settler_island_game::{Action, PlayerView, ResourceCounts};
    use settler_island_protocol::{LobbyId, User, UserId, UserKind};
    use tokio::sync::{mpsc, Notify};

    use super::{open, Lobby, LobbySetup, SeatCount};
    use crate::config::{Config, SessionSecret};
    use crate::metrics::Metrics;
    use crate::outbox::{Outbox, OUTBOX_CAPACITY};
    use crate::store::MemoryStore;

    /// Always asks for something the game never accepts from it.
    struct IllegalBot;

    impl Bot for IllegalBot {
        fn choose(&mut self, _view: &PlayerView, _legal: &[Action]) -> Action {
            Action::Discard {
                resources: ResourceCounts::default(),
            }
        }
    }

    async fn started_lobby(metrics: Arc<Metrics>) -> Lobby<MemoryStore> {
        let owner = User {
            id: UserId("ada".to_string()),
            name: "Ada".to_string(),
            kind: UserKind::Guest,
        };
        let (sender, _) = mpsc::channel(OUTBOX_CAPACITY);
        let (notices, _) = mpsc::unbounded_channel();
        let setup = LobbySetup {
            id: LobbyId(1),
            name: "Table".to_string(),
            owner: owner.clone(),
            outbox: Outbox::new(sender, Arc::new(Notify::new())),
            request_id: 1,
            has_password: false,
            seats: SeatCount::new(3).unwrap(),
            points_to_win: 10,
            bot_difficulty: Difficulty::Random,
        };
        let mut config = Config::new(SessionSecret::new(vec![7; 64]).unwrap());
        config.seed = Some(5);
        let store = Arc::new(MemoryStore::default());
        let mut lobby = open(setup, store, Arc::new(config), metrics, notices);
        for _ in 0..2 {
            lobby.add_bot(&owner.id, 1, Difficulty::Random).unwrap();
        }
        lobby.start(&owner.id, 1).await.unwrap();
        lobby
    }

    fn running_games(metrics: &Metrics) -> String {
        let text = metrics.render().unwrap();
        let line = text
            .lines()
            .find(|line| line.starts_with("settler_running_games "));
        line.unwrap().to_string()
    }

    #[tokio::test]
    async fn a_rejected_bot_move_falls_back_instead_of_stalling_the_game() {
        let mut lobby = started_lobby(Arc::new(Metrics::new().unwrap())).await;
        let running = lobby.game.as_mut().unwrap();
        running.bots = (0..3)
            .map(|_| Some(Box::new(IllegalBot) as Box<dyn Bot>))
            .collect();
        let moves = 40;
        for _ in 0..moves {
            lobby.play_bot().await;
        }
        let running = lobby.game.as_ref().unwrap();
        assert!(!running.stalled);
        assert_eq!(running.record.entries.len(), moves);
    }

    #[tokio::test]
    async fn an_abandoned_game_is_counted_down_once_when_its_lobby_closes() {
        let metrics = Arc::new(Metrics::new().unwrap());
        let mut lobby = started_lobby(metrics.clone()).await;
        assert_eq!(running_games(&metrics), "settler_running_games 1");
        assert!(lobby.abandon().await);
        drop(lobby);
        assert_eq!(running_games(&metrics), "settler_running_games 0");
    }
}
