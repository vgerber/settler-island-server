//! Generates the Godot client of the Settler Island protocol: `client/schema.json` from the protocol
//! types and one GDScript class per schema type under `client/godot/settler_island_api/`.

pub mod gdscript;
pub mod model;

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use schemars::generate::SchemaSettings;
use serde_json::{json, Value};
use settler_island_protocol::{ClientMessage, ServerMessage};

pub const SCHEMA_FILE: &str = "schema.json";
pub const API_DIRECTORY: &str = "godot/settler_island_api";

#[derive(Debug, thiserror::Error)]
pub enum GenerateError {
    #[error(transparent)]
    Model(#[from] model::ModelError),
    #[error(transparent)]
    Render(#[from] gdscript::RenderError),
    #[error("{path}: {source}")]
    Io { path: PathBuf, source: io::Error },
}

fn io_error(path: &Path) -> impl FnOnce(io::Error) -> GenerateError + '_ {
    move |source| GenerateError::Io {
        path: path.to_path_buf(),
        source,
    }
}

/// `client/` next to this crate in the repository.
pub fn default_client_directory() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("client")
}

/// The JSON Schema of every message in both directions, definitions under `$defs`.
pub fn protocol_schema() -> Value {
    let mut generator = SchemaSettings::draft2020_12().into_generator();
    let client = generator.subschema_for::<ClientMessage>();
    let server = generator.subschema_for::<ServerMessage>();
    json!({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Settler Island protocol",
        "description": "A WebSocket text frame holds one ClientMessage (client to server) or one ServerMessage (server to client).",
        "oneOf": [client, server],
        "$defs": generator.definitions(),
    })
}

/// Every generated file by its path relative to the client directory.
pub fn generate(schema: &Value) -> Result<BTreeMap<PathBuf, String>, GenerateError> {
    let model = model::Model::from_schema(schema)?;
    let classes = gdscript::render(&model)?;
    let mut files = BTreeMap::new();
    // Serializing a `Value` cannot fail.
    let mut schema_text = serde_json::to_string_pretty(schema).unwrap_or_default();
    schema_text.push('\n');
    files.insert(PathBuf::from(SCHEMA_FILE), schema_text);
    for (name, content) in classes {
        files.insert(Path::new(API_DIRECTORY).join(name), content);
    }
    Ok(files)
}

/// Generated `.gd` files on disk that the current schema no longer produces.
fn leftover_scripts(
    client_directory: &Path,
    files: &BTreeMap<PathBuf, String>,
) -> Result<Vec<PathBuf>, GenerateError> {
    let directory = client_directory.join(API_DIRECTORY);
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(io_error(&directory)(error)),
    };
    let mut leftovers = Vec::new();
    for entry in entries {
        let path = entry.map_err(io_error(&directory))?.path();
        let Some(name) = path.file_name() else {
            continue;
        };
        let relative = Path::new(API_DIRECTORY).join(name);
        let is_script = path.extension().is_some_and(|extension| extension == "gd");
        if is_script && !files.contains_key(&relative) {
            leftovers.push(relative);
        }
    }
    leftovers.sort();
    Ok(leftovers)
}

/// Writes every file and deletes scripts of types that no longer exist.
pub fn write(
    client_directory: &Path,
    files: &BTreeMap<PathBuf, String>,
) -> Result<(), GenerateError> {
    for leftover in leftover_scripts(client_directory, files)? {
        let path = client_directory.join(leftover);
        fs::remove_file(&path).map_err(io_error(&path))?;
    }
    for (relative, content) in files {
        let path = client_directory.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(io_error(parent))?;
        }
        fs::write(&path, content).map_err(io_error(&path))?;
    }
    Ok(())
}

/// Paths that are missing, differ, or should not exist; empty when the output is current.
pub fn stale_paths(
    client_directory: &Path,
    files: &BTreeMap<PathBuf, String>,
) -> Result<Vec<PathBuf>, GenerateError> {
    let mut stale = Vec::new();
    for (relative, content) in files {
        let path = client_directory.join(relative);
        let current = match fs::read_to_string(&path) {
            Ok(current) => Some(current),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(io_error(&path)(error)),
        };
        if current.as_ref() != Some(content) {
            stale.push(relative.clone());
        }
    }
    stale.extend(leftover_scripts(client_directory, files)?);
    Ok(stale)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn committed_client_matches_the_protocol() {
        let files = generate(&protocol_schema()).unwrap();
        let stale = stale_paths(&default_client_directory(), &files).unwrap();

        assert!(
            stale.is_empty(),
            "client/ is stale, run `cargo run -p settler_island_client_generator`: {stale:?}"
        );
    }

    #[test]
    fn every_protocol_message_gets_a_class_and_a_send_function_or_signal() {
        let files = generate(&protocol_schema()).unwrap();
        let client = &files[&Path::new(API_DIRECTORY).join("SiClient.gd")];

        for expected in [
            "func send_act(action: SiAction) -> int:",
            "func send_create_lobby(",
            "signal game_update_received(message: SiServerMessageGameUpdate)",
            "signal error_received(message: SiServerMessageError)",
        ] {
            assert!(client.contains(expected), "missing {expected:?}");
        }
        assert!(files.contains_key(&Path::new(API_DIRECTORY).join("SiPlayerView.gd")));
        assert!(!files.contains_key(&Path::new(API_DIRECTORY).join("SiTileId.gd")));
    }
}
