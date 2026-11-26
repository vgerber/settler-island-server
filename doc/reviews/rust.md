# Rust crates review

Date: 2026-11-26. Built from 8 slice reviews (rules-a, rules-b, game-core, bot, protocol-generator, server-actors,
server-data, server-tests). The lead checked every high and medium finding against the code, merged duplicates across
slices and added findings that only show up across slices (marked *cross-slice*).

## Summary

The architecture is sound. Rules are pure, validation is separated from mutation and drives `legal_actions`, the server
is actor-based with one owner per piece of state, and a stale generated client fails the build. Most problems come from
three causes that the slices each saw part of:

1. **The game crate keeps its rule data private**, so the bot and the protocol copy it: build costs, port rates, the
   discard and army thresholds, the seat and points bounds, the distance rule and the resource index. Nothing ties the
   copies together, and the bot hides drift by falling back to `legal.first()`.
2. **"Apply cannot fail" holds only by convention.** Apply-side helpers swallow failures (`pay_to_bank`,
   `exchange_with_bank`, `swap_hands`), mutate before a fallible lookup (`play_monopoly`, `play_year_of_plenty`, `buy`),
   or index `players[..]` directly. Several state pairs (`Phase::TradeOffered` + `Game.trade`, `dice_rolled` + phase,
   setup `round: u8`) are kept in sync by hand.
3. **Server integration tests copy their scaffolding.** The scripted play loop exists three times and has already
   drifted; lobby creation, GameStarted waits and join error handling are written out in each test.

One real runtime bug stands out: a failed JWKS fetch makes valid Keycloak tokens fail as `InvalidToken` for 60 s.

## Findings

Ranked by value. Severity: high, medium, low.

### 1. A failed JWKS fetch rejects valid account tokens as InvalidToken for 60 s (high)
- Location: `settler_island_server/src/identity/keycloak.rs:62-102`, `settler_island_server/src/identity/mod.rs:95-99`
- Why: `claim_refresh` stamps `last_fetch` before the fetch runs. If the fetch fails (Keycloak down at start-up, a
  timeout) or is still running when another request arrives, every other token gets `Ok(None)` from `key()`, which
  becomes `Invalid("unknown kid ...")` and `ErrorCode::InvalidToken`. A client that drops its token on InvalidToken
  logs real users out because of a server-side outage.
- Fix: stamp `last_fetch` only after a successful fetch (or track a failed state). When the cache is empty or the window
  was spent on a failed fetch, return `KeysUnavailable` (mapped to Internal) instead of `Ok(None)`. Serialise
  concurrent refreshes (a `tokio::sync::Mutex` around the fetch) so waiters see the new keys. Test in
  `tests/identity.rs`: the realm answers 500 once, then serves keys. Do this together with finding 17 (typed
  `AccountTokenError`), which needs to tell "unknown kid" apart.

### 2. Apply-side mutators can fail silently or half-apply; player access is done three ways (high, cross-slice)
- Location: `settler_island_game/src/game.rs:266-280` (`pay_to_bank`); `settler_island_game/src/rules/trade.rs:81-95`
  (`exchange_with_bank`), `trade.rs:203-214` (`swap_hands`); `settler_island_game/src/rules/development.rs:14-18`
  (`buy` pays before `player_mut`), `development.rs:45-55` (year of plenty spends the card, then `bank.try_remove?`),
  `development.rs:62-81` (monopoly empties other hands before `player_mut?`, unchecked `u8 +=`),
  `development.rs:159-163` (private `player_mut`); `settler_island_game/src/rules/robber.rs:44,73,98,112-113,132,182`
  (direct `players[usize::from(seat)]`); `settler_island_game/src/rules/building.rs:52-55,89-91,98-100`
  (`if let Some(player) = get_mut` that silently skips)
