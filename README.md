# finder.nvim

A vertico-style per-directory file picker for Neovim.

Unlike conventional pickers (telescope, fzf-lua) that recursively scan an
entire directory tree, **finder.nvim shows only the contents of the current
directory** and lets you navigate one level at a time. Filter with fuzzy
matching at each level; descend into a subdirectory with `<Tab>` or `/`;
ascend with `<BS>` when the filter is empty.

No external dependencies. No process spawn. No flicker on directory change.

## Why

Recursive fuzzy pickers are excellent when you know (part of) the filename
you want. They are awkward when you want to *browse* a tree, or when the
root is huge (`~`, `/`, `/var/log`) and listing everything is slow or
pointless.

finder.nvim fills that gap. It is meant to coexist with telescope or
fzf-lua, not replace them.

## Features

- Single floating window, single Neovim process — no external picker binary
- Virtual scrolling: rendering cost is O(window_height), independent of
  directory size
- Fuzzy filtering via the built-in `vim.fn.matchfuzzy`
- In-place directory navigation (no kill/respawn cycle, no flicker)
- Vertical-bar caret in the path bar for an insert-mode feel
- Zero dependencies — pure Lua, ~250 lines

## Requirements

- Neovim 0.10 or newer

## Installation

### lazy.nvim

```lua
{
  "dolmens/finder.nvim",
  keys = {
    { "<leader>.", function() require("finder").open() end, desc = "Finder" },
  },
}
```

### packer.nvim

```lua
use { "dolmens/finder.nvim" }
```

### Manual

Clone into your `runtimepath`:

```sh
git clone https://github.com/dolmens/finder.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/finder.nvim
```

## Usage

```lua
require("finder").open()                       -- start in current buffer's dir
require("finder").open({ cwd = "~/projects" }) -- start in a specific dir
```

Bind it to a key:

```lua
vim.keymap.set("n", "<leader>.", function()
  require("finder").open()
end, { desc = "Finder" })
```

## Key bindings (inside the picker)

| Key | Action |
| --- | --- |
| Printable characters | Append to the filter |
| `<BS>` | Delete one filter char; ascend to parent when filter is empty |
| `<C-w>` / `<M-BS>` | Delete the previous "word" in the filter (any non-alphanumeric char is a separator); ascend to parent when filter is empty |
| `<C-u>` | Clear the filter |
| `<Tab>` | Pick the **top** match: enter dir or open file |
| `/` | Pick top match (like `<Tab>`) when filter is non-empty; jump to `/` when filter is empty |
| `~` | Append `~` when filter is non-empty; jump to `$HOME` when filter is empty |
| `<CR>` | Pick the **highlighted** item: enter dir or open file |
| `<C-j>` / `<Down>` | Move highlight down |
| `<C-k>` / `<Up>` | Move highlight up |
| `<C-h>` | Toggle visibility of hidden (dot) files |
| `<Esc>` / `<C-c>` | Close the picker |

### `<Tab>` vs `<CR>`

`<Tab>` (and `/`) always pick the **first** entry in the filtered list,
regardless of where the highlight currently is. This is the natural
"type-then-confirm" flow.

`<CR>` picks the **currently highlighted** entry, useful after moving
with `<C-j>`/`<C-k>` to a non-top result.

## Configuration

Defaults shown — `setup()` is optional:

```lua
require("finder").setup({
  height_ratio    = 0.7,          -- floating window height as fraction of editor
  width_ratio     = 0.7,
  border          = "rounded",    -- any value accepted by nvim_open_win
  show_hidden     = true,         -- list dotfiles by default; toggle with <C-h>
  ignore_patterns = {             -- always-hidden Lua patterns
    "^%.git$",
    "^%.DS_Store$",
  },
})
```

## Comparison

|  | Recursive picker (fzf-lua, telescope) | finder.nvim |
| --- | --- | --- |
| Listing | Scans every file under cwd | Lists only the current directory |
| Huge directories | Slow or unusable | Always instant |
| "I know the filename" | Excellent | OK |
| "Let me see what's here" | Awkward | Excellent |
| Subdirectory navigation | Re-launch picker (flicker) | In-place refresh (no flicker) |
| External dependencies | `fzf` / `fd` / `rg` | None |

## Status

Early — v0. Functional and pleasant for the author's daily use, but the
API is not frozen. Issues and PRs welcome.

Known limitations / not yet implemented:

- No preview window
- No multi-select
- No file operations (create / rename / delete from within the picker)
- No bookmarks or recent history
- Only one finder window at a time

## License

[MIT](./LICENSE)
