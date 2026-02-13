local M = {}

-- TODO because this is a module designed for consumption by other lua code, figure out what kind of contract to expose. Kind of like mini.diff. This isn't the type of plugin that's meant to make user commands or keybinds; deltaview.nvim does that.
-- expose functions, expose data; for example, deltaview doesn't want to parse things like it does for delta; just expose DiffData
-- the one thing I don't want is a modifiable buffer, because that is a recipe for disaster.
M.setup = function()
    -- :TestDeltaDiff command
    M.initialize_hl_groups()

    vim.api.nvim_create_user_command('TestDeltaDiff', function()
        M.run_delta_diff()
    end, { desc = "Run delta diff on current buffer" })
end

M.initialize_hl_groups = function()
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
end

M.run_delta_diff = function()
    local diff = require('delta.diff')

    local cur_path
    local ok, expanded = pcall(vim.fn.expand, '%:p')
    if ok and expanded ~= '' then
        cur_path = expanded
    else
        cur_path = nil
    end
    diff.git_diff('HEAD', cur_path)
end

return M
