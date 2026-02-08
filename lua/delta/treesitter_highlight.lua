local M = {}

---Get treesitter language from filetype
---@param filetype string
---@return string|nil lang The treesitter language name, or nil if not available
local function get_lang_from_filetype(filetype)
    local lang = vim.treesitter.language.get_lang(filetype)
    if not lang then
        return nil
    end

    -- Check if parser is actually available
    local ok = pcall(vim.treesitter.language.inspect, lang)
    if not ok then
        return nil
    end

    return lang
end

---Apply treesitter highlighting to a target buffer by parsing source content
---This is based on the approach used by diffs.nvim
---@param source_buf number Source buffer to get content from
---@param target_buf number Target buffer to apply highlighting to
---@param line_map table<number, number> Maps source line numbers (1-indexed) to target line numbers (1-indexed)
---@param filetype string The filetype to use for syntax highlighting
---@return number count Number of extmarks created
function M.apply_treesitter_highlighting(source_buf, target_buf, line_map, filetype)
    if not vim.api.nvim_buf_is_valid(source_buf) or not vim.api.nvim_buf_is_valid(target_buf) then
        print("[Delta] Invalid buffer(s) provided")
        return 0
    end

    -- Get treesitter language from filetype
    local lang = get_lang_from_filetype(filetype)
    if not lang then
        print(string.format("[Delta] No treesitter language found for filetype: %s", filetype))
        return 0
    end

    print(string.format("[Delta] Using treesitter language: %s for filetype: %s", lang, filetype))

    -- Build arrays of source lines and mapping
    local code_lines = {}
    local target_line_map = {} -- Maps code array index (0-indexed) to target buffer line (0-indexed)

    -- Sort line_map by source line number for consistent ordering
    local sorted_src_lines = {}
    for src_line, _ in pairs(line_map) do
        table.insert(sorted_src_lines, src_line)
    end
    table.sort(sorted_src_lines)

    for _, src_line in ipairs(sorted_src_lines) do
        local tgt_line = line_map[src_line]
        local ok, lines = pcall(vim.api.nvim_buf_get_lines, source_buf, src_line - 1, src_line, false)
        if ok and lines[1] then
            target_line_map[#code_lines] = tgt_line - 1 -- 0-indexed for both
            table.insert(code_lines, lines[1])
        end
    end

    if #code_lines == 0 then
        print("[Delta] No code lines to highlight")
        return 0
    end

    print(string.format("[Delta] Parsing %d lines with treesitter", #code_lines))

    -- Parse the code as a string
    local code = table.concat(code_lines, '\n')
    local ok, parser = pcall(vim.treesitter.get_string_parser, code, lang)
    if not ok or not parser then
        print(string.format("[Delta] Failed to create treesitter parser for lang: %s", lang))
        return 0
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        print("[Delta] Treesitter parse returned no trees")
        return 0
    end

    -- Get highlight query for the language
    local query = vim.treesitter.query.get(lang, 'highlights')
    if not query then
        print(string.format("[Delta] No highlight query found for lang: %s", lang))
        return 0
    end

    -- Create namespace for our highlights
    local ns_id = vim.api.nvim_create_namespace("delta_treesitter_highlight")
    local count = 0

    -- Iterate through all captures and create extmarks
    for id, node, metadata in query:iter_captures(trees[1]:root(), code) do
        local capture_name = '@' .. query.captures[id] .. '.' .. lang
        local sr, sc, er, ec = node:range() -- Range in the parsed string (0-indexed)

        -- Map string positions to buffer positions
        local buf_sr = target_line_map[sr]
        if buf_sr then
            local buf_er = target_line_map[er] or buf_sr

            -- Apply appropriate priority (syntax highlights should be lower than diff highlights)
            local priority = 199 -- PRIORITY_SYNTAX from diffs.nvim

            local ok_mark, err = pcall(vim.api.nvim_buf_set_extmark, target_buf, ns_id, buf_sr, sc, {
                end_row = buf_er,
                end_col = ec,
                hl_group = capture_name,
                priority = priority,
            })

            if ok_mark then
                count = count + 1
            else
                print(string.format("[Delta] Failed to set extmark: %s", tostring(err)))
            end
        end
    end

    print(string.format("[Delta] Applied %d treesitter extmarks to target buffer %d", count, target_buf))
    return count
end

---Automatically detect filetype from source buffer and apply highlighting
---@param source_buf number Source buffer to get content and filetype from
---@param target_buf number Target buffer to apply highlighting to
---@param line_map table<number, number> Maps source line numbers to target line numbers
---@return number count Number of extmarks created
function M.apply_from_source_buffer(source_buf, target_buf, line_map)
    if not vim.api.nvim_buf_is_valid(source_buf) then
        print("[Delta] Invalid source buffer")
        return 0
    end

    -- Get filetype from source buffer
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = source_buf })
    if not filetype or filetype == "" then
        print(string.format("[Delta] Source buffer %d has no filetype set", source_buf))
        return 0
    end

    print(string.format("[Delta] Detected filetype: %s from source buffer %d", filetype, source_buf))
    return M.apply_treesitter_highlighting(source_buf, target_buf, line_map, filetype)
end

---Alternative approach: Just set the filetype on the target buffer
---and let Neovim's native highlighting handle it
---@param target_buf number Target buffer to set filetype on
---@param filetype string The filetype to set
function M.set_filetype(target_buf, filetype)
    if not vim.api.nvim_buf_is_valid(target_buf) then
        print("[Delta] Invalid target buffer")
        return
    end

    vim.api.nvim_set_option_value("filetype", filetype, { buf = target_buf })
    print(string.format("[Delta] Set filetype '%s' on buffer %d", filetype, target_buf))
end

return M
