local M = {}


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

-- Function to reapply captured highlights
--M.reapply_highlights = function(bufnr, line_number, highlights)
--    -- Create a namespace for our manual highlights
--    local ns_id = vim.api.nvim_create_namespace("frozen_treesitter_highlights")
--
--    -- Clear any existing highlights on this line
--    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, line_number, line_number + 1)
--
--    -- Apply each captured highlight
--    for _, hl in ipairs(highlights) do
--        vim.api.nvim_buf_add_highlight(
--            bufnr,
--            ns_id,
--            hl.hl_group,
--            line_number,
--            hl.col,
--            hl.end_col
--        )
--    end
--
--    return ns_id
--end

-- Function to reapply captured highlights
M.reapply_highlights = function(bufnr, highlights)
    -- Create a namespace for our manual highlights
    local ns_id = vim.api.nvim_create_namespace("frozen_treesitter_highlights")
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    for line_number, highlight in pairs(highlights) do
        -- Apply each captured highlight
        for _, hl in ipairs(highlight) do
            vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_number-1, hl.col, {
                end_col = hl.end_col,
                hl_group = hl.hl_group,
                priority = 101
            })
            --vim.api.nvim_buf_add_highlight(
            --    bufnr,
            --    ns_id,
            --    hl.hl_group,
            --    line_number,
            --    hl.col,
            --    hl.end_col
            --)
        end
    end
    return ns_id
end

M.capture_highlights = function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local line_highlights = {}
    for line_number, line_content in ipairs(lines) do
        local highlights = {}
        if not line_content then
            return highlights
        end

        -- Sample each position on the line
        local prev_group = nil
        local start_col = nil

        for col = 0, #line_content do
            local pos_data = vim.inspect_pos(bufnr, line_number - 1, col)
            local current_group = nil

            -- Get treesitter highlight at this position
            if pos_data.treesitter and #pos_data.treesitter > 0 then
                -- Get the most specific capture (last one that is not a metadata pattern)
                for i = #pos_data.treesitter, 1, -1 do
                    local group = pos_data.treesitter[i]
                    if not M.is_metadata_pattern(group.capture) then
                        current_group = group.hl_group
                        break
                    end
                end
            end

            -- Detect highlight changes
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

M.freeze_and_isolate_highlights = function(bufnr)
    -- 2. Stop treesitter
    vim.treesitter.stop(bufnr)

    -- 3. ALSO disable traditional syntax highlighting
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('syntax off')
    end)
end

--- Helper function to determine language identifier from file extension
--- @param filename string
--- @return string language identifier for markdown code fence
M.get_language_from_filename = function(filename)
    local extension = filename:match("%.([^%.]+)$")
    if not extension then
        return "" -- No extension, use plain code block
    end

    -- Map common extensions to markdown language identifiers
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

--- Recursively compare two tables and return differences
--- @param t1 table First table
--- @param t2 table Second table
--- @param path string|nil Current path for nested keys (for reporting)
--- @return table|nil Differences found, or nil if tables are equal
M.deep_compare = function(t1, t2, path)
    path = path or "root"
    local differences = {}

    -- Check if both are tables
    if type(t1) ~= "table" or type(t2) ~= "table" then
        if t1 ~= t2 then
            return { path = path, t1 = t1, t2 = t2 }
        end
        return nil
    end

    -- Check all keys in t1
    for k, v1 in pairs(t1) do
        local v2 = t2[k]
        local key_path = path .. "." .. tostring(k)

        if type(v1) == "table" and type(v2) == "table" then
            local nested_diff = M.deep_compare(v1, v2, key_path)
            if nested_diff then
                table.insert(differences, nested_diff)
            end
        elseif v1 ~= v2 then
            table.insert(differences, {
                path = key_path,
                t1 = v1 or 'T1LMAO',
                t2 = v2 or "LMAO"
            })
        end
    end

    -- Check for keys in t2 that aren't in t1
    for k, v2 in pairs(t2) do
        if t1[k] == nil then
            local key_path = path .. "." .. tostring(k)
            table.insert(differences, {
                path = key_path,
                t1 = 'T1NilLMao',
                t2 = v2
            })
        end
    end

    return #differences > 0 and differences or nil
end

return M
