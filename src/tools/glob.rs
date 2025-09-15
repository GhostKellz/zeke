use async_trait::async_trait;
use globset::{Glob, GlobSetBuilder};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct GlobTool;

impl GlobTool {
    pub fn new() -> Self {
        Self
    }

    fn find_files(&self, pattern: &str, search_path: &Path) -> Result<Vec<PathBuf>, String> {
        let glob = Glob::new(pattern)
            .map_err(|e| format!("Invalid glob pattern '{}': {}", pattern, e))?;

        let mut builder = GlobSetBuilder::new();
        builder.add(glob);
        let globset = builder.build()
            .map_err(|e| format!("Failed to build glob set: {}", e))?;

        let mut matches = Vec::new();

        for entry in WalkDir::new(search_path)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
        {
            let path = entry.path();

            // Try matching against the full path and just the file name
            let full_path_str = path.to_string_lossy();
            let file_name = path.file_name()
                .map(|n| n.to_string_lossy())
                .unwrap_or_default();

            if globset.is_match(full_path_str.as_ref()) || globset.is_match(file_name.as_ref()) {
                matches.push(path.to_path_buf());
            }
        }

        // Sort by modification time (most recent first) where possible
        matches.sort_by(|a, b| {
            let a_modified = a.metadata().and_then(|m| m.modified()).ok();
            let b_modified = b.metadata().and_then(|m| m.modified()).ok();

            match (a_modified, b_modified) {
                (Some(a_time), Some(b_time)) => b_time.cmp(&a_time), // Reverse for most recent first
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => a.cmp(b), // Fallback to lexicographic
            }
        });

        Ok(matches)
    }
}

#[async_trait]
impl Tool for GlobTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Glob { pattern, path } => {
                let search_path = path.unwrap_or_else(|| PathBuf::from("."));

                if !search_path.exists() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Search path does not exist: {}", search_path.display())),
                    });
                }

                if !search_path.is_dir() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Search path is not a directory: {}", search_path.display())),
                    });
                }

                match self.find_files(&pattern, &search_path) {
                    Ok(matches) => {
                        if matches.is_empty() {
                            Ok(ToolOutput {
                                success: true,
                                content: format!("No files found matching pattern '{}'", pattern),
                                error: None,
                            })
                        } else {
                            let content = matches
                                .iter()
                                .map(|p| p.display().to_string())
                                .collect::<Vec<_>>()
                                .join("\n");

                            Ok(ToolOutput {
                                success: true,
                                content: format!("Found {} files:\n{}", matches.len(), content),
                                error: None,
                            })
                        }
                    }
                    Err(e) => Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(e),
                    }),
                }
            }
            _ => Err(ZekeError::invalid_input("GlobTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Glob"
    }

    fn description(&self) -> &str {
        "Fast file pattern matching tool. Supports glob patterns like '**/*.js' or 'src/**/*.ts'. Returns matches sorted by modification time."
    }
}