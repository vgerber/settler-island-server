pub type StateId = &'static str;

pub trait HasStateId {
    fn get_id(&self) -> StateId;
}
