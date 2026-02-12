local M = {}

--- @param text string
--- @param lang string
--- @return table<number, LineHighlight[]>
M.get_treesitter_highlight_captures = function(text, lang)
    local language_tree = vim.treesitter.get_string_parser(text, lang)
    language_tree:parse()
    local line_highlights = {}

    local text_lines = vim.split(text, '\n', { plain = true })

    language_tree:for_each_tree(function(tree, ltree)
        local tree_lang = ltree:lang()
        local query = vim.treesitter.query.get(tree_lang, 'highlights')
        if not query then
            return
        end

        for id, node, metadata in query:iter_captures(tree:root(), text) do
            local capture_name = query.captures[id]
            if M.is_metadata_pattern(capture_name) then
                goto continue
            end
            local start_row, start_col, end_row, end_col = node:range()

            for row = start_row, end_row do
                line_highlights[row] = line_highlights[row] or {}

                local row_start_col = (row == start_row) and start_col or 0
                local line_length = text_lines[row + 1] and #text_lines[row + 1] or 0
                local row_end_col = (row == end_row) and end_col or line_length

                table.insert(line_highlights[row], {
                    col = row_start_col,
                    end_col = row_end_col,
                    priority = (metadata and metadata.priority) or id,
                    hl_group = "@" .. capture_name .. "." .. tree_lang
                })
            end
            ::continue::
        end
    end)

    --M.print_table(line_highlights)
    return line_highlights
end

--- @param str string
M.is_metadata_pattern = function(str)
    local METADATA_PATTERNS = {
        "^spell",      -- @spell.lua, @spell
        "^nospell",    -- @nospell.lua
        "^conceal",    -- @conceal
        "^definition", -- @definition (for LSP navigation)
        "^scope",      -- @scope (for scope detection)
        "^scope",      -- @scope (for scope detection)
    }

    for _, pattern in ipairs(METADATA_PATTERNS) do
        if str:match(pattern) then
            return true
        end
    end
    return false
end

---@class LineHighlight
---@field col number starting column
---@field end_col number end column
---@field priority number priority
---@field hl_group string highlight group

return M
