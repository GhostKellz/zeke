use async_trait::async_trait;
use std::process::Stdio;
use std::time::Duration;
use tokio::process::Command;
use tokio::time::timeout;
use crate::error::{ZekeError, ZekeResult};
use super::{Tool, ToolInput, ToolOutput};

pub struct BashTool;

impl BashTool {
    pub fn new() -> Self {
        Self
    }

    async fn execute_command(&self, command: &str, timeout_secs: Option<u64>) -> Result<(String, String, i32), String> {
        let timeout_duration = Duration::from_secs(timeout_secs.unwrap_or(120));

        let mut cmd = if cfg!(target_os = "windows") {
            let mut cmd = Command::new("cmd");
            cmd.args(["/C", command]);
            cmd
        } else {
            let mut cmd = Command::new("sh");
            cmd.args(["-c", command]);
            cmd
        };

        cmd.stdout(Stdio::piped())
           .stderr(Stdio::piped())
           .stdin(Stdio::null());

        let child = cmd.spawn()
            .map_err(|e| format!("Failed to spawn command: {}", e))?;

        let output = timeout(timeout_duration, child.wait_with_output())
            .await
            .map_err(|_| format!("Command timed out after {} seconds", timeout_duration.as_secs()))?
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let exit_code = output.status.code().unwrap_or(-1);

        Ok((stdout, stderr, exit_code))
    }

    fn format_command_output(&self, command: &str, stdout: &str, stderr: &str, exit_code: i32) -> String {
        let mut result = String::new();

        result.push_str(&format!("Command: {}\n", command));
        result.push_str(&format!("Exit code: {}\n\n", exit_code));

        if !stdout.is_empty() {
            result.push_str("STDOUT:\n");
            // Truncate output if it's too long
            if stdout.len() > 30000 {
                result.push_str(&stdout[..30000]);
                result.push_str("\n... [output truncated] ...\n");
            } else {
                result.push_str(stdout);
            }
            result.push('\n');
        }

        if !stderr.is_empty() {
            result.push_str("STDERR:\n");
            // Truncate output if it's too long
            if stderr.len() > 30000 {
                result.push_str(&stderr[..30000]);
                result.push_str("\n... [output truncated] ...\n");
            } else {
                result.push_str(stderr);
            }
            result.push('\n');
        }

        result
    }

    fn is_safe_command(&self, command: &str) -> bool {
        let dangerous_commands = [
            "rm -rf /",
            "format",
            "fdisk",
            "mkfs",
            "dd if=",
            ":(){ :|:& };:",
            "sudo rm",
            "sudo dd",
            "sudo mkfs",
            "sudo fdisk",
            "> /dev/sd",
            "shutdown",
            "reboot",
            "halt",
            "poweroff",
        ];

        let cmd_lower = command.to_lowercase();
        for dangerous in &dangerous_commands {
            if cmd_lower.contains(dangerous) {
                return false;
            }
        }

        true
    }
}

#[async_trait]
impl Tool for BashTool {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput> {
        match input {
            ToolInput::Bash { command, timeout } => {
                // Basic safety check
                if !self.is_safe_command(&command) {
                    return Ok(ToolOutput {
                        success: false,
                        content: String::new(),
                        error: Some("Command appears to be potentially dangerous and has been blocked".to_string()),
                    });
                }

                match self.execute_command(&command, timeout).await {
                    Ok((stdout, stderr, exit_code)) => {
                        let output = self.format_command_output(&command, &stdout, &stderr, exit_code);

                        if exit_code == 0 {
                            Ok(ToolOutput {
                                success: true,
                                content: output,
                                error: None,
                            })
                        } else {
                            Ok(ToolOutput {
                                success: false,
                                content: output,
                                error: Some(format!("Command failed with exit code {}", exit_code)),
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
            _ => Err(ZekeError::invalid_input("BashTool received invalid input type")),
        }
    }

    fn name(&self) -> &str {
        "Bash"
    }

    fn description(&self) -> &str {
        "Executes bash commands with timeout support and output capturing. Includes basic safety checks."
    }
}