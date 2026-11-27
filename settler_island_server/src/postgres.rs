use std::time::Duration;

use settler_island_bot::Difficulty;
use settler_island_game::{Action, Event, Game, GameSettings, RecordEntry, RecordSettings, Seat};
use settler_island_protocol::{AwayPolicy, LobbyId, User, UserId, UserKind};
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::types::Json;
use sqlx::{ConnectOptions, Connection, PgPool, Postgres, Transaction};

use crate::identity::{IdentityStore, IdentityStoreError};
use crate::store::{GameId, GameStore, NewGame, SeatPlayer, Snapshot, StoreError, StoredGame};

/// A query running longer than this is cancelled by the database, so a stalled one errors instead of holding a
/// lobby task (and its pooled connection) indefinitely.
const STATEMENT_TIMEOUT: Duration = Duration::from_secs(5);

/// How the connection pool is sized and how long a caller waits for a connection.
#[derive(Debug, Clone, Copy)]
pub struct PoolSettings {
    pub max_connections: u32,
    pub acquire_timeout: Duration,
}

/// Games and identity links in Postgres; cheap to clone (the pool is shared).
#[derive(Debug, Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    /// Connects and applies pending migrations.
    pub async fn connect(
        options: PgConnectOptions,
        settings: PoolSettings,
    ) -> Result<PostgresStore, StoreError> {
        // Migrations may legitimately outlast the statement timeout, so they run on a connection without it.
        let mut connection = options.connect().await?;
        sqlx::migrate!().run(&mut connection).await?;
        connection.close().await?;
        let timeout = STATEMENT_TIMEOUT.as_millis().to_string();
        let pool = PgPoolOptions::new()
            .max_connections(settings.max_connections)
            .acquire_timeout(settings.acquire_timeout)
            .connect_with(options.options([("statement_timeout", timeout.as_str())]))
            .await?;
        Ok(PostgresStore { pool })
    }

    async fn insert_seat(
        transaction: &mut Transaction<'_, Postgres>,
        game: i64,
        seat: i16,
        player: &SeatPlayer,
    ) -> Result<(), StoreError> {
        match player {
            SeatPlayer::Human(user) => {
                sqlx::query!(
                    "INSERT INTO users (id, kind, name) VALUES ($1, $2, $3)
                     ON CONFLICT (id) DO UPDATE SET kind = excluded.kind, name = excluded.name",
                    user.id.0,
                    kind_name(user.kind),
                    user.name,
                )
                .execute(&mut **transaction)
                .await?;
                sqlx::query!(
                    "INSERT INTO game_seats (game, seat, user_id) VALUES ($1, $2, $3)",
                    game,
                    seat,
                    user.id.0,
                )
                .execute(&mut **transaction)
                .await?;
            }
            SeatPlayer::Bot(difficulty) => {
                sqlx::query!(
                    "INSERT INTO game_seats (game, seat, bot_difficulty) VALUES ($1, $2, $3)",
                    game,
                    seat,
                    Json(difficulty) as _,
                )
                .execute(&mut **transaction)
                .await?;
            }
        }
        Ok(())
    }

    /// Why an append matched no running game at the expected index.
    async fn append_rejection(
        transaction: &mut Transaction<'_, Postgres>,
        game: GameId,
        got: u32,
    ) -> Result<StoreError, StoreError> {
        let next = sqlx::query_scalar!(
            r#"SELECT (SELECT COALESCE(MAX(index) + 1, 0) FROM game_actions WHERE game = games.id) AS "next!"
               FROM games WHERE id = $1 AND status = 'running'"#,
            database_id(game)?,
        )
        .fetch_optional(&mut **transaction)
        .await?;
        let Some(next) = next else {
            return Ok(StoreError::UnknownGame(game));
        };
        let row = database_id(game)?;
        let expected = u32::try_from(next).map_err(|_| corrupt(row, "action index"))?;
        Ok(StoreError::OutOfOrder { expected, got })
    }

    async fn load(&self, row: GameRow) -> Result<StoredGame, StoreError> {
        let raw = row.id;
        let id = GameId(u64::try_from(raw).map_err(|_| corrupt(raw, "game id"))?);
        let seats = self.load_seats(raw).await?;
        let actions = self.load_actions(raw).await?;
        let snapshot = sqlx::query!(
            r#"SELECT index, state AS "state: Json<Game>" FROM game_snapshots
               WHERE game = $1 ORDER BY index DESC LIMIT 1"#,
            row.id,
        )
        .fetch_optional(&self.pool)
        .await?
        .map(|snapshot| -> Result<Snapshot, StoreError> {
            Ok(Snapshot {
                actions: u32::try_from(snapshot.index)
                    .map_err(|_| corrupt(raw, "snapshot index"))?,
                state: snapshot.state.0,
            })
        })
        .transpose()?;
        let lobby = u32::try_from(row.lobby_id).map_err(|_| corrupt(raw, "lobby id"))?;
        Ok(StoredGame {
            id,
            game: NewGame {
                settings: GameSettings {
                    seats: row.settings.0.seats,
                    points_to_win: row.settings.0.points_to_win,
                    // Stored as the same 64 bits.
                    seed: u64::from_ne_bytes(row.seed.to_ne_bytes()),
                },
                seats,
                lobby: LobbyId(lobby),
                lobby_name: row.lobby_name,
                bot_difficulty: row.bot_difficulty.0,
                away_policy: row.away_policy.0,
            },
            actions,
            snapshot,
            // A clock set back makes the difference negative; treat that as just left.
            unattended_for: row
                .unattended_seconds
                .map(|seconds| Duration::from_secs(u64::try_from(seconds).unwrap_or(0))),
        })
    }

    async fn load_seats(&self, game: i64) -> Result<Vec<SeatPlayer>, StoreError> {
        let rows = sqlx::query!(
            r#"SELECT seat.bot_difficulty AS "bot_difficulty: Json<Difficulty>",
                      users.id AS "user_id?", users.name AS "user_name?", users.kind AS "user_kind?"
               FROM game_seats seat LEFT JOIN users ON users.id = seat.user_id
               WHERE seat.game = $1 ORDER BY seat.seat"#,
            game,
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| {
                if let Some(difficulty) = row.bot_difficulty {
                    return Ok(SeatPlayer::Bot(difficulty.0));
                }
                let (Some(user_id), Some(name), Some(kind)) =
                    (row.user_id, row.user_name, row.user_kind)
                else {
                    return Err(corrupt(game, "seat"));
                };
                let kind = parse_kind(&kind).ok_or_else(|| corrupt(game, "user kind"))?;
                Ok(SeatPlayer::Human(User {
                    id: UserId(user_id),
                    name,
                    kind,
                }))
            })
            .collect()
    }

    async fn load_actions(&self, game: i64) -> Result<Vec<RecordEntry>, StoreError> {
        let rows = sqlx::query!(
            r#"SELECT index, seat, action AS "action: Json<Action>", events AS "events: Json<Vec<Event>>"
               FROM game_actions WHERE game = $1 ORDER BY index"#,
            game,
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| {
                Ok(RecordEntry {
                    index: u32::try_from(row.index).map_err(|_| corrupt(game, "action index"))?,
                    seat: Seat::try_from(row.seat).map_err(|_| corrupt(game, "seat"))?,
                    action: row.action.0,
                    events: row.events.0,
                })
            })
            .collect()
    }
}

