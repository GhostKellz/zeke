use async_trait::async_trait;
use std::path::Path;
use tokio::fs;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct EditTool;

impl EditTool {
    pub fn new() -> Self {
        Self
    }

    fn perform_edit(&self, content: &str, old_string: &str, new_string: &str, replace_all: bool) -> Result<String, String> {
        if old_string == new_string {
            return Err("old_string and new_string cannot be the same".to_string());
        }

        if old_string.is_empty() {
            return Err("old_string cannot be empty".to_string());
        }

        if replace_all {
            Ok(content.replace(old_string, new_string))
        } else {
            // Check if the string appears exactly once
            let matches: Vec<_> = content.match_indices(old_string).collect();

            match matches.len() {
                0 => Err(format!("String '{}' not found in file", old_string)),
                1 => Ok(content.replacen(old_string, new_string, 1)),
                n => Err(format!("String '{}' appears {} times in file. Use replace_all=true or provide more context to make it unique", old_string, n)),
            }
        }
    }
}

#[async_trait]
impl Tool for EditTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Edit { file_path, old_string, new_string } => {
                if !file_path.exists() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("File does not exist: {}", file_path.display())),
                    });
                }

                // Read the current file content
                let content = match fs::read_to_string(&file_path).await {
                    Ok(content) => content,
                    Err(e) => return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Failed to read file '{}': {}", file_path.display(), e)),
                    }),
                };

                // Perform the edit
                let new_content = match self.perform_edit(&content, &old_string, &new_string, false) {
                    Ok(new_content) => new_content,
                    Err(e) => return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(e),
                    }),
                };

                // Write the updated content back to the file
                match fs::write(&file_path, &new_content).await {
                    Ok(()) => Ok(ToolOutput {
                        success: true,
                        content: format!("File '{}' has been updated successfully", file_path.display()),
                        error: None,
                    }),
                    Err(e) => Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Failed to write file '{}': {}", file_path.display(), e)),
                    }),
                }
            }
            _ => Err(ZekeError::invalid_input("EditTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Edit"
    }

    fn description(&self) -> &str {
        "Performs exact string replacements in files. Requires unique matches unless replace_all is used."
    }
}