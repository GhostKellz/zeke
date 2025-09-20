use clap::Parser;
use tracing::{info, error};
use std::process;

mod providers;
mod agents;
mod cli;
mod api;
mod streaming;
mod git;
mod config;
mod error;
mod auth;
mod tools;
mod mcp;
mod actions;

use cli::{Args, Commands};
use error::ZekeResult;


#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    if let Err(e) = run(args).await {
        error!("Error: {}", e);
        process::exit(1);
    }
}

async fn run(args: Args) -> ZekeResult<()> {
    info!("⚡ ZEKE v{} - The AI Dev Companion", env!("CARGO_PKG_VERSION"));

    match args.command {
        Commands::Chat { message } => {
            cli::commands::chat::handle_chat(message).await
        }
        Commands::Ask { question } => {
            cli::commands::ask::handle_ask(question).await
        }
        Commands::Provider { action } => {
            cli::commands::provider::handle_provider(action).await
        }
        Commands::Router { action } => {
            cli::commands::router::handle_router(action).await
        }
        Commands::Server { host, port } => {
            api::start_api_server(&host, port).await
        }
        Commands::Tui => {
            cli::tui::run_tui().await
        }
        Commands::Explain { code, language } => {
            info!("📖 Explaining code (language: {:?})", language);
            println!("📖 Code explanation: {}", code);
            Ok(())
        }
        Commands::Generate { description, language } => {
            info!("✨ Generating code (language: {:?})", language);
            println!("✨ Code generation: {}", description);
            Ok(())
        }
        Commands::Debug { error_description } => {
            info!("🔧 Debugging error");
            println!("🔧 Debug help for: {}", error_description);
            Ok(())
        }
        Commands::Analyze { file_path, analysis_type } => {
            info!("🔍 Analyzing file: {} (type: {:?})", file_path, analysis_type);
            println!("🔍 Analysis of {} not yet implemented", file_path);
            Ok(())
        }
        Commands::File { action } => {
            info!("📁 File operation: {:?}", action);
            println!("📁 File operations not yet implemented");
            Ok(())
        }
        Commands::Git { action } => {
            info!("🔗 Git operation: {:?}", action);
            println!("🔗 Git operations not yet implemented");
            Ok(())
        }
        Commands::Agent { agent_type } => {
            info!("🤖 Agent operation: {:?}", agent_type);
            println!("🤖 Agent system not yet implemented");
            Ok(())
        }
        Commands::Auth { action } => {
            info!("🔐 Auth operation: {:?}", action);
            println!("🔐 Authentication not yet implemented");
            Ok(())
        }
    }
}
