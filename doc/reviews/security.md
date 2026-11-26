# Security, load and resilience review

Date: 2026-11-26. Scope: `settler_island_server` (HTTP routes, WebSocket protocol, lobbies, identity, Postgres store) at commit `6aaa4ac`. Method: attacker agents went after the API and the service in slices: auth, fuzzing, HTTP, lobby logic, game integrity, connection load, leaks, Postgres and dependencies. Two leads (security, then load and resilience) reproduced the results on their own release builds and ranked them. The principal reviewer checked the doubtful claims against the code. Every server that was started was a private instance on 127.0.0.1 with its own port, stopped by PID.

The attack scripts live in the session scratchpad, written below as `$S` = `<session scratchpad>/attack`. That directory is temporary. Each fix therefore has to bring its own regression test so the scripts are not needed later.

## 1. Executive summary

Overall risk is **moderate for the planned deployment, low today**. Nothing reached critical or high. We found no way to forge an identity with a properly generated secret, no way to act for another seat, no way to read another player's hand, and no way to crash the server from a client. The rules engine and the authority model held up under fuzzing and logic attacks. The weak spot is resource exhaustion. One anonymous host can push the process into gigabytes of memory in seconds:
- unauthenticated sockets that each pin a 1 MiB frame buffer
- concurrent Argon2 verifications at about 20 MB each
- clients that never read and pin about 6 MB of queued replies each
- abandoned bot games kept for 7 days with no cap

On a home NAS that shares RAM with Postgres, ClickHouse and other services, that is a realistic outage and could also hurt the neighbours. All of it can be fixed with small, local changes: caps, deadlines, byte budgets and a semaphore. The reverse proxy can absorb part of it (TLS, header timeouts, connection limits, blocking `/metrics`). Two configuration traps need fixing before deployment:
- `.env.example` ships a session secret that passes validation. A server started from it lets anyone forge any guest id.
- `SETTLER_TRUST_FORWARDED_FOR` must only be on when the game port is reachable from the proxy alone.

Throughput is not a concern. One instance applies 12-15k game actions per second on about one core. At real play speed that is thousands of concurrent games, so memory per connection and per game, plus the 8-connection Postgres pool, are the limits that matter.

## 2. Findings

Severity: **medium** = an anonymous or guest attacker can degrade or take down the service, or a likely misconfiguration breaks auth. **low** = limited impact, needs operator error, or hardening. Status: *reproduced* = re-run by a lead on its own server; *code-confirmed* = verified by reading the code, attacker evidence not re-run.

### M1. Unauthenticated sockets pin up to 1 MiB each; no auth deadline, no connection cap (medium, dos, reproduced)
- **Reproduction:** `$S/fuzz/mem.py <port> <pid> 200 700000 partial` (200 sockets, each sending a 700 KB partial frame). `$S/leaks/hold.py $S <port> <pid> 500` (500 raw upgrades with no `Authenticate`, one ping each).
- **Observed:** 200 partial-frame sockets raised RSS from 7.6 MB to 175 MB (about 0.83 MB each), and all stayed open. Attackers measured 839 MB at 1000 sockets. 500 idle unauthenticated sockets cost about 145 KB each (7 to 79 MB), and 3000 cost about 440 MB. A ping-only socket was still open after 330 s. Memory returned after close, so this is not a leak. `/health` stayed responsive.
- **Expected:** frame limit close to the 64 KiB message limit, `Authenticate` within about 10 s, global and per-IP connection caps, and a smaller idle footprint.
- **Location:** `settler_island_server/src/lib.rs:53` (`MAX_FRAME_BYTES = 1024 * 1024`), `lib.rs:174-190` (upgrade with no limiter and default buffer sizes); `connection.rs:106-125` (`read_loop` uses the 300 s `idle_timeout` in every state, and `Ping`/`Pong` count as activity).
- **Fix:** set `max_message_size`/`max_frame_size` to `MAX_MESSAGE_BYTES` plus small slack. Use a short timeout (about 10 s) while `user` is `None`, and do not count Ping/Pong as activity before authentication. Add a global and per-IP connection semaphore taken in `upgrade` and held for the socket's lifetime. The roughly 145 KB idle cost is most likely tungstenite's default 128 KiB read/write buffers. Measure it, then set `read_buffer_size`/`write_buffer_size` on the upgrade.

