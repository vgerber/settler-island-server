# Wave 4: away policy per lobby and opaque public ids

User decisions 2026-11-27 (security review wave 4): absent players are a lobby setting; clients see opaque ids;
finished games are kept forever (no retention job).

## 4a. Away policy (protocol, lobby; most capable model)
- `AwayPolicy { BotTakesOver, WaitForPlayer }` in the protocol, chosen in `CreateLobby` (optional, default
  `BotTakesOver` = today's behaviour) and shown in `LobbyInfo`; `DEFAULT_AWAY_POLICY` reaches `SiLimits`.
- `BotTakesOver`: as today, a bot plays the seat of a human who left until they rejoin.
- `WaitForPlayer`: the seat stays human; when that seat is pending, nobody moves (bots of other seats wait too, so the
  game does not run ahead), the other players see who is awaited; the abandon rules (unattended grace, 168 h) still
  close a game nobody returns to.
- Restarts: restored lobbies keep the policy (stored with the game; a migration adds the column, default
  `BotTakesOver` for existing rows); with `WaitForPlayer` restored human seats get no bot.
- Client: the lobby browser's create form offers the choice; the room and the game show it; regenerate `client/`.
- Acceptance: integration tests for both policies (leave mid-game: bot moves vs nobody moves; rejoin continues;
  restart keeps the policy with Postgres), mouse-only playtest green.

## 4b. Opaque public ids (protocol; most capable model; after 4a)
- Clients never see a `UserId` (guest ids, `kc:<sub>`). Lobby and game messages carry a `PublicId` instead: random,
  per user, stable for the server's lifetime and across restarts (stored), not derivable from the user id.
- The server maps `PublicId` <-> `UserId` in the identity store; the own session still learns its own `PublicId`
  (Welcome) so the client can find itself.
- `GetRecord`, `LobbyState`, `GameStarted`, `Lobbies`, owner fields and everything else that names a user use it.
- Acceptance: a test walks every ServerMessage sample (the Rust fixtures in godot.rs) and fails if any user id string
  appears; integration test: two clients see each other only by public id; Postgres restart keeps the ids.
