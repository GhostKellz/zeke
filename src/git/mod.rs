use async_trait::async_trait;
use git2::{Repository, Signature, ObjectType, StatusOptions, BranchType, PushOptions, RemoteCallbacks};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tokio::process::Command;
use tracing::{debug, info, error};

use crate::error::{ZekeError, ZekeResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub branch: String,
    pub ahead: usize,
    pub behind: usize,
    pub staged: Vec<String>,
    pub modified: Vec<String>,
    pub untracked: Vec<String>,
    pub conflicts: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitInfo {
    pub hash: String,
    pub message: String,
    pub author: String,
    pub timestamp: String,
}

#[derive(Debug, Clone)]
pub struct GitManager {
    repo_path: PathBuf,
}

impl GitManager {
    pub fn new() -> ZekeResult<Self> {
        let current_dir = std::env::current_dir()
            .map_err(|e| ZekeError::io(format!("Failed to get current directory: {}", e)))?;

        Ok(Self {
            repo_path: current_dir,
        })
    }

    pub fn with_path(path: PathBuf) -> Self {
        Self { repo_path: path }
    }

    fn get_repository(&self) -> ZekeResult<Repository> {
        Repository::discover(&self.repo_path)
            .map_err(|e| ZekeError::config(format!("Git repository not found: {}", e)))
    }

    pub async fn status(&self) -> ZekeResult<GitStatus> {
        let repo = self.get_repository()?;

        // Get current branch
        let head = repo.head().map_err(|e| ZekeError::config(format!("Failed to get HEAD: {}", e)))?;
        let branch_name = head.shorthand().unwrap_or("HEAD").to_string();

        // Get status
        let mut status_opts = StatusOptions::new();
        status_opts.include_untracked(true);
        let statuses = repo.statuses(Some(&mut status_opts))
            .map_err(|e| ZekeError::config(format!("Failed to get git status: {}", e)))?;

        let mut staged = Vec::new();
        let mut modified = Vec::new();
        let mut untracked = Vec::new();
        let mut conflicts = Vec::new();

        for entry in statuses.iter() {
            let path = entry.path().unwrap_or("").to_string();
            let status = entry.status();

            if status.is_index_new() || status.is_index_modified() || status.is_index_deleted() {
                staged.push(path.clone());
            }
            if status.is_wt_modified() || status.is_wt_deleted() {
                modified.push(path.clone());
            }
            if status.is_wt_new() {
                untracked.push(path.clone());
            }
            if status.is_conflicted() {
                conflicts.push(path);
            }
        }

        // Get ahead/behind counts
        let (ahead, behind) = self.get_ahead_behind_counts(&repo, &branch_name)?;

        Ok(GitStatus {
            branch: branch_name,
            ahead,
            behind,
            staged,
            modified,
            untracked,
            conflicts,
        })
    }

    fn get_ahead_behind_counts(&self, repo: &Repository, branch_name: &str) -> ZekeResult<(usize, usize)> {
        let local_branch = repo.find_branch(branch_name, BranchType::Local)
            .map_err(|e| ZekeError::config(format!("Failed to find local branch: {}", e)))?;

        let upstream = local_branch.upstream()
            .map_err(|_| ZekeError::config("No upstream branch configured".to_string()))?;

        let local_oid = local_branch.get().target()
            .ok_or_else(|| ZekeError::config("Failed to get local branch OID".to_string()))?;
        let upstream_oid = upstream.get().target()
            .ok_or_else(|| ZekeError::config("Failed to get upstream branch OID".to_string()))?;

        let (ahead, behind) = repo.graph_ahead_behind(local_oid, upstream_oid)
            .map_err(|e| ZekeError::config(format!("Failed to calculate ahead/behind: {}", e)))?;

        Ok((ahead, behind))
    }

    pub async fn add(&self, paths: &[String]) -> ZekeResult<()> {
        let repo = self.get_repository()?;
        let mut index = repo.index()
            .map_err(|e| ZekeError::config(format!("Failed to get git index: {}", e)))?;

        for path in paths {
            index.add_path(Path::new(path))
                .map_err(|e| ZekeError::config(format!("Failed to add path '{}': {}", path, e)))?;
        }

        index.write()
            .map_err(|e| ZekeError::config(format!("Failed to write index: {}", e)))?;

        info!("Added {} files to git index", paths.len());
        Ok(())
    }

    pub async fn commit(&self, message: &str) -> ZekeResult<String> {
        let repo = self.get_repository()?;

        // Get signature
        let signature = self.get_signature(&repo)?;

        // Get current tree
        let mut index = repo.index()
            .map_err(|e| ZekeError::config(format!("Failed to get git index: {}", e)))?;
        let tree_id = index.write_tree()
            .map_err(|e| ZekeError::config(format!("Failed to write tree: {}", e)))?;
        let tree = repo.find_tree(tree_id)
            .map_err(|e| ZekeError::config(format!("Failed to find tree: {}", e)))?;

        // Get parent commit
        let parent_commit = match repo.head() {
            Ok(head) => {
                let oid = head.target().unwrap();
                Some(repo.find_commit(oid)
                    .map_err(|e| ZekeError::config(format!("Failed to find parent commit: {}", e)))?)
            }
            Err(_) => None, // First commit
        };

        // Create commit
        let parents: Vec<&git2::Commit> = parent_commit.iter().collect();
        let commit_id = repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        ).map_err(|e| ZekeError::config(format!("Failed to create commit: {}", e)))?;

        let commit_hash = commit_id.to_string();
        info!("Created commit: {}", commit_hash);
        Ok(commit_hash)
    }

    fn get_signature(&self, repo: &Repository) -> ZekeResult<Signature> {
        // Try to get signature from git config
        let config = repo.config()
            .map_err(|e| ZekeError::config(format!("Failed to get git config: {}", e)))?;

        let name = config.get_string("user.name")
            .unwrap_or_else(|_| "Zeke User".to_string());
        let email = config.get_string("user.email")
            .unwrap_or_else(|_| "zeke@localhost".to_string());

        Signature::now(&name, &email)
            .map_err(|e| ZekeError::config(format!("Failed to create signature: {}", e)))
    }

    pub async fn create_branch(&self, branch_name: &str, from_branch: Option<&str>) -> ZekeResult<()> {
        let repo = self.get_repository()?;

        let target_commit = if let Some(from) = from_branch {
            let branch = repo.find_branch(from, BranchType::Local)
                .map_err(|e| ZekeError::config(format!("Failed to find source branch '{}': {}", from, e)))?;
            let oid = branch.get().target()
                .ok_or_else(|| ZekeError::config("Failed to get branch OID".to_string()))?;
            repo.find_commit(oid)
                .map_err(|e| ZekeError::config(format!("Failed to find commit: {}", e)))?
        } else {
            let head = repo.head()
                .map_err(|e| ZekeError::config(format!("Failed to get HEAD: {}", e)))?;
            let oid = head.target()
                .ok_or_else(|| ZekeError::config("Failed to get HEAD OID".to_string()))?;
            repo.find_commit(oid)
                .map_err(|e| ZekeError::config(format!("Failed to find HEAD commit: {}", e)))?
        };

        repo.branch(branch_name, &target_commit, false)
            .map_err(|e| ZekeError::config(format!("Failed to create branch '{}': {}", branch_name, e)))?;

        info!("Created branch: {}", branch_name);
        Ok(())
    }

    pub async fn checkout(&self, branch_name: &str) -> ZekeResult<()> {
        let repo = self.get_repository()?;

        let (object, reference) = repo.revparse_ext(branch_name)
            .map_err(|e| ZekeError::config(format!("Failed to find branch '{}': {}", branch_name, e)))?;

        repo.checkout_tree(&object, None)
            .map_err(|e| ZekeError::config(format!("Failed to checkout tree: {}", e)))?;

        match reference {
            Some(gref) => repo.set_head(gref.name().unwrap()),
            None => repo.set_head_detached(object.id()),
        }.map_err(|e| ZekeError::config(format!("Failed to set HEAD: {}", e)))?;

        info!("Checked out branch: {}", branch_name);
        Ok(())
    }

    pub async fn push(&self, remote_name: Option<&str>, branch_name: Option<&str>) -> ZekeResult<()> {
        let repo = self.get_repository()?;

        let remote_name = remote_name.unwrap_or("origin");
        let mut remote = repo.find_remote(remote_name)
            .map_err(|e| ZekeError::config(format!("Failed to find remote '{}': {}", remote_name, e)))?;

        let branch_name = if let Some(name) = branch_name {
            name.to_string()
        } else {
            let head = repo.head()
                .map_err(|e| ZekeError::config(format!("Failed to get HEAD: {}", e)))?;
            head.shorthand().unwrap_or("main").to_string()
        };

        let refspec = format!("refs/heads/{}:refs/heads/{}", branch_name, branch_name);

        let mut callbacks = RemoteCallbacks::new();
        callbacks.credentials(|_url, username_from_url, _allowed_types| {
            git2::Cred::ssh_key_from_agent(username_from_url.unwrap_or("git"))
        });

        let mut push_options = PushOptions::new();
        push_options.remote_callbacks(callbacks);

        remote.push(&[&refspec], Some(&mut push_options))
            .map_err(|e| ZekeError::config(format!("Failed to push: {}", e)))?;

        info!("Pushed branch '{}' to remote '{}'", branch_name, remote_name);
        Ok(())
    }

    pub async fn create_pull_request(&self, title: &str, body: &str, base: &str, head: &str) -> ZekeResult<String> {
        // Use GitHub CLI for PR creation
        let output = Command::new("gh")
            .args(&[
                "pr", "create",
                "--title", title,
                "--body", body,
                "--base", base,
                "--head", head,
            ])
            .output()
            .await
            .map_err(|e| ZekeError::config(format!("Failed to execute gh command: {}", e)))?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(ZekeError::config(format!("Failed to create PR: {}", error)));
        }

        let pr_url = String::from_utf8_lossy(&output.stdout).trim().to_string();
        info!("Created pull request: {}", pr_url);
        Ok(pr_url)
    }

    pub async fn get_recent_commits(&self, count: usize) -> ZekeResult<Vec<CommitInfo>> {
        let repo = self.get_repository()?;

        let mut revwalk = repo.revwalk()
            .map_err(|e| ZekeError::config(format!("Failed to create revwalk: {}", e)))?;

        revwalk.push_head()
            .map_err(|e| ZekeError::config(format!("Failed to push HEAD: {}", e)))?;

        let mut commits = Vec::new();

        for (i, oid) in revwalk.enumerate() {
            if i >= count {
                break;
            }

            let oid = oid.map_err(|e| ZekeError::config(format!("Failed to get commit OID: {}", e)))?;
            let commit = repo.find_commit(oid)
                .map_err(|e| ZekeError::config(format!("Failed to find commit: {}", e)))?;

            commits.push(CommitInfo {
                hash: oid.to_string(),
                message: commit.message().unwrap_or("").to_string(),
                author: commit.author().name().unwrap_or("Unknown").to_string(),
                timestamp: chrono::DateTime::from_timestamp(commit.time().seconds(), 0)
                    .unwrap_or_default()
                    .format("%Y-%m-%d %H:%M:%S")
                    .to_string(),
            });
        }

        Ok(commits)
    }

    pub async fn diff(&self, staged: bool) -> ZekeResult<String> {
        let repo = self.get_repository()?;

        let diff = if staged {
            // Staged changes (index vs HEAD)
            let head_tree = if let Ok(head) = repo.head() {
                let oid = head.target().unwrap();
                let commit = repo.find_commit(oid)?;
                Some(commit.tree()?)
            } else {
                None
            };

            repo.diff_tree_to_index(head_tree.as_ref(), None, None)?
        } else {
            // Working directory changes
            repo.diff_index_to_workdir(None, None)?
        };

        let mut diff_output = String::new();
        diff.print(git2::DiffFormat::Patch, |_delta, _hunk, line| {
            match line.origin() {
                '+' | '-' | ' ' => diff_output.push(line.origin()),
                _ => {}
            }
            diff_output.push_str(std::str::from_utf8(line.content()).unwrap_or(""));
            true
        }).map_err(|e| ZekeError::config(format!("Failed to generate diff: {}", e)))?;

        Ok(diff_output)
    }
}