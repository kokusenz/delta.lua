local M = {}

-- TODO because this is a module designed for consumption by other lua code, figure out what kind of contract to expose. Kind of like mini.diff. This isn't the type of plugin that's meant to make user commands or keybinds; deltaview.nvim does that.
-- expose functions, expose data; for example, deltaview doesn't want to parse things like it does for delta; just expose DiffData
-- the one thing I don't want is a modifiable buffer, because that is a recipe for disaster.

---@param opts DeltaOpts
M.setup = function(opts)
    require('delta.config').setup(opts)

    -- :TestDeltaDiff command
    M.initialize_hl_groups()

    vim.api.nvim_create_user_command('TestDeltaDiff', function(topts)
        local ref = topts.args ~= '' and topts.args or 'HEAD'
        M.run_delta_diff(ref)
    end, { desc = "Run delta diff on current buffer", nargs = '?' })
end

M.initialize_hl_groups = function()
    -- TODO determine if this is the normal way to initialize custom highlight groups
    -- Define custom highlight groups
    vim.api.nvim_set_hl(0, 'DeltaDiffAddedLine', {
        bg = '#002800', -- dark green background
        default = true
    })

    vim.api.nvim_set_hl(0, 'DeltaDiffRemovedLine', {
        bg = '#3f0001', -- dark red background
        default = true
    })

    vim.api.nvim_set_hl(0, 'DeltaDiffAddedWord', {
        bg = '#006000', -- brighter green
        default = true
    })

    vim.api.nvim_set_hl(0, 'DeltaDiffRemovedWord', {
        bg = '#901011', -- brighter red
        default = true
    })

    vim.api.nvim_set_hl(0, 'DeltaTitle', {
        fg = '#24acd4', -- light blue
        default = true
    })
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
