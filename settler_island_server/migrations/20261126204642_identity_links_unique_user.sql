-- One account per user id. Rows sharing a user_id can only come from the old upgrade hole (a second subject linked to
-- a guest id); the earliest link is the rightful owner's, so it is kept and the later ones are dropped.
DELETE FROM identity_links AS link
USING identity_links AS earlier
WHERE link.user_id = earlier.user_id
  AND (earlier.created, earlier.keycloak_sub) < (link.created, link.keycloak_sub);

ALTER TABLE identity_links ADD CONSTRAINT identity_links_user_id_key UNIQUE (user_id);
