use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, oneshot, RwLock};
use uuid::Uuid;
use tracing::{debug, info, warn};
use chrono::Timelike;

use crate::error::{ZekeError, ZekeResult};

/// Action approval status
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ApprovalStatus {
    /// Pending user approval
    Pending,
    /// Approved for this single operation
    AllowedOnce,
    /// Approved for the entire session
    AllowedSession,
    /// Approved for all operations in this project
    AllowedProject,
    /// Denied
    Denied,
}

/// Types of actions that can be performed
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ActionType {
    /// File system operations
    FileWrite { path: String },
    FileRead { path: String },
    FileDelete { path: String },
    /// Command execution
    CommandExecution { command: String },
    /// Network operations
    NetworkRequest { url: String },
    /// Git operations
    GitCommit { message: String },
    GitPush { remote: String, branch: String },
    /// Project operations
    ProjectSearch { pattern: String },
    ProjectModify { scope: String },
}

impl std::fmt::Display for ActionType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ActionType::FileWrite { path } => write!(f, "Write to file: {}", path),
            ActionType::FileRead { path } => write!(f, "Read file: {}", path),
            ActionType::FileDelete { path } => write!(f, "Delete file: {}", path),
            ActionType::CommandExecution { command } => write!(f, "Execute command: {}", command),
            ActionType::NetworkRequest { url } => write!(f, "Network request to: {}", url),
            ActionType::GitCommit { message } => write!(f, "Git commit: {}", message),
            ActionType::GitPush { remote, branch } => write!(f, "Git push to {}/{}", remote, branch),
            ActionType::ProjectSearch { pattern } => write!(f, "Search project for: {}", pattern),
            ActionType::ProjectModify { scope } => write!(f, "Modify project scope: {}", scope),
        }
    }
}

/// Action request containing all necessary context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionRequest {
    pub id: String,
    pub action_type: ActionType,
    pub context: ActionContext,
    pub timestamp: u64,
}

/// Context information for an action
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionContext {
    pub session_id: String,
    pub project_path: Option<String>,
    pub user_id: Option<String>,
    pub reasoning: Option<String>,
    pub impact_assessment: Option<String>,
}

/// Response to an action request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionResponse {
    pub request_id: String,
    pub status: ApprovalStatus,
    pub timestamp: u64,
    pub expires_at: Option<u64>,
}

/// Approval rules for automatic decision making
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalRule {
    pub name: String,
    pub action_pattern: ActionPattern,
    pub auto_approve: bool,
    pub conditions: Vec<RuleCondition>,
}

/// Pattern matching for actions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ActionPattern {
    /// Match specific action type
    ActionType(ActionType),
    /// Match by file pattern (glob)
    FilePattern(String),
    /// Match by command pattern (regex)
    CommandPattern(String),
    /// Match all actions
    All,
}

/// Conditions for rule application
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RuleCondition {
    /// Within project scope
    ProjectScope(String),
    /// Session has specific property
    SessionProperty { key: String, value: String },
    /// Time-based condition
    TimeWindow { start_hour: u8, end_hour: u8 },
}

/// Trait for action approval backends
#[async_trait]
pub trait ActionApprover: Send + Sync {
    /// Request approval for an action
    async fn request_approval(&self, request: ActionRequest) -> ZekeResult<ActionResponse>;

    /// Check if an action is automatically approved by rules
    async fn check_auto_approval(&self, request: &ActionRequest) -> ZekeResult<Option<ApprovalStatus>>;

    /// Add or update an approval rule
    async fn add_rule(&self, rule: ApprovalRule) -> ZekeResult<()>;

    /// Remove an approval rule
    async fn remove_rule(&self, rule_name: &str) -> ZekeResult<()>;

    /// List all active rules
    async fn list_rules(&self) -> ZekeResult<Vec<ApprovalRule>>;
}