### M2. Unbounded concurrent Argon2 verifies and unlimited lobby-password guesses (medium, abuse, code-confirmed)
- **Reproduction:** `$S/lobby/t_brute.py 40 12`. The lead's re-run failed in the script's own setup, and the code confirms the path.
- **Observed:** attackers measured about 455 guesses/s, RSS 913 MB with 40 sockets and 3.08 GB with 150. Each `JoinLobby` with a password runs `spawn_blocking(password::verify)` with `Argon2::default()` (19 MiB of memory per call). There is no semaphore and no failed-attempt counter. The only brake is the per-connection limit of 20 messages/s, and connections are unlimited.
- **Expected:** a bounded number of concurrent hashes and verifies, plus a limit on wrong guesses per (user, lobby) and per IP with backoff.
- **Location:** `settler_island_server/src/connection.rs:324-330` (verify), `:387-395` (hash); `password.rs:14,25`.
- **Fix:** a process-wide semaphore of 4-8 permits around hash and verify, owned by `password.rs` with an async API. Count wrong passwords per (user, lobby) and per IP, and answer `RateLimited` after about 5 per minute.

### M3. Outbox bounded by message count, not bytes: a non-reading client pins about 6 MB (medium, dos, reproduced)
- **Reproduction:** `PID=$($S/leaks/srv.sh 19302 SETTLER_BOT_DELAY_MILLISECONDS=0); $S/leaks/venv/bin/python $S/leaks/slowmany.py $S/leaks 19302 $PID 40 16 40`. 40 guests each start a game, send `GetState` 16 times per second and never read.
- **Observed:** RSS went from 8 MB to 248 MB in 40 s (about 6 MB per client). The clients were kicked eventually, but the memory stayed with the allocator. 100 clients reached 629 MB, and repeated rounds reached 1074 MB. A request of about 60 bytes produces a reply of about 12 KB (200x amplification). Each client needs its own guest session, which the default limit of 10/min (burst 5) per IP slows but does not stop.
- **Expected:** a cap on queued bytes per connection (for example 256 KiB) and a disconnect when the writer is stuck for a few seconds.
- **Location:** `settler_island_server/src/outbox.rs:9` (`OUTBOX_CAPACITY = 1024` messages); `connection.rs:59` and the `write_loop` around `:82-105`.
- **Fix:** give each outbox a byte budget and kick the connection when it is exceeded. Cut the capacity to 64-128 messages. Wrap `sink.send` in a timeout of about 10 s. Optionally rate-limit `GetState`/`GetRecord` more tightly than other messages.

### M4. Abandoned running games are kept for 168 h with no per-user or global cap (medium, abuse/leak, reproduced)
- **Reproduction:** `$S/integrity/t6.py 40` (loop on one token: `CreateLobby`, `AddBot` x3, `StartGame`, `LeaveLobby`). `$S/leaks/aband.py $S/leaks <port>` for a single game. `$S/load/dropout.py <port> 1000 2` for bulk.
- **Observed:** after the run, `settler_lobbies=40` and `settler_running_games=40` with 0 connections, and all of them appear in `ListLobbies`. The games freeze, because bots wait while no human is connected. Each costs about 80-100 KB of RAM (1000 games: 8 to 111 MB). With Postgres the rows persist as well: about 360 bytes per action and about 1200 actions per finished game, so up to about 0.4 MB per game. One connection creates about 4 games/s. The per-IP session limit and the one-lobby-per-user rule still allow roughly 14k games per day per IP, and many more if forwarded-for trust is misconfigured.
- **Expected:** global and per-user caps on lobbies and running games, a short abandon time for games where no human is connected, and started lobbies with no members hidden from the list.
- **Location:** `settler_island_server/src/lobby.rs:450` (`abandon_at = now + abandon_after` when the last human leaves); `config.rs:11` (`DEFAULT_ABANDON_AFTER_HOURS = 168`); `registry.rs` create/claim (no cap).
- **Fix:** global and per-`UserId` caps that reject with a new error code. A separate, short grace for games with no human present, for example `SETTLER_UNATTENDED_ABANDON_MINUTES` defaulting to 15-60. Rate-limit `CreateLobby`/`StartGame`. Hide started lobbies with no members from `ListLobbies`. Add a metric for games with no human present.

