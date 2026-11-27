# State analysis and roadmap

Where the server stands (review of 2026-11-22, code last changed 2024-03-18) and what it takes to be feature complete.

**Status 2026-11-22 (evening): every roadmap step below is done and on `main` and pushed.** The findings in the
next sections describe the code as it was at the start of the day; they are kept for the record. Open follow-ups:
`X-Forwarded-For` trust assumes exactly one proxy appending the address; NAS deployment and a Dockerfile come later.

## Summary
- It builds. A client can connect, register a name, create, list, join and leave lobbies, and list lobby users.
- No game can actually be played. `start-game` creates a `Game` with no players. Nothing ever dispatches an action into
  the state machine, and the state machine cannot dispatch one: states re-borrow the `RefCell` that holds them.
- About half the rules are partly there, a quarter are missing, and several partial ones are wrong (table below).
- Gates: `cargo fmt --check` fails (1 file). `clippy -D warnings` reports 112 findings, mostly trivial. There are 0 unit
  tests, and 2 doctests don't compile because ASCII-art blocks are fenced as Rust.
- Conclusion: keep the board and coordinate code (hex math checked: 19 tiles, 54 corners, 72 edges, correct).
  Redesign the rules core and the server's concurrency model before adding features; patching on top costs more.

## Rule coverage
| Mechanic | Status | Notes |
|---|---|---|
| Board, tiles, number chips | partial | Chip list contains a `1` and only one `11` (`base_board_generator.rs:121`); desert always in the centre |
| Ports | missing | Generation commented out; `SettlementLocation.seaport` always `None` |
| Initial placement | wrong | Order 0,1,2,3,3,0,1,2 instead of snake order; no resources for the 2nd settlement; road id read from the settlement field |
| Building | partial | Distance rule ok; roads can't extend roads; no piece limits; pays before validating, so a failed build loses the cards |
| Dice production | partial | Correct payout, but never returns to action selection; dice RNG seeded with `0`, so every game rolls the same sequence |
| Robber discard / move / steal | wrong | Discards `total - 7` instead of half; robber position never updated; no turn check; can rob yourself; stuck if victim has no cards |
| Player trade | partial | Trading state unreachable; complete/cancel panic on `RefCell` re-borrow |
| Bank and port trade (4:1, 3:1, 2:1) | missing | Returns an error |
| Development cards | missing/stub | Buy action id duplicates `"BuildSettlement"` (`action_data.rs:13`); playing a card only decrements the count |
| Longest road, largest army, VP, win | missing | Nothing counts points |

Cross-cutting bugs: `PlayerResources::remove_resources` uses `.any`, so it removes only the first resource type
(`player_resources.rs:53`); `Color::from` swaps green and blue.

## Server findings
- **Deadlock:** the lock order is inconsistent. `lobby start-game` holds the user's state and then locks the lobby.
  `lobby get-users` holds the lobby and then locks every member's state. Two members doing these at once hang both
  connections, and with them the global `GameServer` mutex.
- **Global mutex:** the whole `GameServer` sits behind one `Arc<Mutex<...>>`, held across awaits that include socket
  sends, so one slow client stalls everyone.
- **Leaks and panics on disconnect:** `unregister_user` unwraps `leave_lobby`, so a registered user who disconnects
  outside a lobby panics the task. Users are also never removed from the `users` map.
- **Missing lobby rules:** anyone in a lobby can start the game; game settings are hard-coded (`players: 2`); there is
  no capacity check on join; nothing is broadcast (other members never learn about joins, leaves or starts).
- **Protocol:** each message is parsed twice, commands are dispatched on `group`/`command` strings, errors are
  `String`s, and the client gets an error code only sometimes. The `NOT_REGISTERED` text reads "User is registered".
- **Smells:** `unsafe impl Send/Sync for UserConnection` isn't needed (every field is already Send + Sync).
  `#[allow(dead_code, unused)]` on both crates hides dead code. Bind address and port are hard-coded
  (`127.0.0.1:8253`), and passwords are stored in plain text.
- **Dependencies:** the game crate depends on tokio, tungstenite, syn and quote, none of which it uses. The libraries
  are from 2023 (tokio-tungstenite 0.20, rand 0.8, env_logger). The workspace has no `resolver = "2"` and is on
  edition 2021.

