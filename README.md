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

### Buffer Creation
The following functions created formatted text files without any highlighting
The data of what is an added line, what is a deleted line, and what is a context line is not visible. That data is stored as a vim buffer variable, `vim.b[bufnr].delta_diff_data_set`.

TODO update more documentation down here, related to opts
```lua
-- Git diff
bufnr = Delta.git_diff(ref, path)  -- ref: "HEAD", "main", etc. path: optional file path

-- Text diff
bufnr = Delta.text_diff(s1, s2, language, opts)

-- Patch/diffstring
bufnr = Delta.patch_diff(diffstring, is_git_diff, language, opts)
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