### M5. `.env.example` ships a public session secret that passes validation (medium, config, code-confirmed)
- **Reproduction:** `grep SESSION_SECRET .env.example` shows `local-development-secret-change-me-0123456789` (45 bytes). `config.rs:125-132` only checks `bytes.len() < MIN_SESSION_SECRET_BYTES`.
- **Observed:** a deployment that copies the example signs guest tokens with a public HMAC key, so anyone can mint a token for any `UserId`, including linked account ids.
- **Expected:** the server refuses a known placeholder or a low-entropy secret, or the example leaves the value blank.
- **Location:** `.env.example:7`; `settler_island_server/src/config.rs:125-132`.
- **Fix:** blank the example value and put the generator command (`openssl rand -base64 48`) in a comment. Reject the old placeholder, anything containing `change-me`, and secrets with very few distinct bytes.

### M6. One guest id can be linked to several Keycloak accounts; the guest token stays valid after upgrade (medium, auth, code-confirmed)
- **Reproduction:** `$S/auth/attack.mjs`, section `upgrade`. This needs the Keycloak fake and was not re-run. In the code, `MemoryIdentityStore::link` uses `links.entry(subject).or_insert_with(user)`, which is keyed by subject only. `identity_links.user_id` has no UNIQUE constraint (migration `20261122151852_create_tables.sql:10-12`). `Identity::upgrade` only checks that the subject is not already bound to another user.
- **Observed:** anyone who holds a guest token (30-day lifetime) can attach their own account to that user, even after the rightful owner has upgraded. Both accounts and the old guest token then act as the same `UserId`.
- **Expected:** one subject per user id (`AccountAlreadyLinked` otherwise), and guest tokens of an upgraded user no longer accepted.
- **Location:** `settler_island_server/src/identity/store.rs:47-53`; `postgres.rs` link query (about `:349-366`); `identity/mod.rs:66-82`.
- **Fix:** a new migration adding `UNIQUE (user_id)` on `identity_links`, a reverse lookup in the memory store, and a rejection in `upgrade`. Treat a linked user's guest token as `InvalidToken`, since the account id is the link.

### M7. No HTTP header/body read timeouts or connection cap (slowloris) (medium, dos, code-confirmed)
- **Reproduction:** `$S/http/slow.py <port> hdr|body|ws|idle 100`; `$S/http/many.py <port> 2500`.
- **Observed:** all stalled sockets were still open after 100 s, and 2500 stalled connections cost about 14 KB each. The server is plain `axum::serve` with no `header_read_timeout`, no timeout layer and no connection limit. The cost per connection is small, which keeps this at medium. Ultimately it exhausts file descriptors.
- **Expected:** header and body read timeouts and a total and per-IP connection cap in the server, or the same enforced by the proxy and documented.
- **Location:** `settler_island_server/src/main.rs:50-60`; `lib.rs:137-148`.
- **Fix:** serve through `hyper_util` with `header_read_timeout`, add `tower_http` request and body timeouts on the HTTP routes, and share the connection semaphore from M1. The deployment part is nginx `client_header_timeout`, `client_body_timeout` and `limit_conn` (see section 5, wave D).

### L1. `RateLimited` and `MessageTooLarge` errors carry no `request_id` (low, protocol, code-confirmed and seen in load runs)
- **Observed:** `on_message` (`connection.rs:139-146`) rejects before reading the request id, so the error has `request_id: null`. In load runs `r1` and `r6`, a client received an anonymous `RateLimited`, kept waiting for its reply, and the game stalled (`STALL game 42 after 85 acts`). The generated Godot client behaves the same way.
- **Fix:** read the id with `RequestIdProbe` before both rejections, as `InvalidMessage` already does.