## Target architecture
- **Rules core** (`settler_island_game`, no I/O, no async):
  - `Game` is plain data: players, board, `phase: Phase` (an enum carrying per-phase data such as roads left or
    pending discards), bank, development deck, seeded RNG.
  - One entry point: `apply(&mut Game, PlayerId, Action) -> Result<Vec<Event>, GameError>`. It validates everything
    first, then mutates; `Action`, `Event` and `GameError` are typed enums.
  - `Resource` is an enum and hands are fixed-size count arrays, not `HashMap<String, usize>`.
  - `Game: Serialize` plus `PlayerView` (own hand visible, others as counts). Same seed plus the same action log
    gives the same game.
  - Delete `settler_island_util` and `settler_island_util_derive`; the `Phase` enum replaces string state ids.
- **Server** (`settler_island_server`):
  - Actors instead of shared mutexes. Each connection gets a reader task and an outbound `mpsc` writer. One lobby
    registry task, and one task per lobby or game that owns its `Game` and gets commands over a channel. No locks
    held across awaits.
  - A typed, versioned protocol: `#[serde(tag = "type")] enum ClientMessage` and `ServerMessage`, an error enum with
    stable codes, and every request answered.
  - Events are broadcast to lobby members, each player gets their own `PlayerView`, and a session token allows
    reconnecting.
  - Config from env (bind address, port), `tracing`, graceful shutdown.
  - Axum 0.8 as the host, following the default web stack (`~/.claude/shared-knowledge/default-web-stack.md`):
    a WebSocket upgrade at `/api/v1/ws`, a small REST part (lobby list, health, session tokens), Prometheus
    `/metrics`. This also keeps a later web export of the Godot client on the same API.
- **Persistence** (Postgres, sqlx with migrations and the committed `.sqlx` cache):
  - A game is stored as settings, seed and the ordered action log; a snapshot every N actions speeds up loading.
    On restart, running games are rebuilt by replaying from the last snapshot, and players reconnect with their
    session token.
  - Users, lobbies and finished games (results, for stats) live in tables. An action is written to the database
    before its events go out, so an acknowledged move is never lost.
- **Identity:** two kinds of user with the same `UserId` inside the server.
  - Guests get a signed session token from `POST /api/v1/sessions/guest` with a display name; the client keeps it to
    reconnect.
  - Keycloak users sign in with OIDC (PKCE, loopback redirect from the Godot client) and present the access token;
    the server checks it against the realm's keys (`axum-keycloak-auth`). A guest can later be upgraded to an account
    so that its games stay linked.
