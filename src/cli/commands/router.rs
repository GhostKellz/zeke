use clap::Subcommand;
use std::sync::Arc;
use tracing::{info, error};

use crate::config::ConfigManager;
use crate::error::ZekeResult;
use crate::providers::router::{ProviderRouter, ProviderMode};
use crate::providers::{ChatRequest, ChatMessage};

#[derive(Debug, Subcommand)]
pub enum RouterAction {
    /// Show current router status and configuration
    Status,
    /// Test router connectivity
    Test,
    /// Switch router mode
    Switch {
        /// Provider mode: direct, ghostllm, auto
        mode: String,
    },
    /// List available providers
    List,
    /// Test a simple chat request
    Chat {
        /// Message to send
        message: String,
    },
}

pub async fn handle_router(action: RouterAction) -> ZekeResult<()> {
    let config_manager = ConfigManager::new();
    let zeke_config = config_manager.load_config().await?;

    let mut router = ProviderRouter::from_zeke_config(&zeke_config).await?;

    match action {
        RouterAction::Status => {
            show_router_status(&router).await?;
        }
        RouterAction::Test => {
            test_router_connectivity(&router).await?;
        }
        RouterAction::Switch { mode } => {
            switch_router_mode(&mut router, &mode).await?;
        }
        RouterAction::List => {
            list_available_providers(&router).await?;
        }
        RouterAction::Chat { message } => {
            test_router_chat(&router, &message).await?;
        }
    }

    Ok(())
}

async fn show_router_status(router: &ProviderRouter) -> ZekeResult<()> {
    info!("🔄 Provider Router Status");

    let config = router.get_config();
    let active_mode = router.get_active_mode();

    println!("📊 Router Configuration:");
    println!("  Active Mode: {:?}", active_mode);
    println!("  Configured Mode: {:?}", config.mode);
    println!("  GhostLLM URL: {}", config.ghostllm.base_url);
    println!("  Routing Enabled: {}", config.ghostllm.enable_routing);
    println!("  Consent Enabled: {}", config.ghostllm.enable_consent);
    println!("  Session Persistence: {}", config.ghostllm.session_persistence);
    println!("  Cost Tracking: {}", config.ghostllm.cost_tracking);

    // Show provider status
    match router.get_provider_status().await {
        Ok(status) => {
            println!("\n🏥 Provider Health:");
            for (provider, is_healthy) in status {
                let status_icon = if is_healthy { "✅" } else { "❌" };
                println!("  {} {}", status_icon, provider);
            }
        }
        Err(e) => {
            error!("Failed to get provider status: {}", e);
        }
    }

    Ok(())
}

async fn test_router_connectivity(router: &ProviderRouter) -> ZekeResult<()> {
    info!("🔍 Testing router connectivity");

    let status = router.get_provider_status().await?;

    if status.is_empty() {
        println!("❌ No providers available");
        return Ok(());
    }

    println!("🧪 Connectivity Test Results:");
    for (provider, is_healthy) in status {
        let result = if is_healthy { "PASS" } else { "FAIL" };
        let icon = if is_healthy { "✅" } else { "❌" };
        println!("  {} {} - {}", icon, provider, result);
    }

    Ok(())
}

async fn switch_router_mode(router: &mut ProviderRouter, mode_str: &str) -> ZekeResult<()> {
    let mode: ProviderMode = mode_str.parse()?;

    info!("🔄 Switching router mode to: {:?}", mode);

    match router.switch_mode(mode.clone()).await {
        Ok(()) => {
            println!("✅ Successfully switched to mode: {:?}", mode);
            show_router_status(router).await?;
        }
        Err(e) => {
            error!("Failed to switch mode: {}", e);
            println!("❌ Failed to switch to mode: {:?} - {}", mode, e);
        }
    }

    Ok(())
}

async fn list_available_providers(router: &ProviderRouter) -> ZekeResult<()> {
    info!("📋 Listing available providers");

    let providers = router.list_available_providers().await;

    if providers.is_empty() {
        println!("❌ No providers available");
        return Ok(());
    }

    println!("📋 Available Providers:");
    for provider in providers {
        println!("  • {}", provider);
    }

    Ok(())
}

async fn test_router_chat(router: &ProviderRouter, message: &str) -> ZekeResult<()> {
    info!("💬 Testing chat with message: {}", message);

    let request = ChatRequest {
        messages: vec![ChatMessage {
            role: "user".to_string(),
            content: message.to_string(),
        }],
        model: None,
        temperature: Some(0.7),
        max_tokens: Some(150),
        stream: Some(false),
    };

    println!("💬 Sending test message: \"{}\"", message);
    println!("⏳ Waiting for response...");

    match router.chat_completion(&request).await {
        Ok(response) => {
            println!("✅ Response received:");
            println!("  Provider: {}", response.provider);
            println!("  Model: {}", response.model);
            println!("  Content: {}", response.content);

            if let Some(usage) = response.usage {
                println!("  Usage: {} tokens ({} prompt + {} completion)",
                    usage.total_tokens, usage.prompt_tokens, usage.completion_tokens);
            }
        }
        Err(e) => {
            error!("Chat test failed: {}", e);
            println!("❌ Chat test failed: {}", e);
        }
    }

    Ok(())
}