- Why: AGENTS.md says validation may reject and applying a validated action cannot fail, and that a client-caused error
  never panics. Today every path is guarded by an earlier check, but nothing ties check and apply together.
  `pay_to_bank` still emits `ResourcesPaid` (and it is persisted) when nothing was paid; `swap_hands` can take one leg
  and skip the other, creating or destroying cards. Reported by rules-a, rules-b and game-core.
- Fix: (a) move `player_mut` to `Game::player_mut(seat) -> Result<&mut PlayerState, GameError>` beside `Game::player`
  and use the pair everywhere; remove direct indexing and silent `if let` skips. (b) Do every fallible lookup before
  the first mutation. (c) Add one all-or-nothing transfer on `Game` (for example `move_resources(from: Holder,
  to: Holder, amount)` with `Holder::{Bank, Seat}`) that checks both sides first, and use it for paying, bank trades,
  trade swaps, year of plenty, monopoly and discards. Where it still cannot fail, a `debug_assert!` on the failure
  branch makes a broken precondition visible in tests and the random-play proptest.

### 3. Rule data is private in the game crate, so the bot and the protocol copy it (high, cross-slice)
- Location:
  - Costs: `settler_island_bot/src/heuristic/hand.rs:30-38` copies `settler_island_game/src/rules/building.rs:10-14`
    (`pub(crate)`) and `development.rs:11` (`CARD_COST`, private).
  - Port rates: `hand.rs:5-7,87-108` (`trade_rates`, own `BANK_RATE`/`GENERIC_PORT_RATE`/`SPECIFIC_PORT_RATE`) copies
    `settler_island_game/src/rules/trade.rs:9-43`, although `OwnView::bank_rates` (`view.rs:50,86`) already carries the
    result.
  - Thresholds: `hand.rs:9` `SAFE_HAND = 7` (robber discard limit), `settler_island_bot/src/heuristic.rs:15`
    `LARGEST_ARMY_MIN` (scoring), the city factor 2 written twice in `evaluation.rs:71-75,239-243` (production).
  - Distance rule: `settler_island_bot/src/heuristic/evaluation.rs:113-123` `is_free_site` copies
    `building.rs` `check_settlement_site`.
  - Resource index: `evaluation.rs:22-27` `slot()` (linear search, silent `unwrap_or(0)` = Clay) copies the private
    `Resource::index` (`resource.rs:26-34`); bot `[u32; 5]`/`[u8; 5]` arrays rely on the order by doc comment.
  - Lobby bounds: `settler_island_protocol/src/lib.rs:14-16` and private `settler_island_game/src/game.rs:19-22`
    (`MIN_SEATS`, `MAX_SEATS`, `MIN_POINTS_TO_WIN`), validated twice (connection.rs and `Game::new`).
- Why: a rule change in the engine silently diverges from the bot (which then plans trades or builds the game rejects;
  see finding 9 for why nobody notices) or from the server's lobby validation. Reported separately by rules-b, bot and
  protocol-generator; the common cause is that the game crate exposes no rule data.
- Fix: the game crate owns and exports the data: `pub const` costs (or `BuildKind::cost()`), `pub` thresholds,
  `pub fn Resource::index`, `BuildingKind::production_factor()`, and a read-only `Board::is_settlement_site(corner)`
  that `check_settlement_site` maps to Occupied/TooClose. The bot reads `own.bank_rates` and deletes `trade_rates`,
  its rate constants, `slot` and `is_free_site`; rates become a `ResourceCounts`. The protocol re-exports the seat and
  points bounds the same way it re-exports `Seat` and `Action`.

