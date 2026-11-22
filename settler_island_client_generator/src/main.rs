//! `cargo run -p settler_island_client_generator [-- --check] [--out <client directory>]`

use std::path::PathBuf;
use std::process::ExitCode;

use settler_island_client_generator::{
    default_client_directory, generate, protocol_schema, stale_paths, write, GenerateError,
};

struct Arguments {
    check: bool,
    client_directory: PathBuf,
}

fn parse_arguments() -> Result<Arguments, String> {
    let mut arguments = Arguments {
        check: false,
        client_directory: default_client_directory(),
    };
    let mut raw = std::env::args().skip(1);
    while let Some(argument) = raw.next() {
        match argument.as_str() {
            "--check" => arguments.check = true,
            "--out" => {
                let directory = raw.next().ok_or("--out needs a directory")?;
                arguments.client_directory = PathBuf::from(directory);
            }
            other => return Err(format!("unknown argument {other:?}")),
        }
    }
    Ok(arguments)
}

fn run(arguments: &Arguments) -> Result<bool, GenerateError> {
    let files = generate(&protocol_schema())?;
    if !arguments.check {
        write(&arguments.client_directory, &files)?;
        println!(
            "wrote {} files to {}",
            files.len(),
            arguments.client_directory.display()
        );
        return Ok(true);
    }
    let stale = stale_paths(&arguments.client_directory, &files)?;
    for path in &stale {
        eprintln!("stale: {}", path.display());
    }
    Ok(stale.is_empty())
}

fn main() -> ExitCode {
    let arguments = match parse_arguments() {
        Ok(arguments) => arguments,
        Err(message) => {
            eprintln!("{message}\nusage: settler_island_client_generator [--check] [--out <dir>]");
            return ExitCode::from(2);
        }
    };
    match run(&arguments) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => {
            eprintln!("client output is stale, run `cargo run -p settler_island_client_generator`");
            ExitCode::FAILURE
        }
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(2)
        }
    }
}