struct GameRow {
    id: i64,
    lobby_id: i32,
    lobby_name: String,
    bot_difficulty: Json<Difficulty>,
    away_policy: Json<AwayPolicy>,
    settings: Json<RecordSettings>,
    seed: i64,
    unattended_seconds: Option<i64>,
}

impl GameStore for PostgresStore {
    async fn create_game(&self, game: NewGame) -> Result<GameId, StoreError> {
        let lobby = i32::try_from(game.lobby.0).map_err(|_| out_of_range("lobby id"))?;
        let mut transaction = self.pool.begin().await?;
        let settings = RecordSettings {
            seats: game.settings.seats,
            points_to_win: game.settings.points_to_win,
        };
        let id = sqlx::query_scalar!(
            "INSERT INTO games (lobby_id, lobby_name, bot_difficulty, away_policy, settings, seed)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
            lobby,
            game.lobby_name,
            Json(game.bot_difficulty) as _,
            Json(game.away_policy) as _,
            Json(settings) as _,
            // Stored as the same 64 bits.
            i64::from_ne_bytes(game.settings.seed.to_ne_bytes()),
        )
        .fetch_one(&mut *transaction)
        .await?;
        for (seat, player) in game.seats.iter().enumerate() {
            let seat = i16::try_from(seat).map_err(|_| out_of_range("seat"))?;
            Self::insert_seat(&mut transaction, id, seat, player).await?;
        }
        transaction.commit().await?;
        u64::try_from(id)
            .map(GameId)
            .map_err(|_| corrupt(id, "game id"))
    }

