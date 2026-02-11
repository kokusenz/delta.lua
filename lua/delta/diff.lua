local M = {}
local utils = require('delta.utils')

--- @param ref string
--- @param path string | nil
M.git_diff = function(ref, path)
    -- get the output of the git diff, pass into get_hunks
    --local current_bufnr = vim.api.nvim_get_current_buf()

    local cmd = string.format('git diff %s', vim.fn.shellescape(ref))
    if path ~= nil then
        cmd = string.format(cmd .. ' -- %s', vim.fn.shellescape(path))
    end
    local handle = io.popen(cmd)

    if not handle then
        vim.notify("Failed to run git diff", vim.log.levels.ERROR)
        return
    end

    local diffstring = handle:read("*a")
    handle:close()

    if diffstring == "" then
        vim.notify("No changes detected in current file", vim.log.levels.WARN)
        return
    end

    local data = M.get_diff_data_directory(diffstring)
    -- create formatted buffer should start with a "loading" at the top
    -- then it should show markdowns of every after file, and every before file, with markdowns
    -- that will then get parsed
    local buf_id = M.create_formatted_buffer(data)
    M.highlight_git_diff(data, buf_id)
    vim.api.nvim_win_set_buf(0, buf_id)
end

--- TODO; align this with the interface that mini.diff provides, such that codecompanion/ai tooling can use for their diffs. maybe that isn't using paths; I don't know how ai does it. Maybe the llm generates patches directly, and mini.diff can take patch files as input
--- will always treat f1 as the buffer that should align with the code in your real project; will open a buffer for it as to try to lsp it up
--- @param f1 string path of file 1
--- @param f2 string path of file 2
M.vim_diff = function(f1, f2)
    -- TODO currently unfinished

    -- f1 open buffer, then get the lines content from buffer; maybe io.popen('cat ...').read
    local old_file = ''
    -- f2 do not open buffer, just need text contents
    local new_file = ''

    -- Generate diff using vim.text.diff
    local vimdiff = vim.text.diff(old_file, new_file, { ctxlen = 3, algorithm = 'myers' })
    -- launch buffer, same behavior as git_diff from here
end

--- @param diff string a diff output
--- @return DirectoryDiffData
M.get_diff_data_directory = function(diff)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DirectoryDiffData
    local result = {
        files = {}
    }

    local current_file_lines = {}
    local current_old_path = nil
    local current_new_path = nil

    local function finalize_current_file()
        if #current_file_lines > 0 and current_new_path then
            local file_diff_string = table.concat(current_file_lines, '\n')
            local file_data = M.get_diff_data_file(file_diff_string)
            file_data.old_path = current_old_path
            file_data.new_path = current_new_path
            result.files[current_new_path] = file_data

            -- reset for next file
            current_file_lines = {}
            current_old_path = nil
            current_new_path = nil
        end
    end

    for _, line in ipairs(lines) do
        if line:match('^%-%-%-') then
            -- File header: --- a/path/to/file
            finalize_current_file()

            current_old_path = line:match('^%-%-%-[%s]+[ab]/(.+)$') or line:match('^%-%-%-[%s]+(.+)$')
        elseif line:match('^%+%+%+') then
            -- File header: +++ b/path/to/file
            current_new_path = line:match('^%+%+%+[%s]+[ab]/(.+)$') or line:match('^%+%+%+[%s]+(.+)$')
        elseif line:match('^diff ') or line:match('^index ') then
            -- Skip git metadata lines (diff, index, etc.)
            -- Skip these lines
            -- Everything else belongs to the current file (hunks and their content)
        else
            table.insert(current_file_lines, line)
        end
    end

    -- Finalize the last file
    finalize_current_file()

    return result
end

