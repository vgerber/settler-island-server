use std::{net::SocketAddr, sync::Arc};

use futures_util::{
    stream::{SplitSink, SplitStream},
    SinkExt, StreamExt,
};
use log::{debug, error, info};
use serde_json::{json, Error, Value};
use tokio::{net::TcpStream, sync::Mutex};
use tokio_tungstenite::{
    tungstenite::{Message, Result},
    WebSocketStream,
};

use crate::server::message::reader::MessageBase;

use super::{
    lobby::game_lobby::GameLobbyAccess,
    message::{
        broker::MessageBroker, error_codes::ErrorCode,
        reader::game_server_message::GameServerMessage,
    },
    user::UserData,
    GameServerAccess,
};

pub type StreamSendAccess = Arc<Mutex<SplitSink<WebSocketStream<TcpStream>, Message>>>;
pub type StreamReceiveAccess = Arc<Mutex<SplitStream<WebSocketStream<TcpStream>>>>;
pub type UserGameStateAccess = Arc<Mutex<UserGameState>>;

pub struct UserGameState {
    pub user: Option<UserData>,
    pub lobby: Option<GameLobbyAccess>,
}

#[derive(Clone)]
pub struct UserConnection {
    connection_address: SocketAddr,
    stream_send: StreamSendAccess,
    stream_receive: StreamReceiveAccess,
    server: GameServerAccess,
    game_state: UserGameStateAccess,
}

unsafe impl Send for UserConnection {}

unsafe impl Sync for UserConnection {}

impl UserGameState {
    pub fn new() -> Self {
        UserGameState {
            user: None,
            lobby: None,
        }
    }
}

impl UserConnection {
    pub fn from(
        stream: WebSocketStream<TcpStream>,
        connection_address: SocketAddr,
        server: GameServerAccess,
    ) -> UserConnection {
        let (send, receive) = stream.split();

        UserConnection {
            connection_address,
            stream_send: StreamSendAccess::new(Mutex::new(send)),
            stream_receive: StreamReceiveAccess::new(Mutex::new(receive)),
            server: server,
            game_state: UserGameStateAccess::new(Mutex::new(UserGameState::new())),
        }
    }

    pub async fn listen(user_connection: &UserConnection) -> Result<()> {
        debug!(
            "Client {} starts listening",
            user_connection.connection_address
        );
        let mut message_broker = MessageBroker::new();
        message_broker
            .register(Box::new(GameServerMessage::new()))
            .expect("Failed to register GameServerMessage");
        let connection_address = user_connection.connection_address;
        while let Some(connection_message) =
            user_connection.stream_receive.lock().await.next().await
        {
            match connection_message {
                Ok(message) => {
                    if !message.is_text() {
                        debug!("Client {} send {:?}", connection_address, message);
                        continue;
                    }
                    UserConnection::read_message(
                        &user_connection,
                        &message_broker,
                        &message.to_string(),
                    )
                    .await;
                }
                Err(error) => {
                    info!(
                        "Client {} send invalid message format \"{}\"",
                        error, connection_address,
                    )
                }
            }
        }

        info!("Client {} disconnected", connection_address);

        let opt_user = user_connection.game_state.lock().await.user.clone();
        if let Some(user) = opt_user {
            match user_connection
                .server
                .lock()
                .await
                .unregister_user(user.get_id())
                .await
            {
                Ok(_) => {}
                Err(err) => error!("Failed to unregister {:?} \"{}\"", user, err),
            }
        }
        info!("Client {} unregistered", connection_address);
        Ok(())
    }

    async fn read_message(
        user_connection: &UserConnection,
        message_broker: &MessageBroker,
        message: &str,
    ) {
        let connection_address = user_connection.connection_address;
        debug!("Client {} send \"{}\"", connection_address, message);
        let message_base_result: Result<MessageBase, Error> =
            serde_json::from_str(&message.to_string());
        let processing_result = match message_base_result {
            Ok(message_base) => {
                message_broker
                    .call(
                        &user_connection,
                        &message_base.group,
                        &message_base.command,
                        message,
                    )
                    .await
            }
            Err(err) => Err(format!(
                "{} Failed to read json message \"{:?}\"",
                connection_address, err
            )),
        };
        if let Err(err) = processing_result {
            error!(
                "{} Failed to process message \"{}\"",
                connection_address, err
            );
        }
        // user_connection
        //     .lock()
        //     .await
        //     .send("DemoMessage")
        //     .await
        //     .unwrap();
    }

    pub async fn send_error(&self, error: ErrorCode) -> Result<()> {
        self.send(
            "error",
            "error",
            json!({"code": error.1, "message": error.0}),
        )
        .await
    }

    pub async fn send(&self, group: &str, command: &str, payload: Value) -> Result<()> {
        let message =
            json!({ "version": 1, "group": group, "command": command, "payload": payload });

        self.stream_send
            .lock()
            .await
            .send(tokio_tungstenite::tungstenite::Message::Text(
                message.to_string(),
            ))
            .await
    }

    pub fn get_server(&self) -> &GameServerAccess {
        &self.server
    }

    pub fn get_game_state(&self) -> &UserGameStateAccess {
        &self.game_state
    }
}
