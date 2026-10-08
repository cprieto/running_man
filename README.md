# Running Man

A small Neovim plugin that puts `▶` in the gutter beside Rust binary entry points reported by Rust Analyzer.

Requires Neovim 0.11+ and an attached Rust Analyzer client, configured through rustaceanvim or your usual LSP setup. Running Man does not start or configure the language server.

## Install with lazy.nvim

For this local checkout:

```lua
{
  dir = '/Users/cprieto/Code/running_man',
  ft = 'rust',
  opts = {},
}
```

Once published, replace `dir` with the GitHub repository string. Lazy automatically calls `require('running_man').setup(opts)`; you can also set `main = 'running_man'` explicitly.

Optional settings (shown with defaults):

```lua
opts = {
  sign_text = '▶',
  sign_hl_group = 'RunningManSign',
  priority = 10,
  debounce_ms = 200,
}
```

The highlight defaults to `DiagnosticOk`. Your window's `signcolumn` must allow signs (`auto` or `yes`).

## Behavior

Only the current buffer is queried and decorated. Signs refresh after edits, saves, buffer entry, and LSP attachment; leaving the buffer clears them. In-flight requests are cancelled and stale responses ignored.

Detection uses Rust Analyzer's [`experimental/runnables`](https://github.com/rust-lang/rust-analyzer/blob/master/docs/book/src/contributing/lsp-extensions.md#runnables) request, including when rustaceanvim manages the client. Cargo `run` entries with a location in the current file receive a sign at their selection range. Test, benchmark, check, and locationless entries are ignored. No source scanning, regex, or Tree-sitter detection is used. Shell runnables are not supported in this first version.

To refresh manually:

```lua
require('running_man').refresh()
```

This version only detects and displays entry points. It has no execution commands or picker.

## Verification

```sh
nvim --headless -u NONE -l tests/runnables.lua
```