### L2. Pings are not metered; one guest token on unlimited connections; takeover is silent (low, protocol)
- **Observed** (attacker reports): 200k pings were answered, and the connection rate limiter never sees them. When the same user connects again, the displaced connection gets no notice, and replies to its echoed request ids go to the new connection.
- **Location:** `connection.rs:106-125`; `lobby.rs:293-300, 404-415, 665-690`.
- **Fix:** count Ping frames toward the limiter. On takeover, send the old outbox a notice and close it.

### L3. Display and lobby names accept bidi overrides, zero-width and other format characters (low, integrity, reproduced)
- **Reproduction:** `curl -X POST -H 'content-type: application/json' -d '{"name":"‮evil​"}' http://127.0.0.1:<port>/api/v1/sessions/guest` is accepted.
- **Location:** `settler_island_server/src/names.rs:4-9`. Only `char::is_control` is rejected. This also applies to Keycloak names.
- **Fix:** reject the Unicode categories Cf, Zl and Zp and filler characters (U+3164, U+115F and similar), and require at least one visible character.

### L4. Rate-limit keys: IPv6 per /128, and forwarded-for trusted with no proxy allow-list (low, abuse)
- **Observed:** with `trust_forwarded_for` on and the port directly reachable, 40 of 40 session requests with a rotating `X-Forwarded-For` succeeded. The default is off. With IPv6, each /128 gets its own bucket, so a /64 has 2^64 buckets.
- **Location:** `rate_limit.rs:67-82`; `lib.rs:176-215`.
- **Fix:** mask IPv6 to /64, and honour forwarded-for only when the peer is in a configured trusted-proxy list.

### L5. Session routes accept 2 MB bodies; framework rejections are plain text (low, config)
- **Observed:** a 1 MB JSON body is parsed fully, then rejected. `{"name":5}` returns a plain-text serde message instead of the JSON error shape.
- **Location:** `lib.rs:121-127, 166-184`.
- **Fix:** `DefaultBodyLimit::max(4096)` on the session routes, and a `JsonRejection` mapper that returns the JSON `ErrorCode` shape.

### L6. No turn clock; bots take absent seats right after a restart (low, abuse)
- **Observed:** a connected player can stall a game forever by never acting. After a restart, as soon as one human reconnects, bots play for the absent humans with no grace period.
- **Location:** `lobby.rs:200-215, 330-352, 620-650`.
- **Fix:** a turn clock that hands an idle seat to a bot, and a reconnect grace of 30-60 s before bots take absent seats. This is a gameplay decision, so it needs a plan.

### L7. Information exposure (low, info-leak)
- `kc:<sub>` user ids (the Keycloak subject) reach every client through `ListLobbies` and lobby details (`identity/mod.rs:59-62`).
- The contents of `CardsDiscarded` are broadcast to every seat. Other players should see only the count (`settler_island_game/src/event.rs`, `visible_to`).
- `/metrics` is unauthenticated on the game port (`lib.rs:129-134`). It holds aggregates only.
- **Fix:** opaque public ids (a protocol change), discard counts only for other seats, and a separate metrics listener on an internal bind, or blocking it at the proxy.

### L8. A huge `SETTLER_ABANDON_AFTER_HOURS` panics the lobby task and leaves a zombie lobby (low, config, reproduced)
- **Reproduction:** `SETTLER_ABANDON_AFTER_HOURS=18446744073709551615`, then a human leaves a running game (`$S/leaks/zombie.py`).
- **Observed:** a panic at `std/src/time.rs:430` from `Instant::now() + abandon_after` (`lobby.rs:450`). `settler_lobbies` stays 1 while `settler_running_games` is 0. The user's next request times out because the registry still points at the dead task. Only the operator can trigger this.
- **Fix:** cap the setting (for example 24×365 hours) in `config.rs`, use `Instant::checked_add`, and add a drop guard in the lobby task that sends `Closed` to the registry however the task ends.

