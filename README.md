# workspace-tools.nvim

Save editing workspaces and search their restoration history.

## Features

- Store native session layouts, views and named workspace history.
- Restore deliberately while protecting modified buffers.
- Select project Python environments independently of session persistence.

## Requirements

Neovim **0.11+**. No required plugin dependencies. An installed selection-tools.nvim enhances workspace search.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/workspace-tools.nvim",
  main = "workspace_tools",
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("workspace_tools").setup({})
```

## Usage

```vim
:WorkspaceSave Review
:WorkspaceSearch
:WorkspaceInfo
```

## Documentation

- [Complete reference](doc/workspace-tools.txt) — `:help workspace-tools`.
- Diagnose availability with `:checkhealth workspace_tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