--- @param diff string the diff for a file (starting from first @@ hunk header)
--- @return FileDiffData
M.get_diff_data_file = function(diff)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type FileDiffData
    local file_data = {
        hunks = {},
        old_path = nil,
        new_path = nil
    }

    local current_hunk = nil
    local old_line_num = 0  -- Track line number in old file
    local new_line_num = 0  -- Track line number in new file
    local diff_line_num = 0 -- Track line number in diff output

    for _, line in ipairs(lines) do
        diff_line_num = diff_line_num + 1

        if line:match('^@@') then
            -- hunk header: @@ -old_start,old_count +new_start,new_count @@
            local old_info, new_info = line:match('^@@[%s]+%-([^%s]+)[%s]+%+([^%s]+)[%s]+@@')

            if old_info and new_info then
                local old_start_str, old_count_str = old_info:match('(%d+),?(%d*)')
                local new_start_str, new_count_str = new_info:match('(%d+),?(%d*)')

                local old_start = tonumber(old_start_str) or 1
                local old_count = tonumber(old_count_str) or 1
                local new_start = tonumber(new_start_str) or 1
                local new_count = tonumber(new_count_str) or 1

                current_hunk = {
                    lines = {},
                    old_start = old_start,
                    old_count = old_count,
                    new_start = new_start,
                    new_count = new_count,
                    header = line
                }

                old_line_num = old_start
                new_line_num = new_start

                table.insert(file_data.hunks, current_hunk)
            end
        elseif line:match('^%+') and current_hunk then
            -- added line
            local content = line:sub(2) -- Remove '+' prefix

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = nil, -- No old line (this is added)
                new_line_num = new_line_num,
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "added"
            })

            new_line_num = new_line_num + 1
        elseif line:match('^%-') and current_hunk then
            -- removed line
            local content = line:sub(2) -- Remove '-' prefix

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = old_line_num,
                new_line_num = nil,                      -- No new line (this is removed)
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "removed"
            })

            old_line_num = old_line_num + 1
        elseif current_hunk and line:match('^%s') then
            -- context line (starts with space or is plain text in hunk)
            local content = line:sub(2) -- Remove leading space

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = old_line_num,
                new_line_num = new_line_num,
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "context"
            })

            old_line_num = old_line_num + 1
            new_line_num = new_line_num + 1
        end
    end

    return file_data
end

