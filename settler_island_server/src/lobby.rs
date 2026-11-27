use std::sync::Arc;
use std::time::Duration;

use settler_island_bot::{bot_seed, create_bot, Bot, Difficulty};
use settler_island_game::{
    Action, Event, Game, GameRecord, GameSettings, RecordEntry, Seat, MAX_SEATS, MIN_SEATS,
};

use crate::store::StoredGame;
use settler_island_protocol::{
    AwayPolicy, ErrorCode, LobbyDetails, LobbyId, LobbyInfo, LobbySummary, SeatOccupant,
    ServerMessage, User, UserId,
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

/// Sent to the registry. Only `Starting` is answered; the registry never waits on a lobby, so a lobby may wait on it.
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
    /// Asks to seat `users` in a new game; refused with `LimitReached` when a game cap is reached.
    Starting {
        lobby: LobbyId,
        users: Vec<UserId>,
        reply: Reply,
    },
}

/// Tells the registry that the lobby closed however its task ends, a panic included, so the registry never keeps
/// pointing at a dead task.
struct ClosedNotice {
    lobby: LobbyId,
    notices: mpsc::UnboundedSender<LobbyNotice>,
}

impl Drop for ClosedNotice {
    fn drop(&mut self) {
        info!(lobby = self.lobby.0, "lobby closed");
        // The registry is gone only during shutdown.
        let _ = self.notices.send(LobbyNotice::Closed(self.lobby));
    }
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
    pub away_policy: AwayPolicy,
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
    /// The seats humans were dealt, whoever plays them now.
    human_seats: Vec<Seat>,
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
    /// A human seat has moved, by its player or by the bot standing in while another human was connected.
    fn humans_played(&self) -> bool {
        self.record
            .entries
            .iter()
            .any(|entry| self.human_seats.contains(&entry.seat))
    }
}

