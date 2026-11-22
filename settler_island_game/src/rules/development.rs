use crate::error::GameError;
use crate::event::Event;

/// Buying and playing development cards arrive in step 2b.
pub(crate) fn not_implemented() -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}
