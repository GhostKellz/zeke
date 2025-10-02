# 👁️ ZEKE Watch Mode - The Revolutionary AI Development Loop

Watch Mode is ZEKE's killer feature - a continuous AI-powered development assistant that watches your codebase, detects issues in real-time, suggests fixes via local LLM, and optionally auto-applies and auto-commits them.

## 🚀 Quick Start

```sh
# Basic monitoring - watch files and report issues
zeke watch

# AI-assisted development - auto-apply suggested fixes
zeke watch --auto-fix

# Full automation - auto-commit when tests pass
zeke watch --auto-fix --auto-commit

# Watch specific directory
zeke watch /path/to/project

# Custom model
zeke watch --model deepseek-coder:33b
```

## 🌟 Features

### 1. Real-Time File Watching
- **Linux**: Native inotify for instant change detection (sub-100ms)
- **macOS**: FSEvents support (coming soon)
- **Fallback**: Polling-based detection for other platforms
- **Recursive**: Automatically watches subdirectories
- **Smart filtering**: Respects `.gitignore`-style patterns

### 2. Grove AST Integration
- **Syntax-aware parsing**: Uses Grove (Tree-sitter for Zig) for deep code understanding
- **Multi-language support**: Zig, JSON, Rust, Go, JavaScript, TypeScript, Python, C/C++
- **Zero-overhead**: Incremental parsing for instant feedback
- **Semantic analysis**: Understands code structure, not just text patterns

### 3. Intelligent Issue Detection

#### Unused Variables
```zig
// Detected: unused variable 'count'
const count = 42;  // ⚠️ Warning: 'count' is never used

// Suggestion: Remove or prefix with underscore
const _count = 42;  // ✅ Intentionally unused
```

#### TODO Comments with Rich Metadata
```zig
// TODO: Basic todo
// ℹ️  Priority: normal, Category: feature

// TODO!!! Urgent optimization needed
// 🟠 Priority: high, Category: feature

// TODO(#123): Implement feature from GitHub issue
// ℹ️  Issue: #123, Link to tracking

// TODO(@john): Fix authentication bug
// ℹ️  Assignee: @john, Category: feature

// FIXME: Critical memory leak
// 🔴 Priority: critical, Category: bug_fix

// HACK: Temporary workaround for null pointer
// 🔴 Priority: critical, Category: hack

// OPTIMIZE: Profile this hot path
// ℹ️  Category: optimization

// REFACTOR: Clean up this code
// ℹ️  Category: refactor

// TEST: Add unit tests
// ℹ️  Category: test

// SECURITY: Validate user input
// ⚠️  Category: security
```

#### Priority Levels
- **Critical** (🔴): `FIXME`, `XXX`, `HACK` - immediate action required
- **High** (🟠): `TODO!!!` - urgent, should be addressed soon
- **Medium** (🟡): `TODO!!` - important, schedule for next sprint
- **Low** (🔵): `TODO!` - nice to have, future consideration
- **Normal** (⚪): `TODO` - standard task

#### Categories
- **Bug Fix** (🐛): `FIXME`, `BUG` - code defects
- **Refactor** (♻️): `REFACTOR`, `CLEANUP` - code quality improvements
- **Optimization** (⚡): `OPTIMIZE`, `PERF` - performance improvements
- **Documentation** (📚): `DOC`, `DOCS` - missing or incomplete docs
- **Feature** (✨): `TODO`, `FEATURE` - new functionality
- **Security** (🔒): `SECURITY`, `XXX` - security concerns
- **Test** (🧪): `TEST`, `TESTING` - test coverage gaps
- **Hack** (⚠️): `HACK`, `WORKAROUND` - temporary solutions

### 4. AI-Powered Fix Suggestions
- **Local LLM**: Uses Ollama (offline, privacy-preserving)
- **Context-aware**: Provides file content and issue details
- **Smart prompts**: Tailored suggestions for each issue type
- **Confidence scoring**: Shows suggestion reliability

Example:
```
🔍 Analyzing src/main.zig...
ℹ️  src/main.zig:42:5 - TODO [Feature]: Add error handling
   💡 Suggestion: Consider creating a GitHub issue to track this feature
   🤖 AI Suggestion: Wrap the function call in a try-catch block and handle
                     the error with proper logging and user feedback
```

### 5. Auto-Fix Mode
When `--auto-fix` is enabled:
1. Detects issue
2. Generates AI suggestion
3. Applies fix to source file
4. Reports what was changed
5. Continues watching

Safety features:
- Only fixes with high AI confidence
- Creates backup before applying
- Logs all changes
- User can review via git diff

