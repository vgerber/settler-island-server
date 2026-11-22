use crate::error::GameError;
use crate::event::Event;

/// Bank, port and player trade arrive in step 2a.
pub(crate) fn not_implemented() -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}
