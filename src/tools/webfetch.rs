use async_trait::async_trait;
use reqwest::Client;
use std::time::Duration;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct WebFetchTool {
    client: Client,
}

impl WebFetchTool {
    pub fn new() -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("Zeke/0.3.0 (Rust AI Dev Companion)")
            .build()
            .unwrap_or_else(|_| Client::new());

        Self { client }
    }

    async fn fetch_content(&self, url: &str) -> Result<String, String> {
        // Validate URL
        let parsed_url = url.parse::<reqwest::Url>()
            .map_err(|e| format!("Invalid URL '{}': {}", url, e))?;

        // Basic security checks
        if parsed_url.scheme() != "http" && parsed_url.scheme() != "https" {
            return Err(format!("Unsupported URL scheme: {}", parsed_url.scheme()));
        }

        // Fetch the content
        let response = self.client
            .get(url)
            .send()
            .await
            .map_err(|e| format!("Failed to fetch URL '{}': {}", url, e))?;

        if !response.status().is_success() {
            return Err(format!("HTTP error {}: {}", response.status().as_u16(), response.status().canonical_reason().unwrap_or("Unknown")));
        }

        let content = response
            .text()
            .await
            .map_err(|e| format!("Failed to read response content: {}", e))?;

        Ok(content)
    }

    fn convert_html_to_markdown(&self, html: &str) -> String {
        // Basic HTML to markdown conversion
        // This is a simplified implementation - a full implementation would use html2md or similar
        let mut markdown = html.to_string();

        // Remove common HTML tags and convert to markdown
        markdown = markdown
            .replace("<br>", "\n")
            .replace("<br/>", "\n")
            .replace("<br />", "\n")
            .replace("</p>", "\n\n")
            .replace("<p>", "")
            .replace("</div>", "\n")
            .replace("<div>", "")
            .replace("</h1>", "\n")
            .replace("<h1>", "# ")
            .replace("</h2>", "\n")
            .replace("<h2>", "## ")
            .replace("</h3>", "\n")
            .replace("<h3>", "### ")
            .replace("</li>", "\n")
            .replace("<li>", "- ")
            .replace("</ul>", "\n")
            .replace("<ul>", "")
            .replace("</ol>", "\n")
            .replace("<ol>", "")
            .replace("</pre>", "\n```\n")
            .replace("<pre>", "\n```\n")
            .replace("</code>", "`")
            .replace("<code>", "`");

        // Remove remaining HTML tags (simple regex)
        let re = regex::Regex::new(r"<[^>]*>").unwrap();
        markdown = re.replace_all(&markdown, "").to_string();

        // Clean up extra whitespace
        let lines: Vec<&str> = markdown.lines()
            .map(|line| line.trim())
            .filter(|line| !line.is_empty())
            .collect();

        lines.join("\n")
    }

    async fn process_content_with_prompt(&self, content: &str, prompt: &str) -> String {
        // For now, just return the content with a note about the prompt
        // In a full implementation, this would use an AI model to process the content
        format!("Content fetched (prompt: '{}')\n\n{}", prompt, content)
    }
}

#[async_trait]
impl Tool for WebFetchTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::WebFetch { url, prompt } => {
                // Fetch the content
                let content = match self.fetch_content(&url).await {
                    Ok(content) => content,
                    Err(e) => return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some(e),
                    }),
                };

                // Convert HTML to markdown if it looks like HTML
                let processed_content = if content.trim_start().starts_with('<') {
                    self.convert_html_to_markdown(&content)
                } else {
                    content
                };

                // Process with prompt (simplified for now)
                let final_content = self.process_content_with_prompt(&processed_content, &prompt).await;

                // Limit content length
                let truncated_content = if final_content.len() > 50000 {
                    format!("{}...\n\n[Content truncated - original length: {} characters]",
                           &final_content[..50000], final_content.len())
                } else {
                    final_content
                };

                Ok(ToolOutput {
                    success: true,
                    content: truncated_content,
                    error: None,
                })
            }
            _ => Err(ZekeError::invalid_input("WebFetchTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "WebFetch"
    }

    fn description(&self) -> &str {
        "Fetches content from URLs and processes it. Converts HTML to markdown and supports content analysis prompts."
    }
}