    async fn append_action(
        &self,
        game: GameId,
        action: RecordEntry,
        snapshot: Option<Game>,
    ) -> Result<(), StoreError> {
        let id = database_id(game)?;
        let index = i32::try_from(action.index).map_err(|_| out_of_range("action index"))?;
        let mut transaction = self.pool.begin().await?;
        // Inserts only into a running game and only at the next index.
        let inserted = sqlx::query!(
            "INSERT INTO game_actions (game, index, seat, action, events)
             SELECT $1, $2, $3, $4, $5 FROM games
             WHERE id = $1 AND status = 'running'
               AND $2 = (SELECT COALESCE(MAX(index) + 1, 0) FROM game_actions WHERE game = $1)",
            id,
            index,
            i16::from(action.seat),
            Json(&action.action) as _,
            Json(&action.events) as _,
        )
        .execute(&mut *transaction)
        .await?
        .rows_affected();
        if inserted == 0 {
            return Err(Self::append_rejection(&mut transaction, game, action.index).await?);
        }
        if let Some(state) = snapshot {
            sqlx::query!(
                "INSERT INTO game_snapshots (game, index, state) VALUES ($1, $2, $3)",
                id,
                index + 1,
                Json(&state) as _,
            )
            .execute(&mut *transaction)
            .await?;
        }
        transaction.commit().await?;
        Ok(())
    }

    async fn load_running(&self) -> Result<Vec<StoredGame>, StoreError> {
        let rows = sqlx::query_as!(
            GameRow,
            r#"SELECT id, lobby_id, lobby_name,
                      bot_difficulty AS "bot_difficulty: Json<Difficulty>",
                      away_policy AS "away_policy: Json<AwayPolicy>",
                      settings AS "settings: Json<RecordSettings>", seed,
                      EXTRACT(EPOCH FROM now() - unattended_since)::BIGINT AS "unattended_seconds?"
               FROM games WHERE status = 'running' ORDER BY id"#,
        )
        .fetch_all(&self.pool)
        .await?;
        let mut games = Vec::with_capacity(rows.len());
        for row in rows {
            games.push(self.load(row).await?);
        }
        Ok(games)
    }

    async fn finish(&self, game: GameId, winner: Seat) -> Result<(), StoreError> {
        let updated = sqlx::query!(
            "UPDATE games SET status = 'finished', finished = now(), winner = $2
             WHERE id = $1 AND status = 'running'",
            database_id(game)?,
            i16::from(winner),
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if updated == 0 {
            return Err(StoreError::UnknownGame(game));
        }
        Ok(())
    }

    async fn abandon(&self, game: GameId) -> Result<(), StoreError> {
        let updated = sqlx::query!(
            "UPDATE games SET status = 'abandoned', finished = now()
             WHERE id = $1 AND status = 'running'",
            database_id(game)?,
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if updated == 0 {
            return Err(StoreError::UnknownGame(game));
        }
        Ok(())
    }

    async fn set_attended(&self, game: GameId, attended: bool) -> Result<(), StoreError> {
        let updated = sqlx::query!(
            "UPDATE games
             SET unattended_since = CASE WHEN $2 THEN NULL ELSE COALESCE(unattended_since, now()) END
             WHERE id = $1 AND status = 'running'",
            database_id(game)?,
            attended,
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if updated == 0 {
            return Err(StoreError::UnknownGame(game));
        }
        Ok(())
    }
}

impl IdentityStore for PostgresStore {
    async fn linked_user(&self, subject: &str) -> Result<Option<UserId>, IdentityStoreError> {
        let user = sqlx::query_scalar!(
            "SELECT user_id FROM identity_links WHERE keycloak_sub = $1",
            subject,
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(user.map(UserId))
    }

    async fn link(&self, subject: &str, user: &UserId) -> Result<UserId, IdentityStoreError> {
        sqlx::query!(
            "INSERT INTO identity_links (keycloak_sub, user_id) VALUES ($1, $2)
             ON CONFLICT DO NOTHING",
            subject,
            user.0,
        )
        .execute(&self.pool)
        .await?;
        // A separate statement sees a concurrent winner's link once it committed.
        let linked = self.linked_user(subject).await?;
        // No row for the subject after the insert means the unique user id belongs to another account.
        linked.ok_or(IdentityStoreError::UserAlreadyLinked)
    }

    async fn is_linked(&self, user: &UserId) -> Result<bool, IdentityStoreError> {
        let linked = sqlx::query_scalar!(
            "SELECT EXISTS (SELECT 1 FROM identity_links WHERE user_id = $1) AS \"linked!\"",
            user.0,
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(linked)
    }
}

fn database_id(game: GameId) -> Result<i64, StoreError> {
    i64::try_from(game.0).map_err(|_| StoreError::UnknownGame(game))
}

fn corrupt(row: i64, field: &'static str) -> StoreError {
    StoreError::Corrupt { row, field }
}

fn out_of_range(field: &'static str) -> StoreError {
    StoreError::OutOfRange { field }
}

fn kind_name(kind: UserKind) -> &'static str {
    match kind {
        UserKind::Guest => "guest",
        UserKind::Account => "account",
    }
}

fn parse_kind(name: &str) -> Option<UserKind> {
    match name {
        "guest" => Some(UserKind::Guest),
        "account" => Some(UserKind::Account),
        _ => None,
    }
}