### 4. Server integration tests copy their scaffolding, and the copies have drifted (high)
- Location: play loop `settler_island_server/tests/game.rs:98-138`, `game.rs:205-251`, `tests/persistence.rs:280-327`
  (persistence ignores `LobbyState` at :322, game.rs panics on it); hand-written `ClientMessage::CreateLobby` literals
  in `game.rs` (2), `lobby.rs` (4), `persistence.rs` (1) because `common::Client::create_lobby` hard-codes
  `points_to_win`/`bot_difficulty` to `None` (`tests/common/mod.rs:227-241`); GameStarted wait loops about ten times
  while `persistence.rs:265-276` has `next_game_started`; `join` returns a raw `ServerMessage`
  (`common/mod.rs:243-251`), so callers match by hand or ignore failures (`lobby.rs:141,158,179`); guest-session
  request built three times (`common/mod.rs:86-101`, `rate_limit.rs:8-19`, `identity.rs`).
- Why: a protocol change has to be fixed in many places and only some tests notice; an ignored failed join lets a test
  continue on the wrong setup.
- Fix: in `tests/common/mod.rs`: one `play_as(...)` loop with a stop predicate and one rule for tolerated messages; a
  lobby-settings struct with `Default` for `create_lobby`; `start_with_bots(...)` that waits for GameStarted; move
  `next_game_started` there and add `next_game_update`; `join -> Result<LobbyDetails, ErrorCode>`; `post_guest(...)`
  returning the raw response with `guest_session` built on it.

### 5. The open trade is stored twice, and the addressing rule is written twice (high, cross-slice)
- Location: `settler_island_game/src/phase.rs:38` (`TradeOffered` with no data), `settler_island_game/src/game.rs:89`
  (`trade: Option<TradeOffer>`), `game.rs:240-251` (`trade_pending_seats` with a fallback for the impossible
  `trade == None`), `settler_island_game/src/view.rs:23-24,101`, `settler_island_game/src/rules/trade.rs:139-158,
  246-259`
- Why: every trade transition has to set phase and `game.trade` together; `legal_answers` checks only `game.trade`.
  "Addressed, not the offerer, not yet answered" is coded in both `trade_pending_seats` and `answer_trade`.
  `answers: Vec<(Seat, bool)>` allows duplicates, and clients receive both fields and could see them disagree.
- Fix: `Phase::TradeOffered { offer: TradeOffer }`; delete `Game.trade` and `PlayerView.trade`; `Game::trade()` matches
  on the phase. Add `TradeOffer::awaits_answer_from(seat)` used by both places, and rename `seat` to `offerer`, `to` to
  `addressed`. Protocol change: regenerate `client/` in the same commit.

### 6. "Current seat in Main" check written four times (medium)
- Location: `settler_island_game/src/rules/building.rs:129-135`, `rules/trade.rs:45-51` (identical private
  `check_main_turn`), `rules/development.rs:166-169` (inline in `check_buy`), `rules/turn.rs:35-38` (inline)
- Fix: `Game::require_main_turn(seat)` next to `require_turn`; delete the two copies. (rules-a, rules-b)

### 7. Road placement check duplicated for paid and free roads (medium)
- Location: `settler_island_game/src/rules/building.rs:137-151` (`check_road`), `rules/development.rs:262-274`
  (`check_free_road_site`)
- Why: site, connection (`NotConnected`) and supply (`NoPiecesLeft`) are copied; only turn and cost differ.
- Fix: `pub(crate) building::check_road_placement(game, seat, edge)`; `check_road` adds main-turn and cost,
  `check_free_road` adds the RoadBuilding phase check. (rules-a, rules-b)

### 8. Phase and turn invariants held by convention (medium, cross-slice)
- Location: setup round `settler_island_game/src/phase.rs:10-16` (`round: u8`, "1 or 2") and
  `rules/setup.rs:17,37-41` (any value other than 1 acts as round 2); `dice_rolled` flag `game.rs:283-289`,
  `rules/turn.rs:17,41`; turn start split across `rules/setup.rs:43-47` (sets `turn_number`, pushes `TurnStarted` by
  hand, no `TurnEnded`), `rules/turn.rs:41-44` and `game.rs:291-300` (`pass_to`); discard owed entries
  `Vec<(Seat, u8)>` with a dead `count > 0` filter (`game.rs` pending seats, `rules/robber.rs:65-69,78-79,129`).
