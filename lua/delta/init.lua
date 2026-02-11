local M = {}

-- TODO because this is a module designed for consumption by other lua code, figure out what kind of contract to expose. Kind of like mini.diff. This isn't the type of plugin that's meant to make user commands or keybinds; deltaview.nvim does that.
-- expose functions, expose data; for example, deltaview doesn't want to parse things like it does for delta; just expose DiffData
-- the one thing I don't want is a modifiable buffer, because that is a recipe for disaster.
M.setup = function()
    -- :TestDeltaDiff command
    vim.api.nvim_create_user_command('TestDeltaDiff', function()
        M.run_delta_diff()
    end, { desc = "Run delta diff on current buffer" })
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
