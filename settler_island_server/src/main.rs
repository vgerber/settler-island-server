use settler_island_server::{
    serve, Config, LogFormat, MemoryIdentityStore, MemoryStore, PostgresStore, ServeError,
    StoreError,
};
use tokio::net::TcpListener;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> std::process::ExitCode {
    // Logging is not up yet when the configuration is bad, so this one goes to stderr.
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("invalid configuration: {error} (see .env.example)");
            return std::process::ExitCode::from(2);
        }
    };
    if let Err(error) = init_logging(&config) {
        eprintln!("invalid configuration: RUST_LOG is not a valid filter: {error}");
        return std::process::ExitCode::from(2);
    }
    match run(config).await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            error!(%error, "server stopped");
            std::process::ExitCode::FAILURE
        }
    }
}

fn init_logging(config: &Config) -> Result<(), tracing_subscriber::filter::ParseError> {
    let filter = EnvFilter::try_new(&config.log_filter)?;
    let builder = tracing_subscriber::fmt().with_env_filter(filter);
    match config.log_format {
        LogFormat::Json => builder.json().init(),
        LogFormat::Text => builder.init(),
    }
    Ok(())
}

#[derive(Debug, thiserror::Error)]
enum StartError {
    #[error("network: {0}")]
    Io(#[from] std::io::Error),
    #[error("DATABASE_URL is not a valid Postgres URL: {0}")]
    DatabaseUrl(sqlx::Error),
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error(transparent)]
    Serve(#[from] ServeError),
}

async fn run(config: Config) -> Result<(), StartError> {
    let listener = TcpListener::bind(config.bind).await?;
    info!(address = %listener.local_addr()?, "listening");
    match config.database_url.clone() {
        Some(url) => {
            let options = url.0.parse().map_err(StartError::DatabaseUrl)?;
            let store = PostgresStore::connect(options).await?;
            info!("games are stored in Postgres");
            serve(listener, config, store.clone(), store, shutdown_signal()).await?;
        }
        None => {
            warn!("DATABASE_URL is unset: games and account links live in memory only");
            let games = MemoryStore::default();
            let identities = MemoryIdentityStore::default();
            serve(listener, config, games, identities, shutdown_signal()).await?;
        }
    }
    info!("shut down");
    Ok(())
}

async fn shutdown_signal() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        error!(%error, "waiting for ctrl-c failed, running until killed");
        std::future::pending::<()>().await;
    }
}