- **Game records and replay.** No Catan notation is as widely used as PGN is for chess (community formats: catanlog
  `.catan`, Settlers Game Notation, Catanatron's JSON), so the record is our own and an exporter can follow later.
  - A record is a header (format version, rules version, settings, seats, board layout) followed by entries in order.
    Each entry is `{ index, player, action, events }`, and random outcomes (dice, stolen card, drawn development
    card) are events in it.
  - The seed is stored only on the server. A record shared during a game would reveal the next rolls if it carried
    the seed, so replay reads the outcomes from the record and never regenerates them.
  - Stepping to entry N means loading the nearest snapshot and applying the entries up to N; going back is the same
    from an earlier snapshot. A replay test checks that replaying a record reproduces every event exactly.
  - Visibility: during a game a player gets the record filtered to their own view. After the game everyone gets the
    full record, which is also the bot training and benchmark data. Export is a JSON Lines file (`.sigame`).
- **Bots:** opponents that play through the same interface as humans, so they can't cheat.
  - The rules core gets `legal_actions(&Game, PlayerId) -> Vec<Action>`. Bots, client hints and tests all use it.
  - Crate `settler_island_bot` holds `trait Bot { fn choose(&mut self, view: &PlayerView, legal: &[Action]) -> Action }`
    and also answers trade offers and discard demands.
  - Strategies, in order:
    - Random: picks any legal action. It's the baseline and a fuzzer.
    - Heuristic: places by pip count and resource mix, follows build priorities, trades with bank and ports, moves the
      robber onto the leader.
    - Search (later): Monte Carlo over the seeded rules core. Hidden cards are sampled, never read.
  - Server: the lobby owner fills seats with bots and picks their difficulty. A bot runs inside the game task with a
    short think delay, and its seats are stored with the game, so bots survive a restart too.
- **Client:** Godot for now, a web export later. The protocol doc (`doc/protocol.md`) is owned here, and the Godot
  repo generates or copies its message types from it.

## Roadmap
Each step is one or more agent-sized changes (see `AGENTS.md` "Agent workflow"). Steps 2a-2d can run in parallel
once step 1 has landed; 2e needs all of them.

| Step | Content | Model | Acceptance |
|---|---|---|---|
| 0 Baseline (done 2026-11-22) | fmt, clippy to 0 warnings, fix the doctest fences, drop `unsafe impl` and the blanket `allow`s, `resolver = "2"`, trim game deps | Sonnet | `tools/check.sh` green |
| 1 Rules core (done) | `Game`/`Phase`/`Action`/`apply` redesign (plan in `doc/plans/` first); `legal_actions`; port setup, roll, build, robber with fixes; seeded RNG; tests for each | Opus | A scripted 4-player game from setup through 10 turns runs headless, deterministic per seed; every action from `legal_actions` is accepted by `apply` |
| 1b Random bot (done) | `settler_island_bot` crate, `Bot` trait, random strategy; a property test plays 4 random bots over many seeds | Sonnet | No seed gets stuck or panics; card totals stay constant. Grows into a full-game test as step 2 lands |
| 2a Trade (done) | bank 4:1, ports 3:1 and 2:1 (port generation), player offers, accept and cancel | Sonnet | Rate tests per port type; a trade never creates or destroys cards |
| 2b Dev cards (done) | deck, buy, play knight / road building / year of plenty / monopoly / VP; one per turn, not on the turn bought | Sonnet | One test per card plus the timing rules |
| 2c Scoring (done) | VP count, longest road (graph search, broken by opponent settlements), largest army, win at 10 | Opus | Longest-road edge cases: branches, cycles, ties, a break |
| 2d Robber (done) | half discard, move, victim choice, steal | Sonnet | Tests for 7 with 7 and 8+ cards, no adjacent victim, empty victim |
| 2e Heuristic bot (done: 200/200 wins vs random, median 59 turns) | placement scoring, build priorities, trades, robber choice, trade answers | Opus | Over 200 seeded games it beats 3 random bots in at least 90 %; median game length is reported |
| 3a Server core (done) | Axum host, actor model, typed protocol and `doc/protocol.md`, lobby rules (owner starts, capacity, broadcast, bot seats), game messages | Opus | Integration test: 1 WebSocket client plays a seeded game against 3 bots to a win |
| 3d Godot client (done) | `settler_island_protocol` types derive `JsonSchema`; `cargo run --bin generate_client` writes `client/godot/` (GDScript classes with `from_dict`/`to_dict`, a typed WebSocket client with one send function per request and one signal per server message) and `client/schema.json`; the gate fails when the output is stale | Sonnet | A headless Godot script connects, registers as a guest, plays a few actions against bots |
| 3b Identity (done) | guest session tokens, Keycloak token check, guest upgrade, local realm in `keycloak/realm-local.json` | Sonnet | Tests: expired/forged token rejected; guest and Keycloak user in one game |
| 3c Persistence (done) | docker-compose Postgres, migrations, action log + snapshots, replay on start, reconnect | Opus | Kill the server mid-game, restart, all 4 clients reconnect and finish the same game |
| 4 Ops (done) | env config, tracing, `/metrics`, CI workflow | Sonnet | CI runs the gate on every push |
| 5 Playable client (done 2026-11-27) | Godot client milestones 1 and 2: lobby, mouse-only play, designed HUD (doc/design/), EventPlayer feedback, toasts, turn cue, settings, CC0 sounds, ambience and music | Sonnet | Mouse-only full game vs 3 bots without script errors; HUD fits 1600x900 and 1280x720; verifier pass |
| 6 3D table (next) | Board3D, 3D cards, dice, piece placement animations, per `doc/plans/godot-3d.md` | Opus plan, Sonnet parts | Design group and plan first |
| later | Dockerfile and NAS deployment, once the Godot client can play | Sonnet | Out of scope for now |

Client leftovers after step 5: nobody has listened to the sounds yet (hook-to-file mapping is a first pass, Kenney Casino/Impact/RPG
packs were blocked for scripted download, see `client/godot/audio/SOURCES.md`); the "Your turn" banner briefly covers the top-bar hint;
`tools/game_screenshots.gd` sometimes prints a `_drop_mouse_over` error when it frees a screen (not in the gate).

## Decisions (2026-11-22)
- **Client:** Godot now, maybe a web export later. JSON over WebSocket stays, and this repo owns the protocol.
- **Persistence:** games survive a restart (Postgres, see Target architecture).
- **Identity:** both guests and Keycloak accounts.
- **Deploy:** Docker on the NAS, but only in the far future; the Godot client isn't ready either. Until then
  everything runs locally (docker-compose Postgres and Keycloak), and nothing here claims NAS resources. When it
  comes, read the shared infrastructure notes first (ports, pi firewall and proxy, backups, monitoring).