### L9. Postgres pool has no acquire or statement timeout and is fixed at 8 connections (low, dos, code-confirmed)
- **Observed:** `PgPoolOptions::new().max_connections(8)` and nothing else (`postgres.rs:13, 24-28`). Lobby tasks await `append_action` inline, so a stalled database blocks every lobby for up to sqlx's 30 s default. Load runs showed the pool saturated (8 of 8) at 100 and at 300 games, with no errors.
- **Fix:** `acquire_timeout` of about 5 s, a `statement_timeout` in the connect options, and a configurable `max_connections`.

### L10. Restore replays the full action log; finished games are never pruned (low, load)
- **Observed:** 95k actions took 34 MB in `game_actions` and 7.4 MB in `game_snapshots`. Restoring 100 games took 0.31 s, which is fine today, but rows of finished games stay forever.
- **Location:** `postgres.rs` (`load_actions`); `store.rs:71`.
- **Fix:** load only the actions after the latest snapshot, and add a retention job for finished games.

### L11. RSS grows after games finish with glibc malloc (low, leak by fragmentation, not re-run)
- **Observed:** 87 to 328 MB over 6 rounds of 400 games with all gauges back at 0. With `MALLOC_ARENA_MAX=1`, RSS plateaued at 131 MB. All gauges returned to zero, so no state is leaked; this is fragmentation.
- **Fix:** `mimalloc` or `jemalloc` as the global allocator in `main.rs`, or `MALLOC_ARENA_MAX=2` in the container environment.

### L12. Auth and dependency hardening (low, dependency)
- `nbf` is not validated, and a failed JWKS fetch is not cached as a failure, so every bad token triggers a fetch (`identity/keycloak.rs:60-110`).
- `jsonwebtoken 9.3.1` is affected by GHSA-h395-gr6q-cpjc. `url 2.5.4` is outdated. The gate has no `cargo deny`/`cargo audit`.
- **Fix:** `validate_nbf = true`, back-off after a failed JWKS fetch, `cargo update` (or a major bump of jsonwebtoken if the advisory requires it), and `deny.toml` plus a `cargo deny check` step in `tools/check.sh`.

**Dropped or merged.** Duplicates across slices were merged into the findings above: the zombie and lobby-rate findings into M4, both connection-cap findings into M1, and the secret length policy into M5. Allocator retention after 200 connections returned to 12 MB, so it is not a leak. Seat indexing in `lobby.rs:390-500` was dropped because no client-controlled path exists. Notes on the local Keycloak realm and on rate-limit keying behind a proxy were dropped as configuration notes; they are covered by L4 and the deployment wave.

## 3. Load results

All runs used a release build on the development machine (32 cores, 60 GB) with `SETTLER_BOT_DELAY_MILLISECONDS=0` and session limits lifted. Each game is 1 human (Python client) plus 3 bots, played to the end. Throughput is the server-wide `settler_actions_applied_total` delta per second. Latency is from a human action to the matching state update. The Python clients are single-threaded and niced, so at the high end they add to the measured latency.