- Why: states the rules never produce (round 3, Main with `dice_rolled == false`, duplicate discard seats) are
  representable, and each new turn-start path must remember three fields.
- Fix: `enum SetupRound { First, Second }`; one `Game::start_turn(seat) -> Vec<Event>` used by setup and `end_turn`;
  optionally let interrupt phases carry where they resume instead of `dice_rolled`; a named discard entry and one
  `owed_discard(seat)` lookup, dropping the dead filter. Protocol change for the round enum: regenerate `client/`.

### 9. The heuristic bot hides illegal decisions; OfferTrade bypasses the legal list (medium)
- Location: `settler_island_bot/src/heuristic.rs:115-125`, `settler_island_bot/src/lib.rs:4-6`,
  `settler_island_server/src/lobby.rs:660-668`
- Why: an action not in `legal` is silently replaced by `legal.first()`, so a decision regression (or a copied rule
  from finding 3 drifting) shows up as weak play, not a test failure. `OfferTrade` passes unchecked because
  `legal_actions` does not list it; if the game rejects it, the lobby marks the bots stalled.
- Fix: `debug_assert!` on the fallback so tests and `heuristic_games` fail; document the OfferTrade exception on the
  `Bot` trait, and have the lobby fall back to `EndTurn` when a bot offer is rejected. A public read-only
  `Game::check(seat, &Action)` (the existing plan step) would let bots validate offers themselves.

### 10. Record and store types duplicate each other (medium, cross-slice)
- Location: `settler_island_server/src/store.rs:33-39` (`StoredAction`) vs `settler_island_game/src/record.rs:36-41`
  (`RecordEntry`, same fields); `settler_island_server/src/lobby.rs:849-877` (index computed, then recomputed by
  `GameRecord::push`; action and events cloned twice); `RecordSettings` built by hand in `record.rs:50-53` and
  `settler_island_server/src/postgres.rs:201-204`, reversed field by field at `postgres.rs:117-122`; replay written as
  `record::replay` (`record.rs`) and `StoredGame::rebuild` (`store.rs:72-97`); `GameRecord::new(&Game)` trusts the
  game is fresh, so `rebuild` builds a throwaway `Game`.
- Why: a new `GameSettings` field silently goes missing from records and the DB; two index sources can disagree.
- Fix: store `RecordEntry` (drop `StoredAction`), build it once and push it (`GameRecord::push_entry`);
  `GameSettings::without_seed()` and `RecordSettings::with_seed(seed)` with exhaustive destructuring; one replay
  function in the game crate that reports divergence, used by `rebuild` and the tests.

### 11. Snapshot cadence rule in four places (medium)
- Location: `settler_island_server/src/lobby.rs:851-854`, `settler_island_server/src/store.rs:363-365` (test),
  `settler_island_server/tests/persistence.rs:56-62`, comment in the create-tables migration (`50`)
- Fix: `store::wants_snapshot(index) -> bool` next to `SNAPSHOT_INTERVAL`, used by the lobby and both tests; drop the
  number from the migration comment (do not edit the applied migration file; leave it, or note it as stale).

### 12. Lobby seat counts and indices are unchecked conventions (medium)
- Location: `settler_island_server/src/lobby.rs:176-177` (`seats[0] = ...`), `lobby.rs:576,676,701,747`
  (`seat as Seat`), `lobby.rs:511,829` (`len() as u8`), validation only at `connection.rs:297`
- Why: any other `LobbySetup` builder (test, future HTTP route) with 0 seats panics the lobby task; seat helpers
  return `usize` and are cast back to `Seat` in four places.
- Fix: a validated `SeatCount` (or validated lobby options) required by `LobbySetup`; seat helpers return `Seat` and
  index with `usize::from(seat)`.

