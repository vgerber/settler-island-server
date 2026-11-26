//! Who a client is: guests hold a server-signed token, accounts a Keycloak access token; both map to one `UserId`.

mod guest;
mod keycloak;
mod store;

use std::time::{SystemTime, UNIX_EPOCH};

use settler_island_protocol::{
    ErrorCode, GuestSession, User, UserId, UserKind, MAX_USER_NAME_CHARS,
};
use tracing::{debug, error};

use crate::config::Config;
use crate::names::clean_name;
use guest::{GuestTokens, GUEST_TOKEN_PREFIX};
use keycloak::{AccountClaims, AccountTokenError, KeycloakVerifier};

pub use store::{IdentityStore, IdentityStoreError, MemoryIdentityStore};

/// Distinguishes account ids from guest uuids.
const ACCOUNT_ID_PREFIX: &str = "kc:";
const FALLBACK_ACCOUNT_NAME: &str = "Player";

pub(crate) struct Identity<I> {
    guests: GuestTokens,
    keycloak: Option<KeycloakVerifier>,
    store: I,
}

impl<I: IdentityStore> Identity<I> {
    pub(crate) fn new(config: &Config, store: I) -> Identity<I> {
        Identity {
            guests: GuestTokens::new(config.session_secret.clone()),
            keycloak: config.keycloak.as_ref().map(KeycloakVerifier::new),
            store,
        }
    }

    pub(crate) fn guest_session(&self, name: &str) -> Result<GuestSession, ErrorCode> {
        let name = clean_name(name, MAX_USER_NAME_CHARS).ok_or(ErrorCode::InvalidName)?;
        let user = User {
            id: UserId(uuid::Uuid::new_v4().to_string()),
            name,
            kind: UserKind::Guest,
        };
        let token = self.guests.issue(&user, unix_now());
        Ok(GuestSession { token, user })
    }

    /// Accepts a guest token or a Keycloak access token.
    pub(crate) async fn authenticate(&self, token: &str) -> Result<User, ErrorCode> {
        if token.starts_with(GUEST_TOKEN_PREFIX) {
            return self.live_guest(token).await;
        }
        let claims = self.account(token).await?;
        let linked = self
            .store
            .linked_user(&claims.sub)
            .await
            .map_err(internal)?;
        let id = linked.unwrap_or_else(|| UserId(format!("{ACCOUNT_ID_PREFIX}{}", claims.sub)));
        Ok(account_user(id, &claims))
    }

    /// Links the guest's id to the account, so the account keeps the guest's games.
    pub(crate) async fn upgrade(
        &self,
        guest_token: &str,
        account_token: &str,
    ) -> Result<User, ErrorCode> {
        let guest = self.live_guest(guest_token).await?;
        let claims = self.account(account_token).await?;
        let linked = match self.store.link(&claims.sub, &guest.id).await {
            Ok(linked) => linked,
            Err(IdentityStoreError::UserAlreadyLinked) => {
                return Err(ErrorCode::AccountAlreadyLinked)
            }
            Err(error) => return Err(internal(error)),
        };
        if linked != guest.id {
            return Err(ErrorCode::AccountAlreadyLinked);
        }
        Ok(account_user(linked, &claims))
    }

    /// A guest token stops working once its user id belongs to an account: the account is the identity from then on.
    async fn live_guest(&self, token: &str) -> Result<User, ErrorCode> {
        let guest = self.guest(token)?;
        if self.store.is_linked(&guest.id).await.map_err(internal)? {
            debug!("guest token rejected: the user was upgraded");
            return Err(ErrorCode::InvalidToken);
        }
        Ok(guest)
    }

    fn guest(&self, token: &str) -> Result<User, ErrorCode> {
        self.guests.verify(token, unix_now()).map_err(|error| {
            debug!(%error, "guest token rejected");
            ErrorCode::InvalidToken
        })
    }

    async fn account(&self, token: &str) -> Result<AccountClaims, ErrorCode> {
        let verifier = self.keycloak.as_ref().ok_or(ErrorCode::AccountsDisabled)?;
        verifier.verify(token).await.map_err(|error| match error {
            AccountTokenError::MissingKeyId
            | AccountTokenError::UnknownKeyId(_)
            | AccountTokenError::Rejected(_) => {
                debug!(%error, "account token rejected");
                ErrorCode::InvalidToken
            }
            AccountTokenError::KeysUnavailable(_) => internal(error),
        })
    }
}

fn account_user(id: UserId, claims: &AccountClaims) -> User {
    let name = claims
        .preferred_username
        .as_deref()
        .map(|name| name.chars().take(MAX_USER_NAME_CHARS).collect::<String>())
        .and_then(|name| clean_name(&name, MAX_USER_NAME_CHARS))
        .unwrap_or_else(|| FALLBACK_ACCOUNT_NAME.to_string());
    User {
        id,
        name,
        kind: UserKind::Account,
    }
}

fn internal(error: impl std::fmt::Display) -> ErrorCode {
    error!(%error, "identity lookup failed");
    ErrorCode::Internal
}

fn unix_now() -> u64 {
    // Only a clock set before 1970 fails here; such a host has bigger problems than token expiry.
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs())
}