| Scenario | Concurrent games / connections | Result | Server cost | RSS |
|---|---|---|---|---|
| 50 games, empty server (`out_1..4`) | 50 / 50 | 50/50 finished, 0 errors, 12.3-13.3k actions/s | about 1 core (4.8 s CPU in 4.8 s) | 8 → 85 MB peak, 60 MB after |
| 50 games next to 150 held sessions and 153 running games (`r_1..4`) | 50 + 153 / 200 | 13.1-14.3k actions/s, p50 25-32 ms, p99 79-160 ms | about 1 core | 121 → 146 MB |
| 200 games (`b_1..4`) | 200 / 200 | 200/200 finished, 14.3-15.1k actions/s, p50 about 185 ms, p99 310-550 ms | 20.4 s CPU in 16-17 s (about 1.2 cores) | 140 → 313 MB peak, 305 MB after |
| 100 games, 4 client processes in parallel (`l_1..4`) | up to 400 / 400 | all finished, 0 errors, 3.7-4.0k actions/s per run, p99 585-830 ms (client-bound) | about 0.4 cores per run | flat at 131 MB (allocator already grown) |
| Postgres, 100 games (`pg/load1`) | 100 | p50 36 ms, p95 87 ms, p99 126 ms | pool 8/8 busy | – |
| Postgres, 300 games (`pg/load3`) | 300 | started in 17 s, p50 111 ms, p95 175 ms, p99 228 ms, no store errors | pool 8/8 busy | – |
| Restart with 100 running games in Postgres (`pg/restore`) | 100 | `/health` after 0.14 s, all 100 restored and resumable | 0.31 s replay | – |
| Postgres size | 95k actions | `game_actions` 34 MB (about 360 B/action, about 0.4 MB per full game), snapshots 7.4 MB | – | – |
| Idle unauthenticated sockets | 500 / 3000 | all accepted, `/health` 0 ms | – | 145 KB per socket (440 MB at 3000) |
| Partial-frame sockets | 200 | all kept open | – | 0.83 MB per socket |
| Non-reading clients spamming `GetState` | 40 / 100 | kicked eventually | – | about 6 MB per client (248 MB / 629 MB) |
| Concurrent password guesses | 40 / 150 sockets | about 455 verifies/s | Argon2 on blocking threads | 913 MB / 3.08 GB |
| Abandoned bot games | 1000 | kept 168 h, frozen | – | 80-100 KB per game |
| Repeated rounds of 400 games, glibc | 6 rounds | gauges back to 0 | – | 87 → 328 MB (131 MB plateau with `MALLOC_ARENA_MAX=1`) |

**What it means.**
- **CPU is not the bottleneck.** The server spends about 80-100 µs of CPU per applied action, including validation, bot moves, the action log and broadcasts, and holds 12-15k actions/s on about one core. With the default 600 ms bot delay and humans thinking for seconds, a game produces well under one action per second. Even a NAS CPU 5-10x slower than the dev machine would carry 1000+ concurrent games.
- **Memory sets the real limit.** Each game costs about 80-100 KB, and each connection about 150 KB idle, before any outbox backlog. 1000 four-human games (4000 connections) come to roughly 100 MB + 600 MB, which is fine on a NAS with a few GB free. The attacks in M1-M4, however, reach the same total with a few hundred sockets. Shrinking the WebSocket buffers (M1) roughly halves the per-player cost.
- **With Postgres, the pool of 8 is the first bottleneck.** Latency triples from 100 to 300 rapid-fire games, though it is still under 250 ms p99. At human speed this is far away, but a stalled database blocks every lobby (L9).
- **Planning number:** one instance comfortably serves a few hundred concurrent players, the realistic ceiling for a hobby server, with large headroom, once the caps from wave A exist. Set the caps to that: for example 1000 connections, 20 per IP, 500 running games and 3 per user.

## 4. What held up

- **Authority and validation.** Fuzzing and logic attacks (out-of-turn actions, foreign seats, invalid trades, discard/robber edge cases, replayed or stale request ids, malformed JSON, wrong types, huge numbers) produced only typed errors (`NotYourTurn`, `WrongPhase`, `InvalidTrade` and others). No panic, no state change, no desync. In the load runs, thousands of invalid human actions were rejected cleanly (for example 3662 `NoTradeOpen` errors at 300 games).
- **Visibility.** No path leaked another player's hand or the development deck. The only leak is the discard contents (L7).
- **Guest tokens with a real secret.** Tampered, truncated, re-signed and expired HMAC tokens were all rejected. Keycloak tokens with a wrong issuer, audience, algorithm, `alg: none` or an unknown `kid` were rejected.
- **Message limits.** The 64 KiB message limit and the 20 messages/s per-connection limiter worked as designed. The problems are the frame buffer below them (M1) and missing ids on rejections (L1).
- **Session rate limiting.** It is per IP by default and does not trust forwarded-for unless configured.
- **Stability.** No crash, deadlock or hang under any client-driven load. Every game finished, and gauges returned to zero after clients left. The only panic needed an absurd operator setting (L8).
- **Persistence.** The action log was written before broadcast, with no lost writes at 300 games. 100 running games survived a restart and resumed in 0.31 s.
- **Code hygiene.** No `unwrap`/`expect` reachable from client input, and all SQL is parameterized through sqlx.

