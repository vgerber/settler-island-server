# Settler Island server

An authoritative multiplayer server for a hex-board settlement trading game. Clients connect over WebSocket (JSON
messages), meet in lobbies and play; the server owns all game state.

## Features

- **Rules engine** (`settler_island_game`): setup placement, dice and resource production, building, the robber,
  development cards, trading, longest road and largest army. Pure logic, deterministic from a seed plus the action log.
- **Bots** (`settler_island_bot`): a random and a heuristic strategy. A bot sees only its player view and picks from the
  legal actions. A bot also stands in for a player who leaves a running game.
- **Lobbies**: 3 or 4 seats, optional password, bots in open seats, 3 to 15 points to win, one lobby per user.
- **Guests and Keycloak**: guests get a server-signed session token (`POST /api/v1/sessions/guest`); Keycloak
  accounts authenticate with an access token and can claim a guest identity (`POST /api/v1/sessions/upgrade`). Both map
  to one user id. The session routes are rate limited per client address.
- **Persistence**: every action is written to Postgres before its events are sent; games survive a restart and a
  returning player is told which lobby holds their game (`Welcome.running_lobby`). Games without a connected human for
  a week are closed.
- **Operations**: `GET /api/v1/health`, Prometheus metrics at `GET /metrics`, configuration from the environment, JSON
  logs on request.
- **Generated Godot client**: GDScript types and a `SiClient` node generated from the protocol types (`client/`).

## Quick start

```sh
docker compose up -d db                                   # Postgres on 127.0.0.1:6436
cp .env.example .env                                      # every setting is documented; sets SQLX_OFFLINE=true
set -a && . ./.env && set +a
cargo run -p settler_island_server                        # listens on 127.0.0.1:8253
```

Without `DATABASE_URL` the server keeps games in memory only. For accounts, start the local Keycloak with
`docker compose --profile auth up -d keycloak` and set the two `SETTLER_KEYCLOAK_*` variables (see `.env.example`).

Endpoints: WebSocket `/api/v1/ws`, `GET /api/v1/health`, `GET /metrics`, `POST /api/v1/sessions/guest`,
`POST /api/v1/sessions/upgrade`.

## Tests

```sh
cargo test --workspace
```

Postgres tests skip unless `SETTLER_TEST_DATABASE_URL` points at a server (each test creates its own database):

```sh
SETTLER_TEST_DATABASE_URL=postgres://settler:settler@127.0.0.1:6436/settler_island cargo test --workspace
```

Queries are checked at compile time against `.sqlx`. `.env` (copied from `.env.example`) sets `SQLX_OFFLINE=true`, which
sqlx reads at compile time, so every `cargo` command builds with the database stopped. Without a `.env`, export
`SQLX_OFFLINE=true` first. Refresh the data after changing a query with the database running and
`cargo sqlx prepare --workspace` (install with `cargo install sqlx-cli --version 0.8.6 --locked`). New migrations go in
`settler_island_server/migrations` (`cargo sqlx migrate add <name> --source settler_island_server/migrations`).
CI runs format, clippy, `cargo sqlx prepare --workspace --check` and the tests, with and without Postgres (`.github/workflows/ci.yml`).

## Client generator

```sh
cargo run -p settler_island_client_generator            # rewrite client/ from the protocol types
cargo run -p settler_island_client_generator -- --check # fail when client/ is stale
```

Protocol changes land in `settler_island_protocol`; regenerate and commit `client/` together with them. Usage and the
type mapping are in [client/README.md](client/README.md).

## Layout

| Path | Role |
|---|---|
| `settler_island_game` | Rules engine |
| `settler_island_bot` | Bot strategies |
| `settler_island_protocol` | Message and id types shared by server and client generator |
| `settler_island_server` | WebSocket and HTTP server, lobbies, persistence, metrics |
| `settler_island_client_generator` | Generates `client/` |
| `client/` | Generated Godot client and its test project |
| `keycloak/` | Local realm import |