struct Lobby<S> {
    id: LobbyId,
    name: String,
    owner: User,
    has_password: bool,
    seats: Vec<SeatOccupant>,
    points_to_win: u8,
    /// Plays for a player who leaves a running game under `AwayPolicy::BotTakesOver`.
    bot_difficulty: Difficulty,
    away_policy: AwayPolicy,
    members: Vec<Member>,
    game: Option<RunningGame>,
    bot_deadline: Instant,
    /// Until when a bot that offered a trade waits for the humans it asked; `None` without an open offer.
    answers_due: Option<Instant>,
    /// When a running game with no connected human is closed; `None` while a human is connected, or when the grace
    /// is too long for an `Instant`, which means never.
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
        away_policy: setup.away_policy,
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

/// Recreates the lobby of a game that was running when the server stopped: every human seat is away, under a bot
/// or waiting as the lobby's policy says, and bots only move once a human is back.
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
    let mut human_seats = Vec::new();
    for (seat, player) in stored.game.seats.iter().enumerate() {
        let occupant = match player {
            SeatPlayer::Human(user) => {
                human_seats.extend(Seat::try_from(seat).ok());
                away_occupant(stored.game.away_policy, away, user.clone())
            }
            SeatPlayer::Bot(difficulty) => SeatOccupant::Bot {
                difficulty: *difficulty,
                reserved_for: None,
            },
        };
        bots.push(stand_in(&occupant, bot_seed(seed, seat)));
        seats.push(occupant);
    }
    let owner = stored.game.seats.iter().find_map(|player| match player {
        SeatPlayer::Human(user) => Some(user.clone()),
        SeatPlayer::Bot(_) => None,
    })?;
    let mut lobby = Lobby {
        id: stored.game.lobby,
        name: stored.game.lobby_name.clone(),
        owner,
        has_password: false,
        seats,
        points_to_win: stored.game.settings.points_to_win,
        bot_difficulty: away,
        away_policy: stored.game.away_policy,
        members: Vec::new(),
        game: Some(RunningGame {
            id: stored.id,
            game,
            record,
            bots,
            human_seats,
            stalled: false,
            seed,
            in_progress: metrics.game_started(),
        }),
        bot_deadline: Instant::now(),
        answers_due: None,
        abandon_at: None,
        store,
        config,
        metrics,
        notices,
    };
    // The time nobody was connected before the restart counts toward the deadline.
    let unattended_for = stored.unattended_for.unwrap_or_default();
    lobby.abandon_at =
        Instant::now().checked_add(lobby.abandon_grace().saturating_sub(unattended_for));
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
        let _closed = ClosedNotice {
            lobby: self.id,
            notices: self.notices.clone(),
        };
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
            let displaced = std::mem::replace(&mut member.outbox, outbox);
            displaced.send_and_close(ServerMessage::Error {
                request_id: None,
                code: ErrorCode::TakenOver,
                message: ErrorCode::TakenOver.description(),
            });
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
            self.abandon_at = Instant::now().checked_add(self.abandon_grace());
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
                let occupant = away_occupant(self.away_policy, self.bot_difficulty, member.user);
                running.bots[index] = stand_in(&occupant, bot_seed(running.seed, index));
                self.bot_deadline = Instant::now() + self.config.bot_delay;
                occupant
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
        let admission = self.ask_to_start();
        // No answer means the registry is shutting down.
        admission.await.map_err(|_| ErrorCode::Internal)??;
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
            away_policy: self.away_policy,
        };
        let stored = self.store.create_game(new_game).await;
        let id = stored.inspect_err(|error| {
            error!(lobby = self.id.0, %error, "storing the new game failed");
            // Frees the seats the registry counted for this game.
            self.note_membership(LobbyNotice::Seated {
                lobby: self.id,
                users: Vec::new(),
            });
        });
        let id = id.map_err(|_| ErrorCode::Internal)?;
        let bots = self
            .seats
            .iter()
            .enumerate()
            .map(|(seat, occupant)| stand_in(occupant, bot_seed(settings.seed, seat)))
            .collect();
        let human_seats = (0..)
            .zip(&self.seats)
            .filter(|(_, occupant)| matches!(occupant, SeatOccupant::Human { .. }))
            .map(|(seat, _)| seat)
            .collect();
        self.game = Some(RunningGame {
            id,
            record: GameRecord::new(&game),
            game,
            bots,
            human_seats,
            stalled: false,
            seed: settings.seed,
            in_progress: self.metrics.game_started(),
        });
        self.bot_deadline = Instant::now() + self.config.bot_delay;
        info!(lobby = self.id.0, game = id.0, "game started");
        self.broadcast_state(Some((user, request_id)));
        for member in self.member_ids() {
            let echo = (member == *user).then_some(request_id);
            self.send_game_started(&member, echo);
        }
        Ok(())
    }

    /// Asks the registry to count the members as seated in a new game, within the server's game caps.
    fn ask_to_start(&self) -> oneshot::Receiver<Result<(), ErrorCode>> {
        let (reply, answer) = oneshot::channel();
        self.note_membership(LobbyNotice::Starting {
            lobby: self.id,
            users: self.member_ids(),
            reply,
        });
        answer
    }

    /// How long a running game may go without a connected human. A game no human has moved in was most likely started
    /// only to be left, so it gets the short `unattended_abandon_after`; one that humans played keeps `abandon_after`.
    fn abandon_grace(&self) -> Duration {
        let played = self.game.as_ref().is_some_and(RunningGame::humans_played);
        if played {
            return self.config.abandon_after;
        }
        self.config
            .abandon_after
            .min(self.config.unattended_abandon_after)
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
    /// does not play itself out, and while the game waits for an away player; a bot that offered a trade waits for
    /// the connected humans it asked, up to `answers_due`.
    fn bot_move(&self) -> Option<(Seat, Instant)> {
        if self.members.is_empty() {
            return None;
        }
        let running = self.game.as_ref().filter(|running| !running.stalled)?;
        if self.waits_for_away_player(running) {
            return None;
        }
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
            Some(due) if offering && self.human_answer_pending(running) => {
                due.max(self.bot_deadline)
            }
            _ => self.bot_deadline,
        };
        Some((seat, at))
    }

    /// An away seat is pending and the game cannot go on without it; one merely asked in another seat's trade offer
    /// does not hold the game up, as the offerer may close the trade without that answer.
    fn waits_for_away_player(&self, running: &RunningGame) -> bool {
        let offerer = running
            .game
            .phase()
            .trade_offer()
            .map(|offer| offer.offerer);
        running.game.pending_seats().into_iter().any(|seat| {
            let away = matches!(
                self.seats.get(usize::from(seat)),
                Some(SeatOccupant::Away { .. })
            );
            away && offerer.is_none_or(|offerer| offerer == seat)
        })
    }

    /// A connected human asked in the open trade who has not answered yet; away players cannot answer.
    fn human_answer_pending(&self, running: &RunningGame) -> bool {
        let Some(offer) = running.game.phase().trade_offer() else {
            return false;
        };
        (0..).zip(&self.seats).any(|(seat, occupant)| {
            matches!(occupant, SeatOccupant::Human { .. }) && offer.awaits_answer_from(seat)
        })
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

    fn member_ids(&self) -> Vec<UserId> {
        self.members
            .iter()
            .map(|member| member.user.id.clone())
            .collect()
    }

    fn member(&self, user: &UserId) -> Option<&Member> {
        self.members.iter().find(|member| member.user.id == *user)
    }

    fn seat_of(&self, user: &UserId) -> Option<Seat> {
        self.find_seat(
            |occupant| matches!(occupant, SeatOccupant::Human { user: seated } if seated.id == *user),
        )
    }

    /// The seat a player who left the running game comes back to.
    fn reserved_seat(&self, user: &UserId) -> Option<Seat> {
        self.find_seat(|occupant| match occupant {
            SeatOccupant::Bot {
                reserved_for: Some(reserved),
                ..
            }
            | SeatOccupant::Away { user: reserved } => reserved.id == *user,
            _ => false,
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

    fn info(&self) -> LobbyInfo {
        LobbyInfo {
            id: self.id,
            name: self.name.clone(),
            owner: self.owner.clone(),
            has_password: self.has_password,
            started: self.game.is_some(),
            points_to_win: self.points_to_win,
            bot_difficulty: self.bot_difficulty,
            away_policy: self.away_policy,
        }
    }

    fn details(&self) -> LobbyDetails {
        LobbyDetails {
            info: self.info(),
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
            info: self.info(),
            seats: self.seat_count(),
            open_seats: u8::try_from(open_seats).unwrap_or(MAX_SEATS),
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

/// The seat of a human who is away from a running game, as the lobby's policy says.
fn away_occupant(policy: AwayPolicy, difficulty: Difficulty, user: User) -> SeatOccupant {
    match policy {
        AwayPolicy::BotTakesOver => SeatOccupant::Bot {
            difficulty,
            reserved_for: Some(user),
        },
        AwayPolicy::WaitForPlayer => SeatOccupant::Away { user },
    }
}

/// The bot that plays the seat, where a bot does.
fn stand_in(occupant: &SeatOccupant, seed: u64) -> Option<Box<dyn Bot>> {
    match occupant {
        SeatOccupant::Bot { difficulty, .. } => Some(create_bot(*difficulty, seed)),
        _ => None,
    }
}

fn seat_player(occupant: &SeatOccupant, fallback: Difficulty) -> SeatPlayer {
    match occupant {
        SeatOccupant::Human { user } | SeatOccupant::Away { user } => {
            SeatPlayer::Human(user.clone())
        }
        SeatOccupant::Bot { difficulty, .. } => SeatPlayer::Bot(*difficulty),
        // Start requires every seat filled.
        SeatOccupant::Open => SeatPlayer::Bot(fallback),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::time::Duration;

    use settler_island_bot::{create_bot, Bot, Difficulty};
    use settler_island_game::{Action, Phase, PlayerView, Resource, ResourceCounts, Seat};
    use settler_island_protocol::{AwayPolicy, LobbyId, SeatOccupant, User, UserId, UserKind};
    use tokio::sync::{mpsc, Notify};
    use tokio::time::Instant;

    use super::{open, Lobby, LobbyNotice, LobbySetup, Member, SeatCount};
    use crate::config::{Config, SessionSecret};
    use crate::metrics::Metrics;
    use crate::outbox::Outbox;
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

    fn config() -> Config {
        let mut config = Config::new(SessionSecret::new((0..64).collect::<Vec<u8>>()).unwrap());
        config.seed = Some(5);
        config
    }

    async fn started_lobby(metrics: Arc<Metrics>, config: Config) -> Lobby<MemoryStore> {
        let owner = User {
            id: UserId("ada".to_string()),
            name: "Ada".to_string(),
            kind: UserKind::Guest,
        };
        let (outbox, _) = Outbox::channel(Arc::new(Notify::new()));
        let (notices, mut registry) = mpsc::unbounded_channel();
        // Stands in for the registry, which admits every start.
        tokio::spawn(async move {
            while let Some(notice) = registry.recv().await {
                if let LobbyNotice::Starting { reply, .. } = notice {
                    let _ = reply.send(Ok(()));
                }
            }
        });
        let setup = LobbySetup {
            id: LobbyId(1),
            name: "Table".to_string(),
            owner: owner.clone(),
            outbox,
            request_id: 1,
            has_password: false,
            seats: SeatCount::new(3).unwrap(),
            points_to_win: 10,
            bot_difficulty: Difficulty::Random,
            away_policy: AwayPolicy::BotTakesOver,
        };
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
        let mut lobby = started_lobby(Arc::new(Metrics::new().unwrap()), config()).await;
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
        let mut lobby = started_lobby(metrics.clone(), config()).await;
        assert_eq!(running_games(&metrics), "settler_running_games 1");
        assert!(lobby.abandon().await);
        drop(lobby);
        assert_eq!(running_games(&metrics), "settler_running_games 0");
    }

    #[tokio::test]
    async fn a_grace_too_long_for_an_instant_never_comes_instead_of_panicking() {
        let config = Config {
            abandon_after: Duration::MAX,
            unattended_abandon_after: Duration::MAX,
            ..config()
        };
        let mut lobby = started_lobby(Arc::new(Metrics::new().unwrap()), config).await;
        let member = &lobby.members[0];
        let (owner, outbox) = (member.user.id.clone(), member.outbox.clone());

        lobby.leave(&owner, &outbox);

        assert!(lobby.members.is_empty());
        assert_eq!(lobby.abandon_at, None);
    }

    /// A card `seat` holds while it is in its main turn.
    fn card_to_offer(lobby: &Lobby<MemoryStore>, seat: Seat) -> Option<Resource> {
        let game = &lobby.game.as_ref()?.game;
        if *game.phase() != Phase::Main || game.current_seat() != seat {
            return None;
        }
        let hand = game.view(Some(seat)).own?.hand;
        Resource::ALL
            .into_iter()
            .find(|resource| hand.get(*resource) > 0)
    }

    /// A started `WaitForPlayer` lobby whose bots (one standing in for Ada on seat 0) played until `seat` has its main
    /// turn with a card in hand; returns that card.
    async fn lobby_where_seat_can_offer(seat: Seat) -> (Lobby<MemoryStore>, Resource) {
        let mut lobby = started_lobby(Arc::new(Metrics::new().unwrap()), config()).await;
        lobby.away_policy = AwayPolicy::WaitForPlayer;
        lobby.game.as_mut().unwrap().bots[0] = Some(create_bot(Difficulty::Random, 1));
        for _ in 0..2000 {
            if let Some(card) = card_to_offer(&lobby, seat) {
                return (lobby, card);
            }
            lobby.play_bot().await;
        }
        panic!("seat {seat} never had a main turn with cards");
    }

    /// Ada leaves seat 0 while Bob stays connected, so only the away seat can hold the bots back.
    fn ada_leaves_while_bob_stays(lobby: &mut Lobby<MemoryStore>) {
        let member = &lobby.members[0];
        let (owner, outbox) = (member.user.id.clone(), member.outbox.clone());
        lobby.leave(&owner, &outbox);
        assert!(matches!(lobby.seats[0], SeatOccupant::Away { .. }));
        let (bob_outbox, _) = Outbox::channel(Arc::new(Notify::new()));
        let bob = User {
            id: UserId("bob".to_string()),
            name: "Bob".to_string(),
            kind: UserKind::Guest,
        };
        lobby.members.push(Member {
            user: bob,
            outbox: bob_outbox,
        });
    }

    fn offer_one(give: Resource, to: Option<Seat>) -> Action {
        let receive = Resource::ALL
            .into_iter()
            .find(|resource| *resource != give)
            .unwrap();
        let mut gives = ResourceCounts::default();
        gives.set(give, 1);
        let mut receives = ResourceCounts::default();
        receives.set(receive, 1);
        Action::OfferTrade {
            give: gives,
            receive: receives,
            to,
        }
    }

    #[tokio::test]
    async fn an_away_player_asked_in_a_bot_trade_neither_holds_up_nor_delays_the_offerer() {
        let (mut lobby, card) = lobby_where_seat_can_offer(1).await;
        ada_leaves_while_bob_stays(&mut lobby);
        let offer = offer_one(card, Some(0));
        lobby.game.as_mut().unwrap().game.apply(1, offer).unwrap();
        lobby.answers_due = Some(Instant::now() + Duration::from_secs(3600));

        assert_eq!(lobby.bot_move(), Some((1, lobby.bot_deadline)));
    }

    #[tokio::test]
    async fn bots_asked_in_the_trade_of_an_away_player_wait_for_them() {
        let (mut lobby, card) = lobby_where_seat_can_offer(0).await;
        let offer = offer_one(card, None);
        lobby.game.as_mut().unwrap().game.apply(0, offer).unwrap();
        ada_leaves_while_bob_stays(&mut lobby);

        assert_eq!(lobby.bot_move(), None);
    }
}
