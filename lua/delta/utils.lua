local M = {}

--- @param text string
--- @param lang string
--- @return table<number, table<LineHighlight>>
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

--- @param bufnr number
--- @return table<number, LineHighlight>
M.capture_highlights = function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local line_highlights = {}
    local unique_hl_groups = {} -- Track unique highlight groups

    for line_number, line_content in ipairs(lines) do
        local highlights = {}
        if not line_content then
            return highlights
        end

        local prev_group = nil
        local start_col = nil

        for col = 0, #line_content do
            local pos_data = vim.inspect_pos(bufnr, line_number - 1, col)
            local current_group = nil

            if pos_data.treesitter and #pos_data.treesitter > 0 then
                -- get the most specific capture (last one that is not a metadata pattern)
                for i = #pos_data.treesitter, 1, -1 do
                    local group = pos_data.treesitter[i]
                    if not M.is_metadata_pattern(group.capture) then
                        current_group = group.hl_group
                        break
                    end
                end
            end

            if current_group ~= prev_group then
                if prev_group and start_col then
                    table.insert(highlights, {
                        col = start_col,
                        end_col = col,
                        hl_group = prev_group
                    })
                    -- Add to unique groups if not already present
                    if not unique_hl_groups[prev_group] then
                        unique_hl_groups[prev_group] = true
                    end
                end
                start_col = col
                prev_group = current_group
            end
        end
        line_highlights[line_number] = highlights
    end

    -- Print all unique highlight groups
    print("Unique highlight groups captured:")
    for hl_group, _ in pairs(unique_hl_groups) do
        print("  " .. hl_group)
    end

    return line_highlights
end

--- @param bufnr number
--- @param highlights table<number, table<LineHighlight>>
M.apply_highlights = function(bufnr, highlights)
    local ns_id = vim.api.nvim_create_namespace("manual_treesitter_highlights")

    for line_number, highlight in pairs(highlights) do
        for _, hl in ipairs(highlight) do
            -- lines are 0 based
            local success, err = pcall(function()
                vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_number, hl.col, {
                    end_col = hl.end_col,
                    hl_group = hl.hl_group,
                    priority = hl.priority
                })
            end)

            if not success then
                print("Error applying highlight:")
                vim.print(vim.api.nvim_buf_get_lines(bufnr, line_number, line_number + 1, true))
                print("  hl: " .. vim.inspect(hl))
                print("  error: " .. tostring(err))
            end
        end
    end
    return ns_id
end

--- @param bufnr number
M.freeze_and_isolate_highlights = function(bufnr)
    vim.treesitter.stop(bufnr)

    -- disabling traditional syntax highlighting
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('syntax off')
    end)
end

--- @param bufnr number
--- @param callbacks table<function>
M.on_treesitter_parse_complete = function(bufnr, callbacks)
    local parser = vim.treesitter.get_parser(bufnr)

    -- TODO register cbs fires when the lua markdown fences have finished being parsed, but before the actual code inside the fences are parsed
    -- we need to fire a waiter until the last valid line of code (iterate from the bottom until the first triple backticks are hit) has a highlight
    -- do a poller that runs ever 100 and stops when the line above the last triple backtick has a highlight.
    -- edge case: if the last hunk looks like ```lua\n``` such that there is nothing to be highlighted
    -- if there is text/characters AND no highlights exist, continue polling
    parser:register_cbs({
        on_changedtree = function()
            vim.schedule(function()
                print("Treesitter parsed! Tree changed.")
                for _, fn in ipairs(callbacks) do
                    fn()
                end
            end)
        end
    })
end

--- Helper function to determine language identifier from file extension
--- @param filename string
--- @return string language identifier for markdown code fence
M.get_language_from_filename = function(filename)
    local extension = filename:match("%.([^%.]+)$")
    if not extension then
        return ""
    end

    -- map common extensions to markdown language identifiers
    local ext_to_lang = {
        lua = "lua",
        py = "python",
        js = "javascript",
        ts = "typescript",
        jsx = "jsx",
        tsx = "tsx",
        rs = "rust",
        go = "go",
        c = "c",
        cpp = "cpp",
        cc = "cpp",
        cxx = "cpp",
        h = "c",
        hpp = "cpp",
        java = "java",
        rb = "ruby",
        php = "php",
        cs = "csharp",
        sh = "bash",
        bash = "bash",
        zsh = "zsh",
        fish = "fish",
        vim = "vim",
        html = "html",
        css = "css",
        scss = "scss",
        sass = "sass",
        json = "json",
        xml = "xml",
        yaml = "yaml",
        yml = "yaml",
        toml = "toml",
        md = "markdown",
        sql = "sql",
        kt = "kotlin",
        swift = "swift",
        r = "r",
        R = "r",
        pl = "perl",
        ex = "elixir",
        exs = "elixir",
        erl = "erlang",
        hs = "haskell",
        scala = "scala",
        clj = "clojure",
        dart = "dart",
    }

    return ext_to_lang[extension] or extension
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

M.get_window_width = function(winid)
    local win_width = vim.api.nvim_win_get_width(winid)
    local numberwidth = vim.api.nvim_get_option_value('numberwidth', { win = winid })
    local signcolumn = vim.api.nvim_get_option_value('signcolumn', { win = winid })
    local foldcolumn = vim.api.nvim_get_option_value('foldcolumn', { win = winid })

    local gutter_width = 0
    if vim.api.nvim_get_option_value('number', { win = winid }) or vim.api.nvim_get_option_value('relativenumber', { win = winid }) then
        gutter_width = gutter_width + numberwidth
    end
    if signcolumn == 'yes' or signcolumn == 'auto' then
        gutter_width = gutter_width + 2 -- sign column is typically 2 chars wide
    end
    gutter_width = gutter_width + tonumber(foldcolumn)

    return win_width - gutter_width
end

--- Read file contents without opening a vim buffer
--- @param filepath string Full path to the file
--- @return table|nil lines Array of lines from the file, or nil if error
M.read_file_lines = function(filepath)
    local file = io.open(filepath, 'r')
    if not file then
        return nil
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    return lines
end

-- helper for test troubleshooting: Recursively print keys and values of a table
M.print_table = function(tbl, indent)
    indent = indent or 0
    local space = string.rep("  ", indent)

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            print(space .. tostring(key) .. ":")
            M.print_table(value, indent + 1)
        else
            print(space .. tostring(key) .. ": " .. tostring(value))
        end
    end
end


---@class LineHighlight
---@field col number starting column
---@field end_col number end column
---@field priority string priority
---@field hl_group string highlight group

return M
