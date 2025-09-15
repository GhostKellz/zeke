use clap::{Parser, Subcommand};

pub mod commands;
pub mod tui;

#[derive(Parser)]
#[command(name = "zeke")]
#[command(about = "⚡ ZEKE - The AI Dev Companion")]
#[command(long_about = "A next-generation AI dev companion with multi-provider support, Neovim integration, and advanced agent capabilities")]
#[command(version)]
pub struct Args {
    #[command(subcommand)]
    pub command: Commands,

    #[arg(short, long, global = true)]
    pub verbose: bool,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Chat with AI
    Chat {
        /// Message to send to AI
        message: String,
    },

    /// Ask AI a question
    Ask {
        /// Question to ask AI
        question: String,
    },

    /// Manage AI providers
    Provider {
        #[command(subcommand)]
        action: ProviderAction,
    },

    /// Start API server for external integrations
    Server {
        /// Host to bind to
        #[arg(long, default_value = "127.0.0.1")]
        host: String,
        /// Port to bind to
        #[arg(long, default_value = "7777")]
        port: u16,
    },

    /// Launch TUI interface
    Tui,

    /// Explain code
    Explain {
        /// Code to explain
        code: String,
        /// Programming language (optional)
        #[arg(short, long)]
        language: Option<String>,
    },

    /// Generate code
    Generate {
        /// Description of what to generate
        description: String,
        /// Programming language (optional)
        #[arg(short, long)]
        language: Option<String>,
    },

    /// Debug code/error
    Debug {
        /// Error description
        error_description: String,
    },

    /// Analyze code file
    Analyze {
        /// File path to analyze
        file_path: String,
        /// Analysis type
        #[arg(value_enum)]
        analysis_type: AnalysisType,
    },

    /// File operations
    File {
        #[command(subcommand)]
        action: FileAction,
    },

    /// Git operations
    Git {
        #[command(subcommand)]
        action: GitAction,
    },

    /// Agent system
    Agent {
        #[command(subcommand)]
        agent_type: AgentType,
    },

    /// Authentication
    Auth {
        #[command(subcommand)]
        action: AuthAction,
    },
}

#[derive(Subcommand)]
pub enum ProviderAction {
    /// Switch to a different provider
    Switch {
        /// Provider name
        provider: String,
    },
    /// Show provider status
    Status,
    /// List available providers
    List,
}


#[derive(clap::ValueEnum, Clone, Debug)]
pub enum AnalysisType {
    Performance,
    Security,
    Style,
    Quality,
    Architecture,
}

#[derive(Subcommand, Debug)]
pub enum FileAction {
    /// Read a file
    Read {
        file_path: String,
    },
    /// Write to a file
    Write {
        file_path: String,
        content: String,
    },
    /// Edit file with AI
    Edit {
        file_path: String,
        instruction: String,
    },
}

#[derive(Subcommand, Debug)]
pub enum GitAction {
    /// Show git status
    Status,
    /// Show git diff
    Diff {
        file_path: Option<String>,
    },
    /// Add files to git
    Add {
        file_path: String,
    },
    /// Commit changes
    Commit {
        message: String,
    },
    /// Show current branch
    Branch,
}

#[derive(Subcommand, Debug)]
pub enum AgentType {
    /// Blockchain operations
    Blockchain {
        #[command(subcommand)]
        command: BlockchainCommand,
    },
    /// Smart contract operations
    SmartContract {
        #[command(subcommand)]
        command: SmartContractCommand,
    },
    /// Network operations
    Network {
        #[command(subcommand)]
        command: NetworkCommand,
    },
    /// Security operations
    Security {
        #[command(subcommand)]
        command: SecurityCommand,
    },
}

#[derive(Subcommand, Debug)]
pub enum BlockchainCommand {
    Status,
    Balance { address: String },
}

#[derive(Subcommand, Debug)]
pub enum SmartContractCommand {
    Deploy { contract_path: String },
    Call { address: String, method: String },
}

#[derive(Subcommand, Debug)]
pub enum NetworkCommand {
    Scan { target: String },
    Ping { host: String },
}

#[derive(Subcommand, Debug)]
pub enum SecurityCommand {
    Scan { target: String },
    Audit { file_path: String },
}

#[derive(Subcommand, Debug)]
pub enum AuthAction {
    /// List supported providers
    List,
    /// Authenticate with provider
    Login {
        provider: String,
        token: String,
    },
    /// Test authentication
    Test {
        provider: String,
    },
}