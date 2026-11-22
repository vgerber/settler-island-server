use std::collections::HashMap;
use std::future::Future;
use std::sync::Mutex;

use settler_island_protocol::UserId;

#[derive(Debug, thiserror::Error)]
pub enum IdentityStoreError {
    #[error("the identity store lock is poisoned")]
    Poisoned,
}

/// Maps Keycloak subjects to the user ids of upgraded guests.
pub trait IdentityStore: Send + Sync + 'static {
    /// The user id `subject` was linked to, if any.
    fn linked_user(
        &self,
        subject: &str,
    ) -> impl Future<Output = Result<Option<UserId>, IdentityStoreError>> + Send;

    /// Links `subject` to `user` unless it is linked already; returns the user id it maps to afterwards.
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
        Ok(links
            .entry(subject.to_string())
            .or_insert_with(|| user.clone())
            .clone())
    }
}
