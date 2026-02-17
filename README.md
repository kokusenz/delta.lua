# delta.lua

[delta](https://github.com/dandavison/delta) (git-delta) in neovim, with treesitter syntax highlighting. Exposes granular functions for the steps to create these buffers, so consumers can customize their view experience.

![delta.lua screenshot]()

## Why?

TODO write this section

## Features

TODO write this section

## Requirements

- Neovim >= 0.9
- Git (for git diff)

## API

delta.lua is designed as a library for other plugins. It creates diff buffers but does not control display.

### Buffer Creation

```lua
local delta = require('delta')

-- Git diff
bufnr = delta.git_diff(ref, path)  -- ref: "HEAD", "main", etc. path: optional file path

-- Text diff
bufnr = delta.text_diff(s1, s2, opts)  -- opts: { language, context }

-- Patch/diffstring
bufnr = delta.diff_diffstring(diffstring, opts)  -- opts: { git, language }
```

### Highlighting

```lua
delta.highlight_delta_artifacts(bufnr)         -- Highlight titles/separators
delta.syntax_highlight_git_diff(bufnr)         -- Treesitter syntax (git only)
delta.diff_highlight_diff(bufnr, opts)  -- Two-tier diff highlighting
```

### Window Setup

```lua
delta.setup_delta_statuscolumn(bufnr, winid)  -- Setup line numbers (call after displaying buffer)
```

### Typical Usage

```lua
local delta = require('delta')

-- 1. Create buffer
local bufnr = delta.git_diff('HEAD')

-- 2. Display buffer (your window/split/float)
vim.api.nvim_win_set_buf(0, bufnr)

-- 3. Apply highlighting
delta.highlight_delta_artifacts(bufnr)
delta.syntax_highlight_git_diff(bufnr)
delta.diff_highlight_diff(bufnr)

-- 4. Setup statuscolumn
delta.setup_delta_statuscolumn(bufnr)
```

See `lua/delta/init.lua` comments for text diff and patch workflows.

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

The fzf file picker might be available out of the box, depending on how it was installed. If it does not work, you may need [additional setup](https://github.com/junegunn/fzf/blob/master/README-VIM.md) in your neovim config. Try adding the fzf binary to your `&runtimepath`, or installing fzf's vim integration using a package manager.

## Configuration

TODO write this section

## Troubleshooting
TODO write this section

## Feature Roadmap

TODO write this section

## Contributing

TODO write this section
