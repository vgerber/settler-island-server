use std::collections::HashMap;

use crate::server::user_connection::UserConnection;

use super::reader::MessageReaderProvider;

pub struct MessageBroker {
    message_readers: HashMap<String, Box<dyn MessageReaderProvider>>,
}

impl MessageBroker {
    pub fn new() -> Self {
        MessageBroker {
            message_readers: HashMap::new(),
        }
    }

    pub fn register(
        &mut self,
        message_reader: Box<dyn MessageReaderProvider>,
    ) -> Result<(), String> {
        self.message_readers
            .insert(message_reader.get_group().clone(), message_reader);
        Ok(())
    }

    pub async fn call(
        &self,
        user: &UserConnection,
        group: &str,
        command: &str,
        json_message: &str,
    ) -> Result<(), String> {
        match self.message_readers.get(group) {
            Some(reader) => reader.call(user, command, json_message).await,
            None => Err(format!("Reader for \"{}\" not found", group)),
        }
    }
}
