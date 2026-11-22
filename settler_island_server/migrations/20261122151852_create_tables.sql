-- Everyone who sat at a game; guests and accounts alike.
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    created TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A Keycloak subject maps to the guest id it was upgraded from; the first link wins.
CREATE TABLE identity_links (
    keycloak_sub TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE games (
    id BIGSERIAL PRIMARY KEY,
    lobby_id INTEGER NOT NULL,
    lobby_name TEXT NOT NULL,
    bot_difficulty JSONB NOT NULL,
    -- The seed stays out of the settings: it reveals every future roll.
    settings JSONB NOT NULL,
    seed BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'finished')),
    created TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished TIMESTAMPTZ,
    winner SMALLINT
);

CREATE INDEX games_running ON games (id) WHERE status = 'running';

CREATE TABLE game_seats (
    game BIGINT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
    seat SMALLINT NOT NULL,
    user_id TEXT REFERENCES users (id),
    bot_difficulty JSONB,
    PRIMARY KEY (game, seat),
    CHECK ((user_id IS NULL) <> (bot_difficulty IS NULL))
);

CREATE TABLE game_actions (
    game BIGINT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
    index INTEGER NOT NULL,
    seat SMALLINT NOT NULL,
    action JSONB NOT NULL,
    events JSONB NOT NULL,
    PRIMARY KEY (game, index)
);

-- The full game state after `index` actions, every 50 actions, so a restart replays only the tail.
CREATE TABLE game_snapshots (
    game BIGINT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
    index INTEGER NOT NULL,
    state JSONB NOT NULL,
    PRIMARY KEY (game, index)
);
