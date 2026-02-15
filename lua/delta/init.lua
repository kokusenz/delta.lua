local M = {}

-- TODO because this is a module designed for consumption by other lua code, figure out what kind of contract to expose. Kind of like mini.diff. This isn't the type of plugin that's meant to make user commands or keybinds; deltaview.nvim does that.
-- expose functions, expose data; for example, deltaview doesn't want to parse things like it does for delta; just expose DiffData
-- the one thing I don't want is a modifiable buffer, because that is a recipe for disaster.

-- TODO verify what flags delta has that I want to support. For example, similarity threshold

---@param opts DeltaOpts
M.setup = function(opts)
    require('delta.config').setup(opts)

    -- Initialize highlight groups
    M.initialize_hl_groups()

    -- TODO when writing unit tests, write a test case for when colorschemes change to assert this behavior
    -- another example test case is that highlights change to light mode when background changes
    -- Reinitialize highlight groups when colorscheme changes
    vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('DeltaHighlights', { clear = true }),
        callback = M.initialize_hl_groups,
        desc = 'Reinitialize Delta highlight groups after colorscheme change'
    })

    -- :TestDeltaDiff command
    vim.api.nvim_create_user_command('TestDeltaDiff', function(topts)
        local ref = topts.args ~= '' and topts.args or 'HEAD'
        M.run_delta_diff(ref)
    end, { desc = "Run delta diff on current buffer", nargs = '?' })
end

M.initialize_hl_groups = function()
    local config = require('delta.config')

    -- Detect background (light or dark)
    local bg = vim.o.background or 'dark'

    -- Select appropriate highlight group set
    local hl_groups = config.options.highlight_groups[bg]

    if not hl_groups then
        vim.notify(
            string.format("Delta: No highlight groups defined for background='%s', falling back to 'dark'", bg),
            vim.log.levels.WARN
        )
        hl_groups = config.options.highlight_groups.dark
    end

    -- Apply custom highlight groups from config
    for hl_group_name, hl_def in pairs(hl_groups) do
        vim.api.nvim_set_hl(0, hl_group_name, hl_def)
    end
end

M.run_delta_diff = function(ref)
    local diff = require('delta.diff')

    ref = ref or 'HEAD'
    local cur_path
    local ok, expanded = pcall(vim.fn.expand, '%:p')
    if ok and expanded ~= '' then
        cur_path = expanded
    else
        cur_path = nil
    end
    diff.git_diff(ref, cur_path)
end

return M
