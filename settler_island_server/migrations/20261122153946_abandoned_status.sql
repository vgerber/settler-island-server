-- A running game nobody has joined for a long time is closed without a winner.
ALTER TABLE games DROP CONSTRAINT games_status_check;
ALTER TABLE games ADD CONSTRAINT games_status_check CHECK (status IN ('running', 'finished', 'abandoned'));
