use async_trait::async_trait;
use std::path::Path;
use tokio::fs;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct WriteTool;

impl WriteTool {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl Tool for WriteTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Write { file_path, content } => {
                // Create parent directories if they don't exist
                if let Some(parent) = file_path.parent() {
                    if !parent.exists() {
                        fs::create_dir_all(parent).await
                            .map_err(|e| ZekeError::io(format!("Failed to create parent directories for '{}': {}", file_path.display(), e)))?;
                    }
                }

                // Check if file exists and warn if overwriting
                let file_exists = file_path.exists();

                match fs::write(&file_path, &content).await {
                    Ok(()) => {
                        let message = if file_exists {
                            format!("File '{}' has been overwritten successfully", file_path.display())
                        } else {
                            format!("File '{}' has been created successfully", file_path.display())
                        };

                        Ok(ToolOutput {
                            success: true,
                            content: message,
                            error: None,
                        })
                    }
                    Err(e) => Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Failed to write file '{}': {}", file_path.display(), e)),
                    }),
                }
            }
            _ => Err(ZekeError::invalid_input("WriteTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Write"
    }

    fn description(&self) -> &str {
        "Writes content to a file, creating parent directories if needed. Overwrites existing files."
    }
}