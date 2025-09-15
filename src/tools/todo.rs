use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Copy)]
pub enum TaskStatus {
    Pending,
    InProgress,
    Completed,
    Blocked,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub content: String,
    pub active_form: String,
    pub status: TaskStatus,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
    pub priority: u8, // 1-5, 5 being highest
    pub tags: Vec<String>,
    pub dependencies: Vec<String>, // Task IDs this task depends on
    pub parent_task: Option<String>, // For subtasks
    pub assignee: Option<String>,
    pub estimated_hours: Option<f32>,
    pub actual_hours: Option<f32>,
}

impl Task {
    pub fn new(content: String, active_form: String) -> Self {
        let now = chrono::Utc::now();
        Self {
            id: Uuid::new_v4().to_string(),
            content,
            active_form,
            status: TaskStatus::Pending,
            created_at: now,
            updated_at: now,
            completed_at: None,
            priority: 3, // Default medium priority
            tags: Vec::new(),
            dependencies: Vec::new(),
            parent_task: None,
            assignee: None,
            estimated_hours: None,
            actual_hours: None,
        }
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.priority = priority.clamp(1, 5);
        self
    }

    pub fn with_tags(mut self, tags: Vec<String>) -> Self {
        self.tags = tags;
        self
    }

    pub fn with_dependencies(mut self, dependencies: Vec<String>) -> Self {
        self.dependencies = dependencies;
        self
    }

    pub fn set_status(&mut self, status: TaskStatus) {
        self.status = status;
        self.updated_at = chrono::Utc::now();

        if status == TaskStatus::Completed {
            self.completed_at = Some(chrono::Utc::now());
        }
    }

