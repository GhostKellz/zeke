use async_trait::async_trait;
use std::path::Path;
use tokio::fs;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct ReadTool;

impl ReadTool {
    pub fn new() -> Self {
        Self
    }

    async fn read_file_with_lines(&self, file_path: &Path, offset: Option<usize>, limit: Option<usize>) -> ZekeResult<String> {
        let content = fs::read_to_string(file_path).await
            .map_err(|e| ZekeError::io(format!("Failed to read file '{}': {}", file_path.display(), e)))?;

        let lines: Vec<&str> = content.lines().collect();
        let start = offset.unwrap_or(0);
        let end = if let Some(limit) = limit {
            std::cmp::min(start + limit, lines.len())
        } else {
            lines.len()
        };

        if start >= lines.len() {
            return Ok(String::new());
        }

        let selected_lines = &lines[start..end];
        let mut result = String::new();

        for (i, line) in selected_lines.iter().enumerate() {
            let line_number = start + i + 1;
            // Truncate lines longer than 2000 characters
            let truncated_line = if line.len() > 2000 {
                format!("{}...[truncated]", &line[..2000])
            } else {
                line.to_string()
            };
            result.push_str(&format!("{:6}→{}\n", line_number, truncated_line));
        }

        Ok(result)
    }
}

#[async_trait]
impl Tool for ReadTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Read { file_path } => {
                if !file_path.exists() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("File does not exist: {}", file_path.display())),
                    });
                }

                if file_path.is_dir() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Path is a directory, not a file: {}", file_path.display())),
                    });
                }

                match self.read_file_with_lines(&file_path, None, None).await {
                    Ok(content) => {
                        if content.is_empty() {
                            Ok(ToolOutput {
                                success: true,
                                content: String::new(),
                                error: Some("Warning: File exists but has empty contents".to_string()),
                            })
                        } else {
                            Ok(ToolOutput {
                                success: true,
                                content,
                                error: None,
                            })
                        }
                    }
                    Err(e) => Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(e.to_string()),
                    }),
                }
            }
            _ => Err(ZekeError::invalid_input("ReadTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Read"
    }

    fn description(&self) -> &str {
        "Reads a file from the filesystem with line numbers. Returns file contents with cat -n format."
    }
}