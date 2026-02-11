local M = {}

--- render the statuscolumn for a delta.lua diff buffer
--- shows: old_line ⋮ new_line
--- @param lnum number The line number (1-indexed)
--- @return string The formatted statuscolumn content
M.render = function(lnum)
    -- vim.v.virtnum is 0 for real lines, >0 for wrapped continuation lines
    if vim.v.virtnum > 0 then
        return '' -- Show nothing for wrapped lines
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local line_map = vim.b[bufnr].delta_line_map

    if not line_map then
        -- fallback to regular line numbers
        return string.format('%4d ', lnum)
    end

    local map = line_map[lnum]

    if not map then
        -- fallback if line number not found in map
        return ''
    end

    local old_str = map.old and string.format('%4d', map.old) or '    '
    local new_str = map.new and string.format('%-4d', map.new) or '    '

    return string.format('%s ⋮ %s', old_str, new_str)
end

return M
