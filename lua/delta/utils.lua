local M = {}

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

return M
