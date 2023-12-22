#[allow(dead_code, unused)]
mod server;
use std::net::SocketAddr;

use log::{error, info};
use server::{GameServer, GameServerAccess};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{
    accept_async,
    tungstenite::{Error, Result},
};

use crate::server::user_connection::UserConnection;

async fn accept_connection(
    game_server: GameServerAccess,
    connection_stream: TcpStream,
    connection_address: SocketAddr,
) {
    if let Err(handle_error) =
        handle_connection(game_server, connection_stream, connection_address).await
    {
        match handle_error {
            Error::ConnectionClosed | Error::Protocol(_) | Error::Utf8 => (),
            handle_error => {
                error!(
                    "Client {} processing failed \"{}\"",
                    connection_address, handle_error
                )
            }
        }
    }
}

async fn handle_connection(
    game_server: GameServerAccess,
    connection_stream: TcpStream,
    connection_address: SocketAddr,
) -> Result<()> {
    info!("Client {connection_address} connected");
    let websocket_stream = accept_async(connection_stream)
        .await
        .expect("Failed to accept client");

    let connection = UserConnection::from(websocket_stream, connection_address, game_server);
    UserConnection::listen(&connection).await
}

#[tokio::main]
async fn main() {
    env_logger::init();
    let try_socket = TcpListener::bind("127.0.0.1:8253").await;
    let listener = try_socket.expect("Failed to bind");
    info!("Listening on 8253");

    let game_server = GameServer::new();
    while let Ok((stream, address)) = listener.accept().await {
        tokio::spawn(accept_connection(game_server.clone(), stream, address));
    }
}
