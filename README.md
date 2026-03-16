# delta.lua

A recreation of [delta](https://github.com/dandavison/delta) (git-delta) in neovim, with treesitter syntax highlighting. Handles the creation of scratch buffers with the diff view. Exposes granular functions for the steps to create these buffers, so consumers can customize their view experience.

This is used as the backend for [deltaview.nvim](https://github.com/kokusenz/deltaview.nvim). To test its features, I recommend using deltaview.nvim, which controls the behavior of how these diff buffers are opened and interacted with.

![delta.lua screenshot](https://github.com/user-attachments/assets/bc11efbf-f4a7-47ad-a062-ee5e4b58b50a)

## Features

- **Three diff input modes**: Create styled diff buffers from a live git diff (`git_diff`), two strings (`text_diff`), or a raw unified diff/patch string (`patch_diff`).
- **Two-tier diff highlighting**: Lines are highlighted at the line level (added/removed background) and then again at the word/token level, highlighting only the characters that changed within a line (inspired by git-delta).
- **Treesitter syntax highlighting**: The original file content is parsed with Neovim's treesitter to apply full language-aware syntax highlighting on top of the diff colours. Supports any language with a treesitter parser installed.
- **Treesitter two-tier diffing**: Treesitter tokens (or Lua-pattern word splitting as a fallback) are used as the unit of comparison for word-level diffs, instead of regex.
- **Similarity-based line pairing**: Added and removed lines within a hunk are paired by Levenshtein similarity score before word-level highlighting is applied, matching the behaviour of delta's `--max-line-distance` option. Configurable via `max_similarity_threshold`.
- **Light and dark theme support**: Highlight groups are defined separately for `dark` and `light` backgrounds and are automatically re-applied whenever the colorscheme changes.
- **Customisable highlight groups**: All eight highlight groups (`DeltaDiffAddedLine`, `DeltaDiffRemovedLine`, `DeltaDiffAddedWord`, `DeltaDiffRemovedWord`, `DeltaTitle`, `DeltaLineNrAdded`, `DeltaLineNrRemoved`, `DeltaLineNrContext`) can be overridden per-background in the setup options.
- **Delta-style statuscolumn**: A custom statuscolumn renders old and new line numbers side-by-side (`old ⋮ new`), coloured by line type, and is automatically restored when the diff buffer is closed.
- **Granular, composable API**: buffer creation, diff highlighting, syntax highlighting, and statuscolumn setup are all separate functions so consuming plugins can mix and match the steps they need.
- **Parsed diff data accessible as buffer variables** — `vim.b[bufnr].delta_diff_data_set` exposes the full structured diff (hunks, line types, old/new line numbers) for further processing by other plugins.

## Requirements

- Neovim >= 0.10
- Treesitter
- (Optional, but recommended) Git

## API

delta.lua is designed as a library for other plugins. It creates diff buffers, and allows other modules to control the behavior of how the buffers are displayed.

### Getting Started

`Delta` is defined as a global variable with all the main functions. It is equivalent to `require('delta')`.
To have your lua language server (lua_ls) show the interface for easier development, add the following to the `on_init` section of your lsp config. If you are using nvim-lsp-config, your configuration should look something like this. I recommend copying the recommend settings from [config.md](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#lua_ls) from nvim-lspconfig, and adding my modification.

```lua
vim.lsp.config('lua_ls', {
  on_init = function(client)
    -- ...
    client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
      runtime = {
        -- ...
      },
      workspace = {
        -- ...
        library = vim.list_extend( -- modification starts with vim.list_extend
            { vim.env.VIMRUNTIME },
            vim.api.nvim_get_runtime_file('lua/delta', true) -- this allows retrieval of delta annotations for easier development
        )
      },
    })
  end
})

vim.lsp.enable({'lua_ls'})
```

Examples of how diff buffers can be composed are found in `lua/delta/init.lua`.

```lua
M.test_git_diff = function(ref) -- ...
end
M.test_text_diff = function(s1, s2) -- ...
end
M.test_patch_diff = function(use_current_file, is_git, language) -- ...
end
```

### Buffer Creation
The following functions created formatted text files without any highlighting
The data of what is an added line, what is a deleted line, and what is a context line is not visible. That data is stored as a vim buffer variable, `vim.b[bufnr].delta_diff_data_set`.

```lua
-- Git diff
-- ref: "HEAD", "main", commit SHA, etc.
-- path: optional file path to limit the diff
-- opts: optional DeltaOpts overrides
bufnr = Delta.git_diff(ref, path, opts)

-- Text diff
-- s1, s2: the two strings to diff
-- language: optional language for syntax highlighting (e.g. 'lua', 'python')
-- opts: optional DeltaOpts overrides
bufnr = Delta.text_diff(s1, s2, language, opts)

-- Patch/diffstring
-- diffstring: a unified diff string (e.g. contents of a .patch file)
-- is_git_diff: true if the string is in git diff format (with file headers)
-- language: optional language for syntax highlighting; ignored when is_git_diff is true
-- opts: optional DeltaOpts overrides
bufnr = Delta.patch_diff(diffstring, is_git_diff, language, opts)
```

### Highlighting

```lua
delta.highlight_delta_artifacts(bufnr)      -- Highlight titles/separators
delta.syntax_highlight_git_diff(bufnr)      -- Treesitter syntax highlight (git_diff workflow: reads from source files on disk)
delta.syntax_highlight_diff_set(bufnr)      -- Treesitter syntax highlight (text_diff/patch_diff workflow: reconstructs content from diff data)
delta.diff_highlight_diff(bufnr, opts)      -- Two-tier diff highlighting (line-level + word-level)
```

### Window Setup

```lua
delta.setup_delta_statuscolumn(bufnr, winid)  -- Setup line numbers (call after displaying buffer)
```

## Installation

[vim.pack](https://github.com/neovim/neovim/pull/34009)

```lua
vim.pack.add({ 'https://github.com/kokusenz/delta.lua.git'})
```

Or your favorite plugin manager:

```lua
-- example: vim plug
Plug('kokusenz/delta.lua')
```

No setup needed by default. You can configure if you want:

```lua
require('delta').setup({
    highlighting = {
        max_similarity_threshold = 0.4
    }
})
```

## Configuration

```lua
require('delta').setup({
    -- Lines of context around each hunk.
    -- Passed as -U<n> to git diff, or as ctxlen to vim.text.diff.
    -- Default: 3
    context = 3,

    highlighting = {
        -- Minimum Levenshtein similarity (0.0–1.0) for two lines to be paired
        -- for word-level highlighting. Lines below this threshold get only
        -- line-level highlighting. Matches delta's --max-line-distance option.
        -- Default: 0.6
        max_similarity_threshold = 0.6,
    },

    -- One-time flag to diff new (untracked) files against /dev/null.
    -- Not recommended to set in your permanent config.
    -- Default: false
    new_file = false,

    -- Highlight group definitions, separated by background type.
    -- Each group accepts `fg`, `bg`, and `default` (boolean).
    -- When `default = true` the group will not override user-defined colors.
    highlight_groups = {
        dark = {
            DeltaDiffAddedLine   = { bg = '#002800' },
            DeltaDiffRemovedLine = { bg = '#3f0001' },
            DeltaDiffAddedWord   = { bg = '#006000' },
            DeltaDiffRemovedWord = { bg = '#901011' },
            DeltaTitle           = { fg = '#24acd4' },
            DeltaLineNrAdded     = { fg = '#008400' },
            DeltaLineNrRemoved   = { fg = '#800202' },
            DeltaLineNrContext   = { fg = '#444444' },
        },
        light = {
            DeltaDiffAddedLine   = { bg = '#cfffd0' },
            DeltaDiffRemovedLine = { bg = '#ffdee2' },
            DeltaDiffAddedWord   = { bg = '#9df0a2' },
            DeltaDiffRemovedWord = { bg = '#ffc1bf' },
            DeltaTitle           = { fg = '#0088aa' },
            DeltaLineNrAdded     = { fg = '#008400' },
            DeltaLineNrRemoved   = { fg = '#800202' },
            DeltaLineNrContext   = { fg = '#444444' },
        },
    },
})
```

## Troubleshooting
- :help delta
- Reach out via an issue

## Feature Roadmap

- LSP integration
    - Some tokens are highlighted by the language server rather than just treesitter + colorscheme. I would like to have these tokens highlighted
    - A nice quality of life to have would be lsp read operations (such as hover, or find references) from within a delta.lua buffer, similar to otter.nvim. Not completely neccesary if using deltaview.nvim, as the workflow is designed to be able to access the real code for lsp operations instantly, but I have my eye on it.
