use std::sync::Arc;

use settler_island_protocol::ServerMessage;
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::{mpsc, Notify};
use tracing::warn;

/// Queued messages per connection before the client counts as stuck.
pub(crate) const OUTBOX_CAPACITY: usize = 1024;

/// The sending half of one connection's writer task.
#[derive(Debug, Clone)]
pub(crate) struct Outbox {
    sender: mpsc::Sender<ServerMessage>,
    kick: Arc<Notify>,
}

impl Outbox {
    pub(crate) fn new(sender: mpsc::Sender<ServerMessage>, kick: Arc<Notify>) -> Outbox {
        Outbox { sender, kick }
    }

    /// Never waits: a client that cannot keep up is disconnected instead of stalling the sender.
    pub(crate) fn send(&self, message: ServerMessage) {
        match self.sender.try_send(message) {
            Ok(()) | Err(TrySendError::Closed(_)) => {}
            Err(TrySendError::Full(_)) => {
                warn!("outbox full, disconnecting the client");
                self.kick.notify_one();
            }
        }
    }
}
