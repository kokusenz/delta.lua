local M = {}

--- @param bufnr number
--- @return table<number, LineHighlight>
M.capture_highlights = function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local line_highlights = {}
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
                end
                start_col = col
                prev_group = current_group
            end
        end
        line_highlights[line_number] = highlights
    end
    return line_highlights
end

--- @param bufnr number
--- @param highlights table<number, LineHighlight>
M.reapply_highlights = function(bufnr, highlights)
    local ns_id = vim.api.nvim_create_namespace("frozen_treesitter_highlights")
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    for line_number, highlight in pairs(highlights) do
        for _, hl in ipairs(highlight) do
            vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_number - 1, hl.col, {
                end_col = hl.end_col,
                hl_group = hl.hl_group,
                priority = 101
            })
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
---@field hl_group string highlight group

return M