/// Terminal-based action approver (for CLI usage)
pub struct TerminalApprover {
    rules: Arc<RwLock<HashMap<String, ApprovalRule>>>,
    session_approvals: Arc<RwLock<HashMap<ActionType, ApprovalStatus>>>,
    project_approvals: Arc<RwLock<HashMap<String, HashMap<ActionType, ApprovalStatus>>>>,
}

impl TerminalApprover {
    pub fn new() -> Self {
        Self {
            rules: Arc::new(RwLock::new(HashMap::new())),
            session_approvals: Arc::new(RwLock::new(HashMap::new())),
            project_approvals: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Display approval prompt to user and get response
    async fn prompt_user(&self, request: &ActionRequest) -> ZekeResult<ApprovalStatus> {
        println!("\n🛡️  Action Approval Required");
        println!("┌─────────────────────────────────────────────┐");
        println!("│ Action: {}                              │", request.action_type);
        if let Some(ref context) = request.context.reasoning {
            println!("│ Context: {}                             │", context);
        }
        if let Some(ref project) = request.context.project_path {
            println!("│ Project: {}                             │", project);
        }
        println!("└─────────────────────────────────────────────┘");
        println!();
        println!("Options:");
        println!("  [A] Allow Once    - Approve this single operation");
        println!("  [S] Allow Session - Approve for entire session");
        println!("  [P] Allow Project - Approve for all operations in this project");
        println!("  [D] Deny          - Block this operation");
        println!("  [?] Help          - Show more information");
        println!();
        print!("Your choice [A/S/P/D/?]: ");

        // For now, simulate user input (in real implementation, this would read from stdin)
        // In the actual implementation, you'd use something like:
        // let mut input = String::new();
        // std::io::stdin().read_line(&mut input)?;

        // For demo purposes, let's default to AllowedOnce
        // In production, this would be an interactive prompt
        tokio::time::sleep(std::time::Duration::from_millis(100)).await; // Simulate user thinking time

        // Simulate user choosing "Allow Once" for demo
        Ok(ApprovalStatus::AllowedOnce)
    }

    /// Check if action matches existing session/project approvals
    async fn check_existing_approvals(&self, request: &ActionRequest) -> Option<ApprovalStatus> {
        // Check session-level approvals
        {
            let session_approvals = self.session_approvals.read().await;
            if let Some(status) = session_approvals.get(&request.action_type) {
                match status {
                    ApprovalStatus::AllowedSession => return Some(ApprovalStatus::AllowedSession),
                    _ => {}
                }
            }
        }

        // Check project-level approvals
        if let Some(ref project_path) = request.context.project_path {
            let project_approvals = self.project_approvals.read().await;
            if let Some(project_map) = project_approvals.get(project_path) {
                if let Some(status) = project_map.get(&request.action_type) {
                    match status {
                        ApprovalStatus::AllowedProject => return Some(ApprovalStatus::AllowedProject),
                        ApprovalStatus::Denied => return Some(ApprovalStatus::Denied),
                        _ => {}
                    }
                }
            }
        }

        None
    }

    /// Store approval decision for future reference
    async fn store_approval(&self, request: &ActionRequest, status: ApprovalStatus) -> ZekeResult<()> {
        match status {
            ApprovalStatus::AllowedSession => {
                let mut session_approvals = self.session_approvals.write().await;
                session_approvals.insert(request.action_type.clone(), status);
            }
            ApprovalStatus::AllowedProject => {
                if let Some(ref project_path) = request.context.project_path {
                    let mut project_approvals = self.project_approvals.write().await;
                    let project_map = project_approvals.entry(project_path.clone()).or_insert_with(HashMap::new);
                    project_map.insert(request.action_type.clone(), status);
                }
            }
            _ => {} // Don't store temporary approvals
        }
        Ok(())
    }
}

#[async_trait]
impl ActionApprover for TerminalApprover {
    async fn request_approval(&self, request: ActionRequest) -> ZekeResult<ActionResponse> {
        debug!("Processing approval request for: {}", request.action_type);

        // First check auto-approval rules
        if let Some(auto_status) = self.check_auto_approval(&request).await? {
            info!("Auto-approved action: {} -> {:?}", request.action_type, auto_status);
            return Ok(ActionResponse {
                request_id: request.id,
                status: auto_status,
                timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
                expires_at: None,
            });
        }

        // Check existing approvals (session/project level)
        if let Some(existing_status) = self.check_existing_approvals(&request).await {
            debug!("Found existing approval: {} -> {:?}", request.action_type, existing_status);
            return Ok(ActionResponse {
                request_id: request.id,
                status: existing_status,
                timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
                expires_at: None,
            });
        }

        // Prompt user for approval
        let status = self.prompt_user(&request).await?;

        // Store the decision for future reference
        self.store_approval(&request, status.clone()).await?;

        info!("User approval decision: {} -> {:?}", request.action_type, status);

        Ok(ActionResponse {
            request_id: request.id,
            status,
            timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            expires_at: None,
        })
    }

    async fn check_auto_approval(&self, request: &ActionRequest) -> ZekeResult<Option<ApprovalStatus>> {
        let rules = self.rules.read().await;

        for rule in rules.values() {
            if self.action_matches_pattern(&request.action_type, &rule.action_pattern) {
                if self.check_rule_conditions(request, &rule.conditions).await {
                    if rule.auto_approve {
                        debug!("Auto-approved by rule: {}", rule.name);
                        return Ok(Some(ApprovalStatus::AllowedOnce));
                    } else {
                        debug!("Auto-denied by rule: {}", rule.name);
                        return Ok(Some(ApprovalStatus::Denied));
                    }
                }
            }
        }

        Ok(None)
    }

    async fn add_rule(&self, rule: ApprovalRule) -> ZekeResult<()> {
        let mut rules = self.rules.write().await;
        rules.insert(rule.name.clone(), rule);
        Ok(())
    }

    async fn remove_rule(&self, rule_name: &str) -> ZekeResult<()> {
        let mut rules = self.rules.write().await;
        rules.remove(rule_name);
        Ok(())
    }

    async fn list_rules(&self) -> ZekeResult<Vec<ApprovalRule>> {
        let rules = self.rules.read().await;
        Ok(rules.values().cloned().collect())
    }
}

impl TerminalApprover {
    fn action_matches_pattern(&self, action: &ActionType, pattern: &ActionPattern) -> bool {
        match pattern {
            ActionPattern::All => true,
            ActionPattern::ActionType(pattern_action) => {
                std::mem::discriminant(action) == std::mem::discriminant(pattern_action)
            }
            ActionPattern::FilePattern(glob) => {
                match action {
                    ActionType::FileWrite { path } |
                    ActionType::FileRead { path } |
                    ActionType::FileDelete { path } => {
                        // Simple glob matching (in production, use a proper glob library)
                        path.contains(&glob.replace("*", ""))
                    }
                    _ => false,
                }
            }
            ActionPattern::CommandPattern(regex) => {
                match action {
                    ActionType::CommandExecution { command } => {
                        // Simple pattern matching (in production, use regex library)
                        command.contains(regex)
                    }
                    _ => false,
                }
            }
        }
    }

    async fn check_rule_conditions(&self, request: &ActionRequest, conditions: &[RuleCondition]) -> bool {
        for condition in conditions {
            match condition {
                RuleCondition::ProjectScope(scope) => {
                    if let Some(ref project_path) = request.context.project_path {
                        if !project_path.contains(scope) {
                            return false;
                        }
                    } else {
                        return false;
                    }
                }
                RuleCondition::SessionProperty { key, value } => {
                    // For now, we don't have session properties implemented
                    // In production, this would check session metadata
                    continue;
                }
                RuleCondition::TimeWindow { start_hour, end_hour } => {
                    let now = chrono::Local::now();
                    let current_hour = now.hour() as u8;
                    if current_hour < *start_hour || current_hour > *end_hour {
                        return false;
                    }
                }
            }
        }
        true
    }
}

/// Action manager that coordinates approval and execution
pub struct ActionManager {
    approver: Arc<dyn ActionApprover>,
    request_sender: mpsc::UnboundedSender<ActionRequest>,
    response_receivers: Arc<RwLock<HashMap<String, oneshot::Sender<ActionResponse>>>>,
}

impl ActionManager {
    pub fn new(approver: Arc<dyn ActionApprover>) -> Self {
        let (request_sender, mut request_receiver) = mpsc::unbounded_channel::<ActionRequest>();
        let response_receivers = Arc::new(RwLock::new(HashMap::<String, oneshot::Sender<ActionResponse>>::new()));

        let approver_clone = approver.clone();
        let receivers_clone = response_receivers.clone();

        // Spawn background task to process approval requests
        tokio::spawn(async move {
            while let Some(request) = request_receiver.recv().await {
                let response = match approver_clone.request_approval(request.clone()).await {
                    Ok(response) => response,
                    Err(e) => {
                        warn!("Approval request failed: {}", e);
                        ActionResponse {
                            request_id: request.id,
                            status: ApprovalStatus::Denied,
                            timestamp: SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs(),
                            expires_at: None,
                        }
                    }
                };

                // Send response back to waiting caller
                let mut receivers = receivers_clone.write().await;
                if let Some(sender) = receivers.remove(&response.request_id) {
                    let _ = sender.send(response);
                }
            }
        });

        Self {
            approver,
            request_sender,
            response_receivers,
        }
    }

    /// Request approval for an action and wait for response
    pub async fn request_approval(&self, action_type: ActionType, context: ActionContext) -> ZekeResult<ApprovalStatus> {
        let request_id = Uuid::new_v4().to_string();
        let (response_sender, response_receiver) = oneshot::channel();

        // Store the response channel
        {
            let mut receivers = self.response_receivers.write().await;
            receivers.insert(request_id.clone(), response_sender);
        }

        let request = ActionRequest {
            id: request_id,
            action_type,
            context,
            timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
        };

        // Send the request
        self.request_sender.send(request)?;

        // Wait for response
        let response = response_receiver.await
            .map_err(|_| ZekeError::provider("Approval request cancelled"))?;

        Ok(response.status)
    }

    /// Add approval rule
    pub async fn add_rule(&self, rule: ApprovalRule) -> ZekeResult<()> {
        self.approver.add_rule(rule).await
    }

    /// Remove approval rule
    pub async fn remove_rule(&self, rule_name: &str) -> ZekeResult<()> {
        self.approver.remove_rule(rule_name).await
    }

    /// List all rules
    pub async fn list_rules(&self) -> ZekeResult<Vec<ApprovalRule>> {
        self.approver.list_rules().await
    }
}

/// Helper functions for creating common action types
impl ActionType {
    pub fn file_write<P: Into<String>>(path: P) -> Self {
        ActionType::FileWrite { path: path.into() }
    }

    pub fn file_read<P: Into<String>>(path: P) -> Self {
        ActionType::FileRead { path: path.into() }
    }

    pub fn command_exec<C: Into<String>>(command: C) -> Self {
        ActionType::CommandExecution { command: command.into() }
    }

    pub fn git_commit<M: Into<String>>(message: M) -> Self {
        ActionType::GitCommit { message: message.into() }
    }
}

/// Helper functions for creating approval rules
impl ApprovalRule {
    pub fn allow_file_reads_in_project<P: Into<String>>(project_path: P) -> Self {
        Self {
            name: "auto_allow_project_reads".to_string(),
            action_pattern: ActionPattern::FilePattern("*.rs".to_string()),
            auto_approve: true,
            conditions: vec![RuleCondition::ProjectScope(project_path.into())],
        }
    }

    pub fn deny_dangerous_commands() -> Self {
        Self {
            name: "deny_dangerous_commands".to_string(),
            action_pattern: ActionPattern::CommandPattern("rm -rf".to_string()),
            auto_approve: false,
            conditions: vec![],
        }
    }
}