use std::{path::PathBuf, env};

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(author, version, about, long_about=None, arg_required_else_help = true)]
struct Cli {
  #[command(subcommand)]
  command: Option<Commands>
}

#[derive(Subcommand)]
enum Commands {
  Init{
    path: Option<PathBuf>
  },
  Build,
  Test,
  Run
}


fn main() -> Result<()> {
  let cli = Cli::parse();

  match &cli.command {
    Some(Commands::Init {path}) => {
      if let Some(p) = path {
        // initialize at relative path
        println!("init at {}/{}", env::current_dir()?.to_str().unwrap(), p.to_str().unwrap());
      } else {
        // initialize in cwd
        println!("init at {}", env::current_dir()?.to_str().unwrap())
      }
    },
    _ => {}
  }

  Ok(())
}
