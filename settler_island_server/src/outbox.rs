use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;

use settler_island_protocol::ServerMessage;
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::{mpsc, Notify};
use tracing::{error, warn};

/// Queued messages per connection before the client counts as stuck.
pub(crate) const OUTBOX_CAPACITY: usize = 128;

/// Serialized bytes queued or being written per connection before the client counts as stuck;
/// one state answer is about 10 KB, so a reading client never comes close.
pub(crate) const OUTBOX_BUDGET_BYTES: usize = 256 * 1024;

/// The sending half of one connection's writer task.
#[derive(Debug, Clone)]
pub(crate) struct Outbox {
    sender: mpsc::Sender<String>,
    kick: Arc<Notify>,
    queued_bytes: Arc<AtomicUsize>,
    /// Set when the client was disconnected for falling behind; its queue is not worth flushing.
    stalled: Arc<AtomicBool>,
}

/// The writer task's half: serialized messages in order, counted against the budget until written.
#[derive(Debug)]
pub(crate) struct OutboxReceiver {
    receiver: mpsc::Receiver<String>,
    kick: Arc<Notify>,
    queued_bytes: Arc<AtomicUsize>,
}

impl Outbox {
    /// `kick` is notified when the client falls behind and must be disconnected.
    pub(crate) fn channel(kick: Arc<Notify>) -> (Outbox, OutboxReceiver) {
        let (sender, receiver) = mpsc::channel(OUTBOX_CAPACITY);
        let queued_bytes = Arc::new(AtomicUsize::new(0));
        let outbox = Outbox {
            sender,
            kick: kick.clone(),
            queued_bytes: queued_bytes.clone(),
            stalled: Arc::new(AtomicBool::new(false)),
        };
        let receiver = OutboxReceiver {
            receiver,
            kick,
            queued_bytes,
        };
        (outbox, receiver)
    }

    /// Shared with the connection so it can skip flushing a client that stopped reading.
    pub(crate) fn stalled_flag(&self) -> Arc<AtomicBool> {
        self.stalled.clone()
    }

    pub(crate) fn same_connection(&self, other: &Outbox) -> bool {
        self.sender.same_channel(&other.sender)
    }

    /// Never waits: a client that cannot keep up is disconnected instead of stalling the sender.
    pub(crate) fn send(&self, message: ServerMessage) {
        let text = match serde_json::to_string(&message) {
            Ok(text) => text,
            Err(error) => {
                error!(%error, "serializing a server message failed");
                return;
            }
        };
        let bytes = text.len();
        let queued_before = self.queued_bytes.fetch_add(bytes, Ordering::Relaxed);
        // One message larger than the budget still goes out when nothing else is waiting.
        if queued_before > 0 && queued_before + bytes > OUTBOX_BUDGET_BYTES {
            self.queued_bytes.fetch_sub(bytes, Ordering::Relaxed);
            warn!(
                queued_before,
                "outbox over its byte budget, disconnecting the client"
            );
            self.stall();
            return;
        }
        match self.sender.try_send(text) {
            Ok(()) => {}
            Err(TrySendError::Closed(_)) => {
                self.queued_bytes.fetch_sub(bytes, Ordering::Relaxed);
            }
            Err(TrySendError::Full(_)) => {
                self.queued_bytes.fetch_sub(bytes, Ordering::Relaxed);
                warn!("outbox full, disconnecting the client");
                self.stall();
            }
        }
    }

    fn stall(&self) {
        self.stalled.store(true, Ordering::Relaxed);
        self.kick.notify_one();
    }

    /// Queues the last message, then asks the connection to close once it is written.
    pub(crate) fn send_and_close(&self, message: ServerMessage) {
        self.send(message);
        self.kick.notify_one();
    }
}

impl OutboxReceiver {
    /// The next serialized message; call `written` with its length once it is on the socket.
    pub(crate) async fn recv(&mut self) -> Option<String> {
        self.receiver.recv().await
    }

    pub(crate) fn written(&self, bytes: usize) {
        self.queued_bytes.fetch_sub(bytes, Ordering::Relaxed);
    }

    /// Ends the connection, for a writer that failed or stalled.
    pub(crate) fn disconnect(&self) {
        self.kick.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use futures_util::FutureExt;
    use settler_island_protocol::{ErrorCode, ServerMessage};
    use tokio::sync::Notify;

    use super::{Outbox, OUTBOX_BUDGET_BYTES};

    fn message_of(text_bytes: usize) -> ServerMessage {
        ServerMessage::Error {
            request_id: None,
            code: ErrorCode::InvalidMessage,
            message: "x".repeat(text_bytes),
        }
    }

    fn kicked(kick: &Notify) -> bool {
        kick.notified().now_or_never().is_some()
    }

    #[tokio::test]
    async fn queued_bytes_over_the_budget_kick_the_client_and_written_bytes_free_it() {
        let kick = Arc::new(Notify::new());
        let (outbox, mut receiver) = Outbox::channel(kick.clone());
        // Each message is 20 KiB of text plus under 100 bytes of envelope, far below the message capacity.
        let fits = OUTBOX_BUDGET_BYTES / (20 * 1024 + 100);
        for _ in 0..fits {
            outbox.send(message_of(20 * 1024));
        }
        assert!(!kicked(&kick));

        let text = receiver.recv().await.unwrap();
        receiver.written(text.len());
        outbox.send(message_of(20 * 1024));
        assert!(!kicked(&kick));

        outbox.send(message_of(20 * 1024));
        assert!(kicked(&kick));
    }

    #[tokio::test]
    async fn one_message_above_the_budget_goes_out_when_nothing_else_waits() {
        let kick = Arc::new(Notify::new());
        let (outbox, mut receiver) = Outbox::channel(kick.clone());
        outbox.send(message_of(OUTBOX_BUDGET_BYTES));
        assert!(!kicked(&kick));
        assert!(receiver.recv().await.is_some());
    }
}
