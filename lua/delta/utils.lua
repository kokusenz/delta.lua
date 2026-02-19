local M = {}

--- @param bufnr number
--- @param highlights table<number, LineHighlight[]>
--- @param namespace string | nil optional namespace
M.apply_highlights = function(bufnr, highlights, namespace)
    local ns_id = vim.api.nvim_create_namespace(namespace or "manual_treesitter_highlights")

    for line_number, highlight in pairs(highlights) do
        for _, hl in ipairs(highlight) do
            -- lines are 0 based
            local success, err = pcall(function()
                vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_number, hl.col, {
                    end_row = hl.end_row,
                    end_col = hl.end_col,
                    hl_eol = hl.hl_eol,
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
--- @return string | nil language identifier for markdown code fence
M.get_language_from_filename = function(filename)
    local extension = filename:match("%.([^%.]+)$")
    if not extension then
        return nil
    end

    -- map common extensions to treesitter parser names
    local ext_to_lang = {
        lua = "lua",
        py = "python",
        js = "javascript",
        ts = "typescript",
        jsx = "javascriptreact",
        tsx = "typescriptreact",
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
        cs = "c_sharp",
        sh = "bash",
        bash = "bash",
        zsh = "bash",
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

    return ext_to_lang[extension]
end

--- Get a canonical file extension for a treesitter language
--- @param language string Treesitter language name (e.g., "c_sharp", "python")
--- @return string|nil extension File extension without the dot (e.g., "cs", "py")
M.get_extension_from_language = function(language)
    -- Map treesitter language names to canonical file extensions
    local lang_to_ext = {
        lua = "lua",
        python = "py",
        javascript = "js",
        typescript = "ts",
        javascriptreact = "jsx",
        typescriptreact = "tsx",
        rust = "rs",
        go = "go",
        c = "c",
        cpp = "cpp",
        java = "java",
        ruby = "rb",
        php = "php",
        c_sharp = "cs",
        bash = "sh",
        fish = "fish",
        vim = "vim",
        html = "html",
        css = "css",
        scss = "scss",
        sass = "sass",
        json = "json",
        xml = "xml",
        yaml = "yaml",
        toml = "toml",
        markdown = "md",
        sql = "sql",
        kotlin = "kt",
        swift = "swift",
        r = "r",
        perl = "pl",
        elixir = "ex",
        erlang = "erl",
        haskell = "hs",
        scala = "scala",
        clojure = "clj",
        dart = "dart",
    }

    return lang_to_ext[language]
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

--- Builds the git diff CLI flags string from effective opts.
--- To add a new git diff flag, insert a new entry here.
--- @param effective DeltaOpts
--- @return string flags_str ready to interpolate before the ref (e.g. "-U10 ")
M.build_git_diff_flags = function(effective)
    local flags = {}
    if effective.context ~= nil then
        table.insert(flags, string.format('-U%d', effective.context))
    end
    return #flags > 0 and (table.concat(flags, ' ') .. ' ') or ''
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

return M

---@class LineHighlight
---@field col number starting column
---@field end_col number end column
---@field priority number priority
---@field hl_group string highlight group
---@field end_row? number end row
---@field hl_eol? boolean
