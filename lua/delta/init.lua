local M = {}

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