### 6. Auto-Commit Mode
When `--auto-commit` is enabled:
1. Applies auto-fixes
2. Runs `zig build test`
3. Only commits if tests pass
4. Generates descriptive commit messages
5. Includes "Generated with Zeke Watch Mode" footer

Example commit:
```
fix: auto-fix 3 issue(s) in src/parser.zig

Automatically fixed by Zeke Watch Mode
- Applied AI-suggested fixes
- All tests passed

🤖 Generated with Zeke Watch Mode
```

## 🎯 Use Cases

### 1. Continuous Code Review
Leave Watch Mode running during development for instant feedback:
```sh
zeke watch src/
```

### 2. TODO Management
Track and prioritize technical debt:
```sh
zeke watch --show-todos
```

### 3. AI Pair Programming
Let Zeke auto-fix issues as you code:
```sh
zeke watch --auto-fix
```

### 4. Automated Testing & Commits
Full CI/CD-like workflow locally:
```sh
zeke watch --auto-fix --auto-commit
```

### 5. Learning & Documentation
See AI explanations for every issue:
```sh
zeke watch --explain
```

## ⚙️ Configuration

### Watch Patterns
Edit `.zeke/watch.toml`:
```toml
[watch]
patterns = ["*.zig", "*.json", "*.md"]
ignore = [
    "zig-cache/**",
    "zig-out/**",
    ".git/**",
    ".zeke/**",
    "**/node_modules/**",
]

[ai]
model = "deepseek-coder:33b"
host = "http://localhost:11434"
timeout_ms = 30000

[auto-fix]
enabled = false
confidence_threshold = 0.8
backup_before_fix = true

[auto-commit]
enabled = false
require_tests = true
commit_message_prefix = "fix"
```

### Environment Variables
```sh
export ZEKE_WATCH_MODEL="deepseek-coder:33b"
export ZEKE_OLLAMA_HOST="http://localhost:11434"
export ZEKE_AUTO_FIX=true
export ZEKE_AUTO_COMMIT=true
```

## 🔧 Advanced Usage

### Custom Issue Detectors
Add your own issue patterns in `.zeke/detectors.zig`:
```zig
pub fn detectCustomIssue(parsed: *ParsedFile) ![]Issue {
    // Your custom detection logic
}
```

### AI Model Selection
```sh
# Fast, low resource
zeke watch --model codellama:7b

# Balanced
zeke watch --model deepseek-coder:33b

# Maximum quality
zeke watch --model codellama:70b
```

### Filter by Issue Type
```sh
# Only show critical issues
zeke watch --severity critical

# Only show TODOs
zeke watch --category feature

# Only show assignees
zeke watch --assignee @john
```

## 🎨 Output Formats

### Pretty (Default)
Colorful, emoji-rich output in terminal

### JSON
Machine-readable for integration:
```sh
zeke watch --format json > issues.json
```

### Summary
Concise overview:
```sh
zeke watch --format summary
```

## 🚧 Roadmap

- [ ] macOS FSEvents implementation
- [ ] Windows file watching
- [ ] Language server protocol (LSP) integration
- [ ] Web dashboard for remote monitoring
- [ ] Team collaboration features
- [ ] Custom AI model training
- [ ] Integration with GitHub Issues
- [ ] Slack/Discord notifications
- [ ] VS Code extension
- [ ] Database persistence for TODO tracking

## 💡 Tips & Tricks

1. **Start with basic mode first** - understand what's detected before enabling auto-fix
2. **Use `.gitignore` patterns** - Watch Mode respects ignore files automatically
3. **Review AI suggestions** - check `git diff` before committing auto-fixes
4. **Tune the model** - try different Ollama models for your use case
5. **Monitor performance** - Watch Mode is designed to be lightweight
6. **Combine with git hooks** - integrate into pre-commit workflow

## 🐛 Troubleshooting

### "Too many open files" error
Increase file descriptor limit:
```sh
ulimit -n 4096
```

### Watch Mode not detecting changes
Check ignore patterns:
```sh
zeke watch --debug
```

### Ollama connection failed
Verify Ollama is running:
```sh
curl http://localhost:11434/api/generate
```

### Auto-fix breaking code
Adjust confidence threshold:
```toml
[auto-fix]
confidence_threshold = 0.9  # Higher = more conservative
```

## 🤝 Contributing

Watch Mode is actively developed! Contributions welcome:

1. **Add language support**: Implement Grove parsers
2. **New detectors**: Create custom issue detectors
3. **AI improvements**: Better prompt engineering
4. **Platform support**: macOS FSEvents, Windows watching
5. **Documentation**: Usage examples and tutorials

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## 📄 License

Part of ZEKE - see main [LICENSE](LICENSE)

---

**Built with paranoia and joy by [GhostKellz](https://github.com/ghostkellz)**
