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

    return line_highlights
end

--- @param text string
--- @param lang string
--- @return string[]
M.get_treesitter_token_strings = function(text, lang)
    local language_tree = vim.treesitter.get_string_parser(text, lang)
    local tree = language_tree:parse()[1]
    local node_strings = {}

    --- Check if a node type represents free text that should be split into words
    --- @param node_type string
    --- @return boolean
    local function is_free_text_node_type(node_type)
        return node_type == "comment_content"
            or node_type == "string_content"
            or node_type == "inline"  -- Markdown free text
    end

    local function traverse(node)
        if node:child_count() == 0 then
            -- leaf node
            local node_text = vim.treesitter.get_node_text(node, text)
            if node_text and node_text ~= "" then
                local node_type = node:type()

                if is_free_text_node_type(node_type) then
                    -- Split comments into words for better diffing
                    for word in node_text:gmatch("%S+") do
                        table.insert(node_strings, word)
                    end
                else
                    table.insert(node_strings, node_text)
                end
            end
        else
            -- non-leaf node - traverse children
            for child in node:iter_children() do
                traverse(child)
            end
        end
    end

    traverse(tree:root())

    local strings = {}
    local cur_node_idx = 1
    local i = 1
    while i < #text + 1 do
        local substr_found = 0
        for j = i, #text, 1 do
            local substring = text:sub(i,j)
            if substring == node_strings[cur_node_idx] then
                substr_found = j
                break
            end
        end
        if substr_found ~= 0 then
            table.insert(strings, node_strings[cur_node_idx])
            cur_node_idx = cur_node_idx + 1
            i = substr_found + 1
        else
            table.insert(strings, text:sub(i,i))
            i = i+1
        end
    end

    return strings
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
