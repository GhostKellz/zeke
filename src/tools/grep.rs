use async_trait::async_trait;
use regex::Regex;
use std::path::{Path, PathBuf};
use tokio::fs;
use walkdir::WalkDir;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct GrepTool;

impl GrepTool {
    pub fn new() -> Self {
        Self
    }

    async fn search_file(&self, file_path: &Path, pattern: &Regex, case_insensitive: bool) -> Result<Vec<(usize, String)>, String> {
        let content = fs::read_to_string(file_path).await
            .map_err(|e| format!("Failed to read file '{}': {}", file_path.display(), e))?;

        let mut matches = Vec::new();

        for (line_num, line) in content.lines().enumerate() {
            if pattern.is_match(line) {
                matches.push((line_num + 1, line.to_string()));
            }
        }

        Ok(matches)
    }

    fn get_file_type_extensions(file_type: &str) -> Vec<&'static str> {
        match file_type.to_lowercase().as_str() {
            "rust" | "rs" => vec!["rs"],
            "python" | "py" => vec!["py", "pyw"],
            "javascript" | "js" => vec!["js", "jsx"],
            "typescript" | "ts" => vec!["ts", "tsx"],
            "java" => vec!["java"],
            "cpp" | "c++" => vec!["cpp", "cxx", "cc", "hpp", "hxx"],
            "c" => vec!["c", "h"],
            "go" => vec!["go"],
            "ruby" | "rb" => vec!["rb"],
            "php" => vec!["php"],
            "html" => vec!["html", "htm"],
            "css" => vec!["css"],
            "json" => vec!["json"],
            "xml" => vec!["xml"],
            "yaml" | "yml" => vec!["yaml", "yml"],
            "toml" => vec!["toml"],
            "md" | "markdown" => vec!["md", "markdown"],
            "txt" | "text" => vec!["txt"],
            _ => vec![],
        }
    }

    fn should_include_file(&self, file_path: &Path, file_type: Option<&str>, glob_pattern: Option<&str>) -> bool {
        // Check file type filter
        if let Some(ft) = file_type {
            if let Some(extension) = file_path.extension().and_then(|e| e.to_str()) {
                let valid_extensions = Self::get_file_type_extensions(ft);
                if !valid_extensions.is_empty() && !valid_extensions.contains(&extension) {
                    return false;
                }
            } else if !Self::get_file_type_extensions(ft).is_empty() {
                return false;
            }
        }

        // Check glob pattern filter
        if let Some(pattern) = glob_pattern {
            // Simple glob matching - could be enhanced with proper glob library
            if pattern.contains('*') {
                let regex_pattern = pattern
                    .replace(".", r"\.")
                    .replace("*", ".*");

                if let Ok(regex) = Regex::new(&regex_pattern) {
                    let file_name = file_path.file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("");

                    if !regex.is_match(file_name) {
                        return false;
                    }
                }
            } else if let Some(file_name) = file_path.file_name().and_then(|n| n.to_str()) {
                if !file_name.contains(pattern) {
                    return false;
                }
            }
        }

        true
    }

    async fn search_directory(&self,
        search_path: &Path,
        pattern: &Regex,
        file_type: Option<&str>,
        glob_pattern: Option<&str>,
        case_insensitive: bool,
        show_line_numbers: bool,
        _context_before: usize,
        _context_after: usize,
        files_only: bool,
        count_only: bool,
        head_limit: Option<usize>
    ) -> Result<String, String> {
        let mut results = Vec::new();
        let mut _file_count = 0;

        for entry in WalkDir::new(search_path)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
        {
            let file_path = entry.path();

            if !self.should_include_file(file_path, file_type, glob_pattern) {
                continue;
            }

            match self.search_file(file_path, pattern, case_insensitive).await {
                Ok(matches) => {
                    if !matches.is_empty() {
                        _file_count += 1;

                        if files_only {
                            results.push(file_path.display().to_string());
                        } else if count_only {
                            results.push(format!("{}:{}", file_path.display(), matches.len()));
                        } else {
                            let mut file_results = Vec::new();

                            for (line_num, line) in matches {
                                if show_line_numbers {
                                    file_results.push(format!("{}:{}:{}", file_path.display(), line_num, line));
                                } else {
                                    file_results.push(format!("{}:{}", file_path.display(), line));
                                }
                            }

                            results.extend(file_results);
                        }

                        // Apply head limit if specified
                        if let Some(limit) = head_limit {
                            if results.len() >= limit {
                                results.truncate(limit);
                                break;
                            }
                        }
                    }
                }
                Err(_) => {
                    // Skip files we can't read (binary files, permission issues, etc.)
                    continue;
                }
            }
        }

        if results.is_empty() {
            Ok(format!("No matches found for pattern '{}'", pattern.as_str()))
        } else {
            Ok(results.join("\n"))
        }
    }
}

#[async_trait]
impl Tool for GrepTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Grep { pattern, path, file_type } => {
                let search_path = path.unwrap_or_else(|| PathBuf::from("."));

                if !search_path.exists() {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Search path does not exist: {}", search_path.display())),
                    });
                }

                // Compile regex pattern
                let regex = match Regex::new(&pattern) {
                    Ok(regex) => regex,
                    Err(e) => return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(format!("Invalid regex pattern '{}': {}", pattern, e)),
                    }),
                };

                let result = if search_path.is_file() {
                    // Search single file
                    match self.search_file(&search_path, &regex, false).await {
                        Ok(matches) => {
                            if matches.is_empty() {
                                format!("No matches found in file '{}'", search_path.display())
                            } else {
                                matches.iter()
                                    .map(|(line_num, line)| format!("{}:{}:{}", search_path.display(), line_num, line))
                                    .collect::<Vec<_>>()
                                    .join("\n")
                            }
                        }
                        Err(e) => return Ok(ToolOutput {
                            success: false,
                            content: String::new(),
                            error: Some(e),
                        }),
                    }
                } else {
                    // Search directory
                    match self.search_directory(
                        &search_path,
                        &regex,
                        file_type.as_deref(),
                        None, // glob pattern - could be added as parameter
                        false, // case insensitive
                        true, // show line numbers
                        0, // context before
                        0, // context after
                        false, // files only
                        false, // count only
                        None // head limit
                    ).await {
                        Ok(result) => result,
                        Err(e) => return Ok(ToolOutput {
                            success: false,
                            content: String::new(),
                            error: Some(e),
                        }),
                    }
                };

                Ok(ToolOutput {
                    success: true,
                    content: result,
                    error: None,
                })
            }
            _ => Err(ZekeError::invalid_input("GrepTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Grep"
    }

    fn description(&self) -> &str {
        "Powerful search tool built on regex. Supports file type filtering and pattern matching across codebases."
    }
}