// Agent system - specialized AI agents for different development tasks
pub mod blockchain;
pub mod smartcontract;
pub mod network;
pub mod security;
pub mod subagents;

use crate::error::ZekeResult;
use std::sync::Arc;

pub use subagents::{SubagentManager, SubagentType, SubagentContext, CodeSnippet};

pub trait Agent {
    fn name(&self) -> &str;
    fn capabilities(&self) -> Vec<&str>;
}

pub struct AgentManager {
    subagent_manager: Option<Arc<SubagentManager>>,
}

impl AgentManager {
    pub fn new() -> Self {
        Self {
            subagent_manager: None,
        }
    }

    pub fn with_subagent_manager(subagent_manager: Arc<SubagentManager>) -> Self {
        Self {
            subagent_manager: Some(subagent_manager),
        }
    }

    pub async fn execute_command(&self, agent_type: &str, command: &str) -> ZekeResult<String> {
        if let Some(subagent_manager) = &self.subagent_manager {
            let agent_type = agent_type.parse::<SubagentType>()?;
            let context = SubagentContext {
                files: Vec::new(),
                code_snippets: Vec::new(),
                additional_context: std::collections::HashMap::new(),
                requirements: Vec::new(),
            };

            subagent_manager
                .execute_task_immediately(agent_type, command.to_string(), context)
                .await
        } else {
            Ok("Subagent system not initialized".to_string())
        }
    }

    pub async fn list_available_agents(&self) -> Vec<(String, String)> {
        if let Some(subagent_manager) = &self.subagent_manager {
            subagent_manager
                .list_available_agents()
                .await
                .into_iter()
                .map(|(agent_type, description)| (format!("{:?}", agent_type), description.to_string()))
                .collect()
        } else {
            Vec::new()
        }
    }
}