### 13. Postgres id conversions: `as` on write, `try_from` on read (medium)
- Location: `settler_island_server/src/postgres.rs:209` (`lobby.0 as i32`), `postgres.rs:219` (`seat as i16`),
  `postgres.rs:113,280-282` (read with `try_from`), GameId conversions `postgres.rs:95,222-224,366-368`
  (`corrupt(GameId(0), ..)`), `settler_island_server/src/store.rs:14` (`GameId(pub u64)`)
- Why: a value the write accepts can be refused on read, and the `?` inside `load_running` then fails the restore of
  every game. Errors name a non-existent `GameId(0)`.
- Fix: `try_from` on write with a typed error (or a BIGINT column via a new migration); one checked GameId
  constructor with a private field; report the raw row id; consider skipping and logging one corrupt game in
  `load_running`.

### 14. Error texts hardcode the limits their constants define (medium)
- Location: `settler_island_protocol/src/lib.rs:282,289-293` vs `lib.rs:9-18`; comment on `MAX_FRAME_BYTES` in
  `settler_island_server/src/lib.rs:88`
- Fix: build the texts with `format!` from the constants (`description` already returns `String`). (protocol-generator,
  server-actors)

### 15. Metrics gauges updated by hand on scattered paths (medium)
- Location: `running_games` at `settler_island_server/src/lobby.rs:265,551,628,870`; `lobbies` at
  `settler_island_server/src/registry.rs:219-220,300-301,333-334`
- Fix: tie `running_games` to the running game's life (one place that marks finished/abandoned and decrements once);
  `list_lobby`/`unlist_lobby` helpers on the registry that update the map and gauge together.

### 16. Two rate limiters with different algorithms (medium)
- Location: `settler_island_server/src/connection.rs:32-57,425-433` (fixed window, allows 2x at a window edge),
  `settler_island_server/src/rate_limit.rs:15-62` (token bucket per IP)
- Fix: extract a single-key `TokenBucket` from `rate_limit.rs`; `IpLimiter` holds a map of them, the connection holds
  one; move the test.

### 17. String-typed errors against AGENTS.md (medium)
- Location: `settler_island_server/src/identity/keycloak.rs:25-30,65,69,142` (`Invalid(String)`);
  `settler_island_client_generator/src/main.rs:15-50` (`Result<_, String>`, `Ok(bool)` result)
- Fix: `MissingKeyId`, `UnknownKeyId(String)`, `Rejected(#[from] jsonwebtoken::errors::Error)`; for the CLI a
  thiserror `ArgumentError` and `enum Outcome { Written, Current, Stale(..) }`.

### 18. Board offers only raw getters, so geometry queries are rebuilt everywhere (medium, cross-slice)
- Location: "buildings of a seat" scans in `settler_island_game/src/rules/trade.rs:23-34`,
  `settler_island_bot/src/heuristic/evaluation.rs:64-79,125-136`, `heuristic/hand.rs:59-63,86-95`; "corner touches a
  road of seat" in `rules/building.rs:169,179` and `evaluation.rs:135,146`; other edge end at `rules/scoring.rs:129`;
  the port stored on both corner and edge (`settler_island_game/src/board.rs:52,58-60`, kept equal by
  `generator.rs` test only).
- Fix: public read-only `Board::buildings_of(seat)`, `touches_road(corner, seat)`, `Edge::other_end(corner)`, and one
  port source (edge) with `Board::port_at(corner)`; rules and bot both call them.

### 19. Config: DATABASE_URL parsed late; the .env.example test compares five fields (medium)
- Location: `settler_island_server/src/config.rs:65-73,186`, `settler_island_server/src/main.rs:57-59`;
  test `config.rs:322-342`
- Why: an invalid URL is found after the port is bound; the public `String` bypasses the redacting Debug. The example
  test misses `trade_answer_time`, log settings, `trust_forwarded_for` and `database_url`.