## 5. Fix plan

Rules for every task:
- TDD: the regression test comes first and must fail before the fix. Where it fits, the test is a server integration test in `settler_island_server/tests/` that reproduces the attack, using a real WebSocket client against an ephemeral port.
- After the fix, prove the test bites: revert the fix in a trap-guarded script and confirm the test fails.
- One concern per commit, and a green `tools/check.sh` (plus `tools/check.sh db` for store changes) before merge.

Tasks in one wave touch disjoint files. Shared files (`config.rs`, `Cargo.toml`, the protocol `ErrorCode`, `client/`) are changed only by the lead in wave 0. No critical or high findings exist, so waves 1-2 carry the mediums, ordered by impact.

**Wave 0. Lead, shared files (one sitting)**
- 0a. Protocol: add `ErrorCode::LimitReached` (or `TooManyGames` plus `TooManyConnections`) and regenerate `client/` in the same commit.
- 0b. `config.rs`, every new setting at once, with defaults and validation tests:
  - `max_connections`, `max_connections_per_ip`, `auth_timeout` (10 s)
  - `max_running_games`, `max_games_per_user`, `unattended_abandon_after` (30 min)
  - a cap on `SETTLER_ABANDON_AFTER_HOURS` (L8)
  - `trusted_proxies`, `metrics_bind`, `db_max_connections`, `db_acquire_timeout`
- 0c. M5: blank `.env.example:7` and reject placeholder or low-entropy secrets in `SessionSecret::new`. The test feeds the old example value and expects `ConfigError`.
- 0d. `Cargo.toml`: add the dependencies later waves need (`hyper-util` server features, `tower-http` timeout, and the allocator if chosen).

**Wave 1. Parallel, file-disjoint (mediums)**

| Task | Findings | Files | Regression test |
|---|---|---|---|
| 1A | M1 (server part) | `connection.rs` (`read_loop` auth deadline, no ping activity before auth, ping metering), L1, L2 ping part | Integration: an unauthenticated socket that only pings is closed within `auth_timeout`. A burst over the limit gets `RateLimited` with the sent `request_id`. |
| 1B | M1 (upgrade part), M7 server part, L5 | `lib.rs` (frame size to 64 KiB + slack, smaller read/write buffers, connection semaphore global and per IP, `DefaultBodyLimit`, JSON rejection mapper, timeout layer) | Integration: a 200 KiB frame is rejected and closed. Connection N+1 from one IP is refused. A 10 KB guest body gets a JSON 413. |
| 1C | M4, L8 | `lobby.rs` (unattended abandon grace, `checked_add`, drop guard sends `Closed`), `registry.rs` (global and per-user caps, hide member-less started lobbies) | Integration: create, start and leave in a loop; game N+1 is refused with `LimitReached`. With a short `unattended_abandon_after`, the lobby disappears and `settler_running_games` returns to 0. Unit: a huge `abandon_after` does not panic. |
| 1D | M6 | new migration (`UNIQUE(user_id)` on `identity_links`), `identity/store.rs`, `postgres.rs` link query, `identity/mod.rs` upgrade, `.sqlx` | Unit: memory store, a second subject for the same user gives `AccountAlreadyLinked`. Postgres test (`check.sh db`) for the same. |
| 1E | L3 | `names.rs` | Unit: names with U+202E, U+200B or U+3164, and names made only of format characters, are rejected. |

**Wave 2. Parallel, file-disjoint (remaining mediums and lows)**

