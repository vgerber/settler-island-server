use std::collections::HashMap;
use std::future::Future;
use std::sync::Mutex;

use settler_island_protocol::UserId;

#[derive(Debug, thiserror::Error)]
pub enum IdentityStoreError {
    #[error("the identity store lock is poisoned")]
    Poisoned,
    #[error("the user id is linked to another account already")]
    UserAlreadyLinked,
    #[error("database: {0}")]
    Database(#[from] sqlx::Error),
}

/// Maps Keycloak subjects to the user ids of upgraded guests.
pub trait IdentityStore: Send + Sync + 'static {
    /// The user id `subject` was linked to, if any.
    fn linked_user(
        &self,
        subject: &str,
    ) -> impl Future<Output = Result<Option<UserId>, IdentityStoreError>> + Send;

    /// Whether some account was linked to `user`, which retires the guest token for that id.
    fn is_linked(
        &self,
        user: &UserId,
    ) -> impl Future<Output = Result<bool, IdentityStoreError>> + Send;

    /// Links `subject` to `user` unless it is linked already; returns the user id it maps to afterwards.
    /// A new subject for a user id that another account holds is `UserAlreadyLinked`.
    fn link(
        &self,
        subject: &str,
        user: &UserId,
    ) -> impl Future<Output = Result<UserId, IdentityStoreError>> + Send;
}

/// Keeps links in memory; they are lost on restart.
#[derive(Debug, Default)]
pub struct MemoryIdentityStore {
    // A plain mutex is fine: it is never held across an await.
    links: Mutex<HashMap<String, UserId>>,
}

impl IdentityStore for MemoryIdentityStore {
    async fn linked_user(&self, subject: &str) -> Result<Option<UserId>, IdentityStoreError> {
        let links = self
            .links
            .lock()
            .map_err(|_| IdentityStoreError::Poisoned)?;
        Ok(links.get(subject).cloned())
    }

    async fn link(&self, subject: &str, user: &UserId) -> Result<UserId, IdentityStoreError> {
        let mut links = self
            .links
            .lock()
            .map_err(|_| IdentityStoreError::Poisoned)?;
        if let Some(existing) = links.get(subject) {
            return Ok(existing.clone());
        }
        if links.values().any(|linked| linked == user) {
            return Err(IdentityStoreError::UserAlreadyLinked);
        }
        links.insert(subject.to_string(), user.clone());
        Ok(user.clone())
    }

    async fn is_linked(&self, user: &UserId) -> Result<bool, IdentityStoreError> {
        let links = self
            .links
            .lock()
            .map_err(|_| IdentityStoreError::Poisoned)?;
        Ok(links.values().any(|linked| linked == user))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_second_subject_cannot_take_a_linked_user_id() {
        let store = MemoryIdentityStore::default();
        let user = UserId("guest".to_string());
        assert!(!store.is_linked(&user).await.unwrap());
        assert_eq!(store.link("first", &user).await.unwrap(), user);
        assert!(store.is_linked(&user).await.unwrap());
        assert!(matches!(
            store.link("second", &user).await,
            Err(IdentityStoreError::UserAlreadyLinked)
        ));
        assert_eq!(store.linked_user("second").await.unwrap(), None);
        // Linking the same subject again is not an error.
        assert_eq!(store.link("first", &user).await.unwrap(), user);
    }
}
