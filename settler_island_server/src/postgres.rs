use std::time::Duration;

use settler_island_bot::Difficulty;
use settler_island_game::{Action, Event, Game, GameSettings, RecordSettings, Seat};
use settler_island_protocol::{LobbyId, User, UserId, UserKind};
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::types::Json;
use sqlx::{PgPool, Postgres, Transaction};

use crate::identity::{IdentityStore, IdentityStoreError};
use crate::store::{
    GameId, GameStore, NewGame, SeatPlayer, Snapshot, StoreError, StoredAction, StoredGame,
};

const MAX_CONNECTIONS: u32 = 8;

/// Games and identity links in Postgres; cheap to clone (the pool is shared).
#[derive(Debug, Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    /// Connects and applies pending migrations.
    pub async fn connect(options: PgConnectOptions) -> Result<PostgresStore, StoreError> {
        let pool = PgPoolOptions::new()
            .max_connections(MAX_CONNECTIONS)
            .connect_with(options)
            .await?;
        sqlx::migrate!().run(&pool).await?;
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
        let expected = u32::try_from(next).map_err(|_| corrupt(game, "action index"))?;
        Ok(StoreError::OutOfOrder { expected, got })
    }

    async fn load(&self, row: GameRow) -> Result<StoredGame, StoreError> {
        let id = GameId(u64::try_from(row.id).map_err(|_| corrupt(GameId(0), "game id"))?);
        let seats = self.load_seats(id, row.id).await?;
        let actions = self.load_actions(id, row.id).await?;
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
                    .map_err(|_| corrupt(id, "snapshot index"))?,
                state: snapshot.state.0,
            })
        })
        .transpose()?;
        let lobby = u32::try_from(row.lobby_id).map_err(|_| corrupt(id, "lobby id"))?;
        Ok(StoredGame {
            id,
            game: NewGame {
                settings: GameSettings {
                    seats: row.settings.0.seats,
                    points_to_win: row.settings.0.points_to_win,
                    // Stored as the same 64 bits.
                    seed: row.seed as u64,
                },
                seats,
                lobby: LobbyId(lobby),
                lobby_name: row.lobby_name,
                bot_difficulty: row.bot_difficulty.0,
            },
            actions,
            snapshot,
            // A clock set back makes the difference negative; treat that as just left.
            unattended_for: row
                .unattended_seconds
                .map(|seconds| Duration::from_secs(u64::try_from(seconds).unwrap_or(0))),
        })
    }

    async fn load_seats(&self, id: GameId, game: i64) -> Result<Vec<SeatPlayer>, StoreError> {
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
                    return Err(corrupt(id, "seat"));
                };
                let kind = parse_kind(&kind).ok_or_else(|| corrupt(id, "user kind"))?;
                Ok(SeatPlayer::Human(User {
                    id: UserId(user_id),
                    name,
                    kind,
                }))
            })
            .collect()
    }

    async fn load_actions(&self, id: GameId, game: i64) -> Result<Vec<StoredAction>, StoreError> {
        let rows = sqlx::query!(
            r#"SELECT index, seat, action AS "action: Json<Action>", events AS "events: Json<Vec<Event>>"
               FROM game_actions WHERE game = $1 ORDER BY index"#,
            game,
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| {
                Ok(StoredAction {
                    index: u32::try_from(row.index).map_err(|_| corrupt(id, "action index"))?,
                    seat: Seat::try_from(row.seat).map_err(|_| corrupt(id, "seat"))?,
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
    settings: Json<RecordSettings>,
    seed: i64,
    unattended_seconds: Option<i64>,
}

impl GameStore for PostgresStore {
    async fn create_game(&self, game: NewGame) -> Result<GameId, StoreError> {
        let mut transaction = self.pool.begin().await?;
        let settings = RecordSettings {
            seats: game.settings.seats,
            points_to_win: game.settings.points_to_win,
        };
        let id = sqlx::query_scalar!(
            "INSERT INTO games (lobby_id, lobby_name, bot_difficulty, settings, seed)
             VALUES ($1, $2, $3, $4, $5) RETURNING id",
            // Lobby ids are small counters; the column is signed.
            game.lobby.0 as i32,
            game.lobby_name,
            Json(game.bot_difficulty) as _,
            Json(settings) as _,
            // Stored as the same 64 bits.
            game.settings.seed as i64,
        )
        .fetch_one(&mut *transaction)
        .await?;
        for (seat, player) in game.seats.iter().enumerate() {
            Self::insert_seat(&mut transaction, id, seat as i16, player).await?;
        }
        transaction.commit().await?;
        u64::try_from(id)
            .map(GameId)
            .map_err(|_| corrupt(GameId(0), "game id"))
    }

    async fn append_action(
        &self,
        game: GameId,
        action: StoredAction,
        snapshot: Option<Game>,
    ) -> Result<(), StoreError> {
        let id = database_id(game)?;
        let index = i32::try_from(action.index).map_err(|_| corrupt(game, "action index"))?;
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
             ON CONFLICT (keycloak_sub) DO NOTHING",
            subject,
            user.0,
        )
        .execute(&self.pool)
        .await?;
        // A separate statement sees a concurrent winner's link once it committed.
        let linked = sqlx::query_scalar!(
            "SELECT user_id FROM identity_links WHERE keycloak_sub = $1",
            subject,
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(UserId(linked))
    }
}

fn database_id(game: GameId) -> Result<i64, StoreError> {
    i64::try_from(game.0).map_err(|_| StoreError::UnknownGame(game))
}

fn corrupt(game: GameId, field: &'static str) -> StoreError {
    StoreError::Corrupt { game, field }
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
