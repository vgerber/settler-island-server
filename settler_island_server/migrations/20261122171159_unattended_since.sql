-- Since when no human is connected to a running game, so the abandon deadline survives a restart.
ALTER TABLE games ADD COLUMN unattended_since TIMESTAMPTZ;
