use settler_island_server::{serve, Config, MemoryIdentityStore, MemoryStore};
use tokio::net::TcpListener;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> std::process::ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            error!(%error, "server stopped");
            std::process::ExitCode::FAILURE
        }
    }
}

#[derive(Debug, thiserror::Error)]
enum StartError {
    #[error(transparent)]
    Config(#[from] settler_island_server::ConfigError),
    #[error("network: {0}")]
    Io(#[from] std::io::Error),
}

async fn run() -> Result<(), StartError> {
    let config = Config::from_env()?;
    let listener = TcpListener::bind(config.bind).await?;
    info!(address = %listener.local_addr()?, "listening");
    serve(
        listener,
        config,
        MemoryStore::default(),
        MemoryIdentityStore::default(),
        shutdown_signal(),
    )
    .await?;
    info!("shut down");
    Ok(())
}

async fn shutdown_signal() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        error!(%error, "waiting for ctrl-c failed, running until killed");
        std::future::pending::<()>().await;
    }
}
