-- What a running game does with the seat of a human who is away; games from before keep today's bot stand-in.
ALTER TABLE games ADD COLUMN away_policy JSONB NOT NULL DEFAULT '"BotTakesOver"';
