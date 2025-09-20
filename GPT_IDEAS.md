zeke.nvim & terminal wiring

Point your plugin and CLI to the Ghostly Router using OpenAI semantics:

Neovim (Lua) minimal example

-- zeke.nvim config snippet
vim.g.zeke_api_base = "http://ghostly.local:8080/v1"
vim.g.zeke_api_key  = "sk-local"  -- not used, placeholder
vim.g.zeke_model    = "auto"      -- ignored; router picks

-- Code actions route via tags in the prompt
require("zeke").setup({
  provider = "openai",
  model = "auto",
  temperature = 0.2,
  max_tokens = 1024,
  system = "You are Zeke, a terse expert coding assistant.",
  -- example keymaps
  keymaps = {
    refactor = "<leader>zr",
    explain  = "<leader>ze",
    tests    = "<leader>zt",
  }
})


Terminal (Claude-CLI style)

export OPENAI_API_BASE="http://ghostly.local:8080/v1"
export OPENAI_API_KEY="sk-local"
# Now any OpenAI-compatible CLI (or your own) will hit Ghostly first.

5) Optional: RAG for local code/docs

Add a RAG sidecar so Ghostly can search your repos or docs before answering:

Index /srv/repos (your monorepos) with llamaindex / haystack / tantivy.

Add a ?rag=true flag to your router to do:

embed → retrieve top-k → stuff into system/context

then call Ollama

(You can bolt this on later without changing Neovim or CLI.)