| Task | Findings | Files | Regression test |
|---|---|---|---|
| 2A | M2 | `password.rs` (async API with semaphore), `connection.rs` call sites and per (user, lobby) / per-IP wrong-guess counter | Integration: 6 wrong passwords in a minute give `RateLimited`. Unit: hashes in flight never exceed the permit count. |
| 2B | L4 | `rate_limit.rs` (/64 masking, trusted-proxy check) | Unit: two addresses in one /64 share a bucket. Forwarded-for from an untrusted peer is ignored. |
| 2C | L9, L10 (restore part) | `postgres.rs` (acquire/statement timeouts, configurable pool size, load actions after the latest snapshot), `store.rs` | Postgres test: a restore with a snapshot reads only the tail and reaches the same state. A pool with the database paused errors within the acquire timeout. |
| 2D | L12 | `identity/keycloak.rs` (`validate_nbf`, negative JWKS cache with back-off) | Unit: a token with `nbf` in the future is rejected. Two bad-`kid` tokens within the back-off window cause one fetch. |
| 2E | L11, M7 (main part) | `main.rs` (global allocator, `hyper_util` serve with `header_read_timeout`, metrics listener on `metrics_bind`) | Integration: a socket that sends half a request line is closed after the header timeout. |

**Wave 3. Sequential after wave 2 (they touch `connection.rs`/`lobby.rs` again)**
- 3A. M3: a byte budget in `outbox.rs` (kick when exceeded), capacity cut to 64-128 messages, a `sink.send` timeout in `connection.rs` `write_loop`. Integration test: a client that never reads and spams `GetState` is disconnected before 256 KiB is queued, and other players in its game keep receiving updates.
- 3B. L2 takeover: `lobby.rs` notifies and closes the displaced outbox. Integration test: a second login with the same token closes the first socket with a notice.
- 3C. L12 dependencies: `cargo update`, bump jsonwebtoken past the advisory, add `deny.toml` and a `cargo deny check` step in `tools/check.sh`. The lead owns `tools/check.sh` and the lockfile.

**Wave 4. Needs a plan in `doc/plans/` first (gameplay or protocol design)**
- 4A. L6: turn clock and reconnect grace. Rules and the lobby task are involved, so use the most capable model.
- 4B. L7: opaque public user ids (protocol change and client regeneration) and count-only `CardsDiscarded` for other seats (`settler_island_game/src/event.rs`, with a rules test that other seats see only the count).
- 4C. L10 retention: a job that deletes or archives finished games older than N days.

**Wave D. Deployment work (proxy, TLS, NAS), not code; do it together with claiming the NAS port**
- D1. TLS terminated at the pi's nginx, with clients using `wss://`. Proxy `/api/v1/ws` with `Upgrade`/`Connection` headers and a `proxy_read_timeout` above the server's idle timeout.
- D2. nginx `client_header_timeout 10s`, `client_body_timeout 10s`, `client_max_body_size 8k` on `/api/v1/sessions`, `limit_conn` per IP (about 20) and `limit_req` on the session routes. These cover M7 and part of M1 before the code fixes land.
- D3. Block `/metrics` at the proxy, or move it to `metrics_bind` on the NAS's internal network, and point Prometheus at it (L7).
- D4. Set `SETTLER_TRUST_FORWARDED_FOR=true` (and `trusted_proxies`) only after confirming the NAS firewall lets only the pi reach the game port. Otherwise leave it off (L4).
- D5. Generate the secret on the NAS (`openssl rand -base64 48`) and store it only in the NAS env file, never from `.env.example` (M5).
- D6. Container memory limit (for example 512 MB-1 GB) so an attack cannot starve Postgres or ClickHouse on the NAS. Set `MALLOC_ARENA_MAX=2` if 2E does not switch the allocator.
- D7. Postgres role `statement_timeout`, and add the game tables to the nightly backup.
- D8. Monitoring: add the container to the ContainerMissing list, and alert on `settler_connections`, `settler_running_games` (and the new unattended-games metric) and RSS.
- D9. Update the shared-knowledge notes (port, network, backup, monitoring) in the same turn.

