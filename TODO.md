# Zeke Neovim Plugin - TODO

## Phase 1: Core UI Components
- [ ] Floating chat panel (like claude-code.nvim)
  - [ ] Telescope-based UI framework
  - [ ] Markdown rendering support
  - [ ] Syntax highlighting in code blocks
  - [ ] Stream rendering for real-time responses
- [ ] Action panel with Allow once/Allow all/Deny buttons
- [ ] Diff preview window for proposed changes
- [ ] Status line integration showing connection state

## Phase 2: GhostLLM Integration
- [ ] WebSocket client for streaming responses
- [ ] REST client fallback
- [ ] Session management (maintain session_id)
- [ ] Context buffer management
- [ ] Handle model swap notifications (<250ms pause target)
- [ ] Error handling and reconnection logic

## Phase 3: Core Commands
- [ ] `/explain` - Explain selected code
- [ ] `/fix` - Fix errors in selection/file
- [ ] `/test` - Generate tests for selection
- [ ] `/refactor` - Refactor selected code
- [ ] `/complete` - Inline completions
- [ ] `<leader>z` - Toggle Zeke panel

## Phase 4: File Operations
- [ ] Apply patches with GhostWarden approval flow
- [ ] Multi-file edit support
- [ ] Undo/redo integration
- [ ] Git integration for diff views
- [ ] Tree-sitter integration for context awareness

## Phase 5: Advanced Features
- [ ] Project-wide refactoring support
- [ ] Background indexing for better context
- [ ] Custom action definitions
- [ ] Snippet generation
- [ ] Documentation generation
- [ ] Code review mode

## Phase 6: Configuration
- [ ] Config file support (.zeke.toml)
- [ ] Keybinding customization
- [ ] Theme support
- [ ] Model preference settings
- [ ] Auto-approval rules configuration

## Technical Requirements
- [ ] Pure Lua implementation (no Python dependencies)
- [ ] Lazy.nvim compatible
- [ ] Neovim 0.9+ support
- [ ] LSP integration for better context
- [ ] Treesitter integration
- [ ] Telescope.nvim integration

## Performance Goals
- [ ] < 50ms command response time
- [ ] < 100ms panel open/close
- [ ] Minimal memory footprint
- [ ] Non-blocking operations
- [ ] Efficient diff algorithms

## Testing
- [ ] Unit tests for core logic
- [ ] Integration tests with mock GhostLLM
- [ ] Performance benchmarks
- [ ] Multi-provider testing
- [ ] Error recovery testing