- Fix: parse into `PgConnectOptions` in `from_vars`; compare the whole `Config` with struct update for the secret, and
  set `SETTLER_TRADE_ANSWER_SECONDS` in the every-variable test.

### 20. Generator: unreadable schema shapes become `Any`; GDScript types are strings (medium)
- Location: `settler_island_client_generator/src/model.rs:465-486,516`; `gdscript.rs:338,425-476,637`; literal
  `"request_id"` check in the generated send body (`gdscript.rs:701-703`) next to the `REQUEST_ID` constant (`:12`)
- Why: a new protocol shape (map, multi-part allOf) still passes `--check` and hands clients raw dictionaries; type
  decisions branch on `starts_with("Array")`.
- Fix: return `ModelError::Unsupported` for those shapes (keep `Any` only for untyped schemas); a small `GdType` enum
  with `default_value()`/`is_typed_array()`, from which `element_type` derives; have the generator require
  `REQUEST_ID` on every root variant and emit it via the constant.

### 21. Bank-trade legality written twice (medium)
- Location: `settler_island_game/src/rules/trade.rs:228-244` (`legal_main`) vs `trade.rs:53-71`
- Why: unlike development.rs, legal actions do not come from the check function, so "listed implies accepted" relies
  on keeping two copies in sync.
- Fix: `check_bank_trade(..) -> Result<(give, receive), GameError>`; `bank_trade` applies its result and `legal_main`
  filters by it. Compute `bank_rates` once per call instead of five corner scans.

### 22. Lobby info structs duplicated across protocol and server (medium)
- Location: `settler_island_protocol/src/lib.rs:208-232` (`LobbySummary`, `LobbyDetails`, seven shared fields),
  `settler_island_server/src/lobby.rs:806-835`
- Fix: nested `LobbyInfo` built once in the lobby; regenerate `client/`. Fold `DEFAULT_BOT_DIFFICULTY` into the same
  change (`protocol lib.rs:103-105` documents it in prose, `connection.rs:316` hard-codes `Difficulty::Heuristic`).

### 23. Timing tests sleep instead of synchronising; Postgres test databases leak (medium)
- Location: `settler_island_server/tests/abandon.rs:99,120,130,162,170`, `tests/connection.rs:243,264`;
  `tests/common/mod.rs:71-84`, `tests/persistence.rs:140` (name already wrong)
- Fix: a `common::eventually(deadline, condition)` poller (the pattern exists in `metrics.rs` wait_for); keep sleeps
  only for "does not happen" checks with a one-line reason. Drop the name parameter; return a guard that drops the
  database (`WITH (FORCE)`), or drop leftovers with a common prefix at start.

### 24. "Is the game finished / who won" matched in six places (low, cross-slice)
- Location: `settler_island_game/src/game.rs:138`, `rules/scoring.rs:49`, `settler_island_server/src/lobby.rs:675,
  759,868`, `settler_island_bot/src/harness.rs:69`, `settler_island_bot/src/heuristic.rs:53`
- Fix: `Game::winner() -> Option<Seat>` (and `is_finished`).

### 25. Shared test data and seeds are spelled out everywhere (low, cross-slice)
- Location: 28 `GameSettings { .. }` literals across crates; bot seed formula `seed.wrapping_mul(31) + seat` in
  `settler_island_bot/tests/random_games.rs:12` and `tests/heuristic_games.rs:26` differs from the server's
  `bot_seed` (`settler_island_server/src/lobby.rs:891-893`), so tests do not exercise server seeds; card-total helpers
  under three names and the literal 95 (`game.rs`, `rules/robber.rs:209-211`, `rules/trade.rs:298-305`,
  `rules/development.rs:285-287`, `rules/setup.rs:176`); own-building searches three times in `building.rs` tests;
  `scoring` `put_city` beside `test_support::put_settlement`.