    pub fn can_start(&self, task_manager: &TaskManager) -> bool {
        // Check if all dependencies are completed
        for dep_id in &self.dependencies {
            if let Some(dep_task) = task_manager.get_task(dep_id) {
                if dep_task.status != TaskStatus::Completed {
                    return false;
                }
            } else {
                // Dependency doesn't exist, can't start
                return false;
            }
        }
        true
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskList {
    pub name: String,
    pub description: Option<String>,
    pub tasks: Vec<Task>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

impl TaskList {
    pub fn new(name: String) -> Self {
        let now = chrono::Utc::now();
        Self {
            name,
            description: None,
            tasks: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }

    pub fn add_task(&mut self, task: Task) {
        self.tasks.push(task);
        self.updated_at = chrono::Utc::now();
    }

    pub fn get_task_mut(&mut self, task_id: &str) -> Option<&mut Task> {
        self.tasks.iter_mut().find(|t| t.id == task_id)
    }

    pub fn remove_task(&mut self, task_id: &str) -> bool {
        if let Some(pos) = self.tasks.iter().position(|t| t.id == task_id) {
            self.tasks.remove(pos);
            self.updated_at = chrono::Utc::now();
            true
        } else {
            false
        }
    }

    pub fn get_tasks_by_status(&self, status: TaskStatus) -> Vec<&Task> {
        self.tasks.iter().filter(|t| t.status == status).collect()
    }

    pub fn get_available_tasks(&self, task_manager: &TaskManager) -> Vec<&Task> {
        self.tasks
            .iter()
            .filter(|t| t.status == TaskStatus::Pending && t.can_start(task_manager))
            .collect()
    }
}

pub struct TaskManager {
    current_list: RwLock<TaskList>,
    task_index: RwLock<HashMap<String, usize>>, // task_id -> index in current list
}

impl TaskManager {
    pub fn new() -> Self {
        Self {
            current_list: RwLock::new(TaskList::new("Default".to_string())),
            task_index: RwLock::new(HashMap::new()),
        }
    }

    pub fn with_list(list: TaskList) -> Self {
        let mut task_index = HashMap::new();
        for (index, task) in list.tasks.iter().enumerate() {
            task_index.insert(task.id.clone(), index);
        }

        Self {
            current_list: RwLock::new(list),
            task_index: RwLock::new(task_index),
        }
    }

    pub async fn add_task(&self, task: Task) -> ZekeResult<String> {
        let mut list = self.current_list.write().await;
        let mut index = self.task_index.write().await;

        // Validate dependencies exist
        for dep_id in &task.dependencies {
            if !index.contains_key(dep_id) {
                return Err(ZekeError::invalid_input(format!("Dependency task '{}' not found", dep_id)));
            }
        }

        let task_id = task.id.clone();
        let task_index_value = list.tasks.len();

        list.add_task(task);
        index.insert(task_id.clone(), task_index_value);

        Ok(task_id)
    }

    pub async fn update_task_status(&self, task_id: &str, status: TaskStatus) -> ZekeResult<()> {
        let mut list = self.current_list.write().await;

        // First, find the task and validate status transitions
        let task_index = list.tasks.iter().position(|t| t.id == task_id)
            .ok_or_else(|| ZekeError::invalid_input(format!("Task '{}' not found", task_id)))?;

        let current_status = list.tasks[task_index].status;

        // Validate status transition
        match (&current_status, &status) {
            (TaskStatus::Completed, _) => {
                return Err(ZekeError::invalid_input("Cannot change status of completed task"));
            }
            (TaskStatus::Cancelled, _) => {
                return Err(ZekeError::invalid_input("Cannot change status of cancelled task"));
            }
            (_, TaskStatus::InProgress) => {
                // Only one task can be in progress at a time
                let other_in_progress = list.tasks.iter()
                    .filter(|t| t.id != task_id && t.status == TaskStatus::InProgress)
                    .count();
                if other_in_progress > 0 {
                    return Err(ZekeError::invalid_input("Another task is already in progress. Complete it first."));
                }
            }
            _ => {}
        }

        // Now safely update the task
        list.tasks[task_index].set_status(status);
        Ok(())
    }

    pub async fn get_current_task(&self) -> Option<Task> {
        let list = self.current_list.read().await;
        list.get_tasks_by_status(TaskStatus::InProgress).first().map(|t| (*t).clone())
    }

    pub async fn get_task_list(&self) -> TaskList {
        self.current_list.read().await.clone()
    }

    pub fn get_task(&self, _task_id: &str) -> Option<Task> {
        // Note: This is a simplified synchronous version for dependency checking
        // In a real implementation, you'd want proper async handling
        unimplemented!("Use async methods for task access")
    }

    pub async fn get_task_async(&self, task_id: &str) -> Option<Task> {
        let list = self.current_list.read().await;
        list.tasks.iter().find(|t| t.id == task_id).cloned()
    }

    pub async fn remove_task(&self, task_id: &str) -> ZekeResult<()> {
        let mut list = self.current_list.write().await;
        let mut index = self.task_index.write().await;

        if list.remove_task(task_id) {
            index.remove(task_id);

            // Rebuild index to account for shifted positions
            index.clear();
            for (i, task) in list.tasks.iter().enumerate() {
                index.insert(task.id.clone(), i);
            }

            Ok(())
        } else {
            Err(ZekeError::invalid_input(format!("Task '{}' not found", task_id)))
        }
    }

    pub async fn get_progress_summary(&self) -> TaskProgressSummary {
        let list = self.current_list.read().await;

        let total = list.tasks.len();
        let completed = list.get_tasks_by_status(TaskStatus::Completed).len();
        let in_progress = list.get_tasks_by_status(TaskStatus::InProgress).len();
        let pending = list.get_tasks_by_status(TaskStatus::Pending).len();
        let blocked = list.get_tasks_by_status(TaskStatus::Blocked).len();
        let cancelled = list.get_tasks_by_status(TaskStatus::Cancelled).len();

        let completion_percentage = if total > 0 {
            (completed as f32 / total as f32) * 100.0
        } else {
            0.0
        };

        TaskProgressSummary {
            total,
            completed,
            in_progress,
            pending,
            blocked,
            cancelled,
            completion_percentage,
        }
    }

    pub async fn set_task_list(&self, new_list: TaskList) -> ZekeResult<()> {
        let mut list = self.current_list.write().await;
        let mut index = self.task_index.write().await;

        // Rebuild task index
        index.clear();
        for (i, task) in new_list.tasks.iter().enumerate() {
            index.insert(task.id.clone(), i);
        }

        *list = new_list;
        Ok(())
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskProgressSummary {
    pub total: usize,
    pub completed: usize,
    pub in_progress: usize,
    pub pending: usize,
    pub blocked: usize,
    pub cancelled: usize,
    pub completion_percentage: f32,
}

pub struct TodoTool {
    manager: TaskManager,
}

impl TodoTool {
    pub fn new() -> Self {
        Self {
            manager: TaskManager::new(),
        }
    }

    pub fn with_manager(manager: TaskManager) -> Self {
        Self { manager }
    }

    async fn handle_add_task(&self, content: String, active_form: String, priority: Option<u8>) -> ZekeResult<ToolOutput> {
        let task = Task::new(content, active_form)
            .with_priority(priority.unwrap_or(3));

        let task_id = self.manager.add_task(task).await?;

        Ok(ToolOutput {
            success: true,
            content: format!("Task added with ID: {}", task_id),
            error: None,
        })
    }

    async fn handle_update_status(&self, task_id: String, status: TaskStatus) -> ZekeResult<ToolOutput> {
        self.manager.update_task_status(&task_id, status.clone()).await?;

        Ok(ToolOutput {
            success: true,
            content: format!("Task '{}' status updated to {:?}", task_id, status),
            error: None,
        })
    }

    async fn handle_list_tasks(&self) -> ZekeResult<ToolOutput> {
        let list = self.manager.get_task_list().await;
        let summary = self.manager.get_progress_summary().await;

        let mut output = String::new();
        output.push_str(&format!("📋 Task List: {}\n", list.name));
        output.push_str(&format!("Progress: {}/{} tasks completed ({:.1}%)\n\n",
                                summary.completed, summary.total, summary.completion_percentage));

        for (i, task) in list.tasks.iter().enumerate() {
            let status_icon = match task.status {
                TaskStatus::Pending => "⏳",
                TaskStatus::InProgress => "🔄",
                TaskStatus::Completed => "✅",
                TaskStatus::Blocked => "🚫",
                TaskStatus::Cancelled => "❌",
            };

            output.push_str(&format!("{}. {} {} (Priority: {})\n",
                                   i + 1, status_icon, task.content, task.priority));

            if !task.tags.is_empty() {
                output.push_str(&format!("   Tags: {}\n", task.tags.join(", ")));
            }
        }

        Ok(ToolOutput {
            success: true,
            content: output,
            error: None,
        })
    }
}

#[async_trait]
impl Tool for TodoTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Todo { action, task_id, content, active_form, status, priority } => {
                match action.as_str() {
                    "add" => {
                        if let (Some(content), Some(active_form)) = (content, active_form) {
                            self.handle_add_task(content, active_form, priority).await
                        } else {
                            Err(ZekeError::invalid_input("Content and active_form required for add action"))
                        }
                    }
                    "update" => {
                        if let (Some(task_id), Some(status)) = (task_id, status) {
                            self.handle_update_status(task_id, status).await
                        } else {
                            Err(ZekeError::invalid_input("Task ID and status required for update action"))
                        }
                    }
                    "list" => {
                        self.handle_list_tasks().await
                    }
                    "remove" => {
                        if let Some(task_id) = task_id {
                            self.manager.remove_task(&task_id).await?;
                            Ok(ToolOutput {
                                success: true,
                                content: format!("Task '{}' removed", task_id),
                                error: None,
                            })
                        } else {
                            Err(ZekeError::invalid_input("Task ID required for remove action"))
                        }
                    }
                    _ => Err(ZekeError::invalid_input(format!("Unknown action: {}", action))),
                }
            }
            _ => Err(ZekeError::invalid_input("TodoTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Todo"
    }

    fn description(&self) -> &str {
        "Task management system for tracking progress and organizing work. Supports task creation, status updates, dependencies, and progress tracking."
    }
}