local M = {}
local config = require('delta.config')
local utils_highlighting = require('delta.utils_highlighting')
local diff = require('delta.diff')

-- TODO because this is a module designed for consumption by other lua code, figure out what kind of contract to expose. Kind of like mini.diff. This isn't the type of plugin that's meant to make user commands or keybinds; deltaview.nvim does that.
-- expose functions, expose data; for example, deltaview doesn't want to parse things like it does for delta; just expose DiffData
-- the one thing I don't want is a modifiable buffer, because that is a recipe for disaster.

-- TODO verify what flags delta has that I want to support. For example, similarity threshold

---@param opts DeltaOpts
M.setup = function(opts)
    config.setup(opts)
    utils_highlighting.initialize_hl_groups()

    -- :TestDeltaDiff command
    vim.api.nvim_create_user_command('TestDeltaDiff', function(topts)
        local ref = topts.args ~= '' and topts.args or 'HEAD'
        M.run_delta_diff(ref)
    end, { desc = "Run delta diff on current buffer", nargs = '?' })
end

M.run_delta_diff = function(ref)
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