- Fix: `GameSettings::standard(seats, seed)`; export `bot_seed` from `settler_island_bot` and use it in the lobby and
  both tests; `test_support::{card_total, TOTAL_CARDS, own_buildings, put_building}`.

### 26. Small server structure cleanups (low)
- `STORE_RETRY` carries the doc of `bot_difficulty` (`settler_island_server/src/lobby.rs:20-21`): rewrite as "Wait
  before retrying a store write that failed."
- `impl<S: GameStore> GameStore for Arc<S>` in `store.rs` removes the 34-line `SharedStore` forwarder
  (`tests/abandon.rs:18-51`).
- `welcome_member` / `send_full_state` for the join paths (`lobby.rs:373-402,459-462`); `notify_registry` for every
  LobbyNotice send (`lobby.rs:308,552,729,765-775`); a `LobbyContext` for the four shared handles
  (`lobby.rs:162-214`, `registry.rs:136-139,272-328`).
- `GameRecord::visible_to(viewer)` in the game crate instead of redaction in `lobby.rs:672-691`.
- `ErrorCode::tag() -> &'static str` instead of serialising to JSON for the metric label
  (`settler_island_server/src/metrics.rs:66-70`); `ServerMessage::request_id()` in the protocol instead of test-only
  `echoed_request_id` (`tests/common/mod.rs:108-119`).
- Humans of a stored game filtered twice (`lobby.rs:230-233`, `registry.rs:291-295`): `NewGame::humans()`.
- Guest token `kind` claim is trusted though `issue` fixes it (`identity/guest.rs:17-23,50,78-82`): set
  `UserKind::Guest` in `verify`.

### 27. Small game and bot cleanups (low)
- `ResourceCounts::add(resource, amount)` and `saturating_sub`, make `deposit` public: replaces get/set arithmetic in
  `rules/production.rs:36,58,81`, `rules/development.rs:81` and the bot (`heuristic.rs:179-181,327-332`,
  `hand.rs:41-54`).
- Rename `Phase::RoadBuilding { roads_left }` to `free_roads_left` (clashes with `PlayerState.roads_left`; protocol
  change, regenerate `client/`).
- `GameError::NotYourTurn` doubles as "unknown seat" (`game.rs:253-257`) and "owes no discard" (`robber.rs:66-69`):
  add `UnknownSeat` and reuse `InvalidDiscard`.
- Drop unused `_seat` from `robber::on_seven`; rename `scoring::blocks` and `data`.
- Domain types in `game.rs` (`DevelopmentCard`/deck, `TradeOffer`, `PlayerState`) belong in their rule modules,
  per the "game.rs only dispatches" rule.
- `building::place_*` (unchecked, takes from supply) vs `setup::place_*` (validated) vs `test_support::put_*`
  (no supply): rename the building helpers to make the difference visible.
- Bot: `GameOutcome.actions` duplicates `record.entries.len()` (`harness.rs:8-11,134`); `main_action` evaluates all
  eight strategies eagerly and recomputes `seat_production` per legal action (`heuristic.rs:61-82`): use a lazy
  chain and compute production once.
- Hot-path recomputation: `legal_builds` repeats turn/cost/supply checks per corner and edge (`building.rs:61-78`);
  longest road runs a DFS from every corner after every action (`scoring.rs:48-62,111-117`). Worth doing when
  benchmarks show it.

### 28. Tests worth adding or fixing (low)
- Robber victim dedup (two buildings of one seat on the robbed tile give one Steal) and desert yield in setup
  (`rules/robber.rs:172-187`, `rules/production.rs:27-40`).
- Bot: focused tests for `reachable_sites` (blocked by opponent building, distance decay), year of plenty, card
  purchase; bound the open-ended loop in `heuristic.rs:527-551` or build the two views directly.
- `generator.rs:215-233` re-implements the red-number check it tests; check adjacency through shared corners instead.
- Generator: a unit test that two definitions mapping to one file name give `RenderError::DuplicateFile`;
  `read_fields` dedups only adjacent names (`model.rs:376-399`): use a seen-set.
