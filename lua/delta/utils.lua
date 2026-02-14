local M = {}

--- @param bufnr number
--- @param highlights table<number, LineHighlight[]>
M.apply_highlights = function(bufnr, highlights)
    -- TODO optionally take in the namespace. This way, if you don't specify, highlights are additive. If you do, you can override existing highlights
    local ns_id = vim.api.nvim_create_namespace("manual_treesitter_highlights")

    for line_number, highlight in pairs(highlights) do
        for _, hl in ipairs(highlight) do
            -- lines are 0 based
            local success, err = pcall(function()
                vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_number, hl.col, {
                    end_col = hl.end_col,
                    hl_group = hl.hl_group,
                    priority = tonumber(hl.priority)
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

return M