--- @param diff_data DirectoryDiffData
--- @return number buf_id
M.create_formatted_buffer = function(diff_data)
    -- Create buffer with proper options
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = diff_bufnr })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = diff_bufnr })

    local output_lines = {}
    local current_line_num = 0 -- Track current line number in formatted buffer (0-indexed)
    local separator_width = utils.get_window_width(0)

    local bar = '─'
    local pipe = '│'
    local top_corner = '┐'
    local bottom_corner = '┘'

    -- Process each file
    for filename, file_data in pairs(diff_data.files) do
        -- Add file header (just the new filename)
        table.insert(output_lines, filename)
        current_line_num = current_line_num + 1

        -- Use full buffer width for separator instead of just filename length
        table.insert(output_lines, bar:rep(separator_width))
        current_line_num = current_line_num + 1

        table.insert(output_lines, "") -- Blank line after filename
        current_line_num = current_line_num + 1

        -- Get language for code fence based on file extension
        local lang = utils.get_language_from_filename(filename)

        -- Process each hunk in the file
        for _, hunk in ipairs(file_data.hunks) do
            -- Add hunk header with new line number
            local hunk_header = string.format("Line %d ", hunk.new_start)
            table.insert(output_lines, bar:rep(#hunk_header) .. top_corner)
            current_line_num = current_line_num + 1

            table.insert(output_lines, hunk_header .. pipe)
            current_line_num = current_line_num + 1

            table.insert(output_lines, bar:rep(#hunk_header) .. bottom_corner)
            current_line_num = current_line_num + 1

            -- Process each line in the hunk
            for _, line in ipairs(hunk.lines) do
                -- Add content without +/- prefixes (already removed in parsing)
                table.insert(output_lines, line.content)

                -- Update formatted_diff_line_num to track position in formatted buffer
                line.formatted_diff_line_num = current_line_num
                current_line_num = current_line_num + 1
            end

            table.insert(output_lines, "") -- Blank line after hunk
            current_line_num = current_line_num + 1
        end
    end

    -- Set buffer content (temporarily make it modifiable)
    vim.api.nvim_set_option_value('modifiable', true, { buf = diff_bufnr })
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, output_lines)
    --vim.api.nvim_set_option_value('modifiable', false, { buf = diff_bufnr })

    return diff_bufnr
end

M.highlight = function(bufnr)
    local highlights = utils.capture_highlights(bufnr)
    utils.freeze_and_isolate_highlights(bufnr)
    utils.apply_highlights(bufnr, highlights)
end

--- @param diff_data DirectoryDiffData
--- @param bufnr number id of buffer with the diffed contents
M.highlight_git_diff = function(diff_data, bufnr)
    -- Find git root directory
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if vim.v.shell_error ~= 0 then
        vim.notify("Not in a git repository", vim.log.levels.WARN)
        return
    end

    -- Iterate through each file and apply highlighting
    for filename, file_data in pairs(diff_data.files) do
        -- Construct full path to source file
        local source_path = git_root .. '/' .. filename

        -- Check if file exists
        if vim.fn.filereadable(source_path) == 0 then
            vim.notify("File not found: " .. source_path, vim.log.levels.WARN)
            goto continue
        end

        M.highlight_diff_file(file_data, bufnr, source_path)

        ::continue::
    end
end


--- @param file_data FileDiffData
--- @param bufnr number
--- @param filepath string Full path to the source file
M.highlight_diff_file = function(file_data, bufnr, filepath)
    local lang = utils.get_language_from_filename(file_data.new_path)

    local lines = utils.read_file_lines(filepath)
    if not lines then
        vim.notify('Could not read file: ' .. filepath, vim.log.levels.WARN)
        return
    end

    local content = table.concat(lines, '\n')
    local tokens = utils.get_treesitter_highlight_captures(content, lang)

    --- @type table<number, table<LineHighlight>>
    local new_highlights = {}
    for _, hunk in ipairs(file_data.hunks) do
        for _, line in ipairs(hunk.lines) do
            if line.line_type == 'context' then
                new_highlights[line.formatted_diff_line_num] = tokens[line.new_line_num - 1]
            elseif line.line_type == 'added' then
                local line_length = #line.content
                local hls = tokens[line.new_line_num - 1] or {}
                local add_highlight = {
                    col = 0,
                    end_col = line_length,
                    priority = 200,
                    hl_group = 'DiffAdd'
                }

                table.insert(hls, 1, add_highlight)
                new_highlights[line.formatted_diff_line_num] = hls
            else
                local line_length = #line.content
                new_highlights[line.formatted_diff_line_num] = {
                    {
                        col = 0,
                        end_col = line_length,
                        priority = 200,
                        hl_group = 'DiffDelete'
                    }
                }
            end
        end
    end
    utils.apply_highlights(bufnr, new_highlights)
end


return M

--- @class DiffLine
--- @field content string The line content
--- @field old_line_num number|nil Line number in old file (nil if added)
--- @field new_line_num number|nil Line number in new file (nil if removed)
--- @field diff_line_num number Line number in the diff output
--- @field formatted_diff_line_num number Line number in the diff output; if formatting is applied to the buffer, this field is updated, while diff_line_num remains the same
--- @field line_type "added"|"removed"|"context" Type of change

--- @class Hunk
--- @field lines DiffLine[] Array of lines in this hunk
--- @field old_start number Starting line number in old file
--- @field old_count number Number of lines in old file
--- @field new_start number Starting line number in new file
--- @field new_count number Number of lines in new file
--- @field header string The hunk header line (e.g., "@@ -10,5 +12,6 @@")

--- @class FileDiffData
--- @field hunks Hunk[] Array of hunks for this file
--- @field old_path string|nil Path to old file (from --- a/...)
--- @field new_path string|nil Path to new file (from +++ b/...)

--- A key-value table where key is the filename, and the value is FileData
--- @class DirectoryDiffData
--- @field files table<string, FileDiffData> Map of filename to file diff data
