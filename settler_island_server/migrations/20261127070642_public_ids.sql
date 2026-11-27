-- The id clients see for a user: random, so it reveals nothing about the user id, and kept forever.
CREATE TABLE public_ids (
    user_id TEXT PRIMARY KEY,
    public_id TEXT NOT NULL UNIQUE,
    created TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users of stored games get theirs now, so restored lobbies can name every seat.
INSERT INTO public_ids (user_id, public_id)
SELECT id, replace(gen_random_uuid()::text, '-', '') FROM users;
