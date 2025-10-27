const std = @import("std");

/// Shell completion generator for Zeke CLI
pub const Completions = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Completions {
        return .{ .allocator = allocator };
    }

    /// Generate completions for specified shell
    pub fn generate(self: Completions, shell: Shell, writer: anytype) !void {
        switch (shell) {
            .bash => try self.generateBash(writer),
            .zsh => try self.generateZsh(writer),
            .fish => try self.generateFish(writer),
        }
    }

    fn generateBash(self: Completions, writer: anytype) !void {
        _ = self;
        try writer.writeAll(
            \\# Bash completion for zeke
            \\# Install: source this file or copy to /etc/bash_completion.d/zeke
            \\
            \\_zeke_completions() {
            \\    local cur prev commands
            \\    COMPREPLY=()
            \\    cur="${COMP_WORDS[COMP_CWORD]}"
            \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
            \\
            \\    # Main commands
            \\    commands="chat serve auth config doctor models provider analyze edit refactor generate help version completion"
            \\
            \\    # Subcommands for each main command
            \\    case "${prev}" in
            \\        auth)
            \\            COMPREPLY=( $(compgen -W "google github openai anthropic xai azure list test" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        config)
            \\            COMPREPLY=( $(compgen -W "get set validate show edit" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        provider)
            \\            COMPREPLY=( $(compgen -W "status list set" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        completion)
            \\            COMPREPLY=( $(compgen -W "bash zsh fish" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        --model|-m)
            \\            COMPREPLY=( $(compgen -W "auto fast smart balanced local" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        --provider|-p)
            \\            COMPREPLY=( $(compgen -W "ollama claude openai xai google azure copilot" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\        --log-level)
            \\            COMPREPLY=( $(compgen -W "debug info warn error" -- ${cur}) )
            \\            return 0
            \\            ;;
            \\    esac
            \\
            \\    # Complete main commands
            \\    if [[ ${COMP_CWORD} -eq 1 ]]; then
            \\        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
            \\        return 0
            \\    fi
            \\
            \\    # Complete flags
            \\    if [[ ${cur} == -* ]]; then
            \\        COMPREPLY=( $(compgen -W "--help --version --log-level --model --provider --port --config" -- ${cur}) )
            \\        return 0
            \\    fi
            \\}
            \\
            \\complete -F _zeke_completions zeke
            \\
        );
    }

    fn generateZsh(self: Completions, writer: anytype) !void {
        _ = self;
        try writer.writeAll(
            \\#compdef zeke
            \\# Zsh completion for zeke
            \\# Install: Copy to ~/.zsh/completions/_zeke or /usr/share/zsh/site-functions/_zeke
            \\
            \\_zeke() {
            \\    local -a commands
            \\    commands=(
            \\        'chat:Chat with AI assistant'
            \\        'serve:Start HTTP server'
            \\        'auth:Manage provider authentication'
            \\        'config:View and modify configuration'
            \\        'doctor:System health diagnostics'
            \\        'models:List available models'
            \\        'provider:Manage AI providers'
            \\        'analyze:Analyze code quality'
            \\        'edit:Edit files with AI assistance'
            \\        'refactor:Refactor code'
            \\        'generate:Generate code from templates'
            \\        'completion:Generate shell completions'
            \\        'help:Show help information'
            \\        'version:Show version information'
            \\    )
            \\
            \\    local -a auth_commands
            \\    auth_commands=(
            \\        'google:Authenticate with Google OAuth'
            \\        'github:Authenticate with GitHub OAuth'
            \\        'openai:Add OpenAI API key'
            \\        'anthropic:Add Anthropic API key'
            \\        'xai:Add xAI API key'
            \\        'azure:Configure Azure OpenAI'
            \\        'list:List configured providers'
            \\        'test:Test provider authentication'
            \\    )
            \\
            \\    local -a config_commands
            \\    config_commands=(
            \\        'get:Get configuration value'
            \\        'set:Set configuration value'
            \\        'validate:Validate configuration'
            \\        'show:Show current configuration'
            \\        'edit:Edit configuration file'
            \\    )
            \\
            \\    local -a models
            \\    models=(
            \\        'auto:Auto-select best model'
            \\        'fast:Fast model (claude-haiku)'
            \\        'smart:Smart model (claude-opus)'
            \\        'balanced:Balanced model (claude-sonnet)'
            \\        'local:Local model (ollama)'
            \\    )
            \\
            \\    local -a providers
            \\    providers=(
            \\        'ollama:Local Ollama'
            \\        'claude:Anthropic Claude'
            \\        'openai:OpenAI GPT'
            \\        'xai:xAI Grok'
            \\        'google:Google Gemini'
            \\        'azure:Azure OpenAI'
            \\        'copilot:GitHub Copilot'
            \\    )
            \\
            \\    _arguments -C \
            \\        '1: :->command' \
            \\        '2: :->subcommand' \
            \\        '*: :->args' \
            \\        '(-h --help)'{-h,--help}'[Show help]' \
            \\        '(-v --version)'{-v,--version}'[Show version]' \
            \\        '--log-level[Set log level]:level:(debug info warn error)' \
            \\        '(-m --model)'{-m,--model}'[Select model]:model:->models' \
            \\        '(-p --provider)'{-p,--provider}'[Select provider]:provider:->providers' \
            \\        '--port[Server port]:port:' \
            \\        '--config[Config file path]:file:_files'
            \\
            \\    case $state in
            \\        command)
            \\            _describe 'command' commands
            \\            ;;
            \\        subcommand)
            \\            case $words[2] in
            \\                auth)
            \\                    _describe 'auth command' auth_commands
            \\                    ;;
            \\                config)
            \\                    _describe 'config command' config_commands
            \\                    ;;
            \\                completion)
            \\                    _values 'shell' 'bash' 'zsh' 'fish'
            \\                    ;;
            \\            esac
            \\            ;;
            \\        models)
            \\            _describe 'model' models
            \\            ;;
            \\        providers)
            \\            _describe 'provider' providers
            \\            ;;
            \\    esac
            \\}
            \\
            \\_zeke "$@"
            \\
        );
    }

    fn generateFish(self: Completions, writer: anytype) !void {
        _ = self;
        try writer.writeAll(
            \\# Fish completion for zeke
            \\# Install: Copy to ~/.config/fish/completions/zeke.fish
            \\
            \\# Commands
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'chat' -d 'Chat with AI assistant'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'serve' -d 'Start HTTP server'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'auth' -d 'Manage provider authentication'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'config' -d 'View and modify configuration'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'doctor' -d 'System health diagnostics'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'models' -d 'List available models'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'provider' -d 'Manage AI providers'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'analyze' -d 'Analyze code quality'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'edit' -d 'Edit files with AI'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'refactor' -d 'Refactor code'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'generate' -d 'Generate code'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'completion' -d 'Generate shell completions'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'help' -d 'Show help'
            \\complete -c zeke -f -n '__fish_use_subcommand' -a 'version' -d 'Show version'
            \\
            \\# Auth subcommands
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'google' -d 'Google OAuth'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'github' -d 'GitHub OAuth'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'openai' -d 'OpenAI API key'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'anthropic' -d 'Anthropic API key'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'xai' -d 'xAI API key'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'azure' -d 'Azure OpenAI'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'list' -d 'List providers'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from auth' -a 'test' -d 'Test authentication'
            \\
            \\# Config subcommands
            \\complete -c zeke -f -n '__fish_seen_subcommand_from config' -a 'get' -d 'Get value'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from config' -a 'set' -d 'Set value'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from config' -a 'validate' -d 'Validate config'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from config' -a 'show' -d 'Show config'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from config' -a 'edit' -d 'Edit config file'
            \\
            \\# Completion shells
            \\complete -c zeke -f -n '__fish_seen_subcommand_from completion' -a 'bash' -d 'Bash completions'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from completion' -a 'zsh' -d 'Zsh completions'
            \\complete -c zeke -f -n '__fish_seen_subcommand_from completion' -a 'fish' -d 'Fish completions'
            \\
            \\# Global options
            \\complete -c zeke -s h -l help -d 'Show help'
            \\complete -c zeke -s v -l version -d 'Show version'
            \\complete -c zeke -l log-level -d 'Log level' -xa 'debug info warn error'
            \\complete -c zeke -s m -l model -d 'Model selection' -xa 'auto fast smart balanced local'
            \\complete -c zeke -s p -l provider -d 'Provider selection' -xa 'ollama claude openai xai google azure copilot'
            \\complete -c zeke -l port -d 'Server port' -x
            \\complete -c zeke -l config -d 'Config file' -r
            \\
        );
    }
};

pub const Shell = enum {
    bash,
    zsh,
    fish,

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "fish")) return .fish;
        return null;
    }
};

/// Main entry point for completion command
pub fn generateCompletions(allocator: std.mem.Allocator, shell: Shell) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [8192]u8 = undefined;
    var writer_struct = stdout_file.writer(&buf);
    const stdout = &writer_struct.interface;

    const completions = Completions.init(allocator);
    try completions.generate(shell, stdout);
    try stdout.flush();
}