- `tests/persistence.rs:21` `ACTIONS_BEFORE_CRASH` counts updates, not actions: stop on record length so "past the
  first snapshot" is really checked; take replay settings from `record.header.settings_without_seed`
  (`tests/game.rs:48-53`, `tests/persistence.rs:408-418`).

### 29. Persistence details (low)
- `users.kind` has no CHECK constraint, unlike `games.status`; add one in a new migration and a round-trip test of
  `kind_name`/`parse_kind` (`postgres.rs:288-321,374-387`).
- `link()` repeats the `linked_user` SQL (`postgres.rs:337-362`): call `self.linked_user`.
- `rebuild` reuses the name `stored` for a count and for each action, and `Snapshot.actions` is a count while
  `StoredGame.actions` is a Vec (`store.rs:41-46,80-94`): rename to `action_count`; check `index == position` while
  replaying.

## Dropped

- **Board cloned into every view (game-core, medium):** real cost, but small at 3-4 seats, and splitting Board into
  layout and pieces is a protocol redesign best done with the planned 3D client, not as a cleanup. Noted for that work.
- **`distribute` takes a seat-indexed slice (rules-a, low):** the slice is always built from `players`; a pair list
  adds noise for no practical safety.
- **u128 used-edge bitmask (rules-b, low):** the board is fixed at 72 edges with no variant planned, and an overflow
  panics in debug test runs.
- **`bank_rate` `.min(BANK_RATE)` and per-resource rescan (rules-b, low):** folded into finding 21.
- **Monopoly arithmetic (rules-b, low):** folded into finding 2.
- **Generated-class substring test is redundant (protocol-generator, low):** harmless; the replacement test it
  suggests is kept in finding 28.
- **`union_files` placeholder vectors, class header built five times, `writeln!` comment noise, wide generator public
  API (protocol-generator, low):** cosmetic in a code generator with one consumer; not worth the churn now.
- **Default duration conversions repeated in config (server-data, low):** two lines; not worth a helper.
- **Restoring games runs three queries per game (server-data, low):** restart-only and few games.
- **Server start-up glue duplicated with godot.rs (server-tests, low):** the Godot harness lives in another crate and
  needs `serve`; one line explaining the different config suffices.
- **"Gap in action index breaks rebuild" as medium (server-data):** inserts are guarded by the next-index check and
  loads are ordered, so it is downgraded to the low rename/check in finding 29.
- **Discard tuple lookup written twice (rules-a, game-core):** merged into finding 8.

## Good, keep

- Validation is read-only and separate from mutation; `check_*` functions also drive `legal_*`, and failure tests
  assert the game is unchanged after an `Err` (`errors_leave_the_game_unchanged` probes about 400 rejected actions).
- Determinism is tested from three sides (same-seed board, scripted game, JSON snapshot that continues identically),
  plus a card-conservation proptest and a proptest of longest road against an independent brute force.
- `Event::visible_to` is the single point that hides secret information.
- The protocol re-exports the game vocabulary, and `--check` plus the committed-client test make a stale generated
  client a build failure; `DuplicateFile` and `check_references` catch collisions at generation time.
- Actor design: one task per lobby and one registry task, oneshot replies, non-blocking notices, an outbox that never
  awaits and disconnects a slow client.
- `apply_and_store` applies on a clone, writes to the store, then commits; `StoredGame::rebuild` verifies replayed
  events against the stored ones.
- Secrets are newtypes with redacting Debug; `Config::from_vars` takes a lookup closure for hermetic tests; all SQL
  goes through checked `query!` macros with offline data.
- Integration tests run real WebSockets against the real router on ephemeral ports, with injected stores
  (`RejectingStore` proves store-before-broadcast) and a restart test that drops a whole runtime mid-flight.
