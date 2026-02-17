local M = {}
local utils = require('delta.utils')
local utils_treesitter = require('delta.utils_treesitter')
local utils_highlighting = require('delta.utils_highlighting')
local config = require('delta.config')

--- creates a delta buffer based on a git diff
--- @param ref string
--- @param path string | nil
--- @return number | nil bufnr
M.git_diff = function(ref, path)
    -- TODO, allow for the passing in of custom flags. Specifically, context (-U) might be useful. Maybe test to assert that other flags won't break
    -- most likely will require changes and consistency in all three workflows (text diff, git diff, diff diff)
    -- see opts param in text workflow, looks like that might be the way to go; just fully implement that
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

    local data = M.get_diff_data_git(diffstring)
    local buf_id = M.create_formatted_buffer(data)
    return buf_id
end

--- creates a delta buffer based on two texts
--- @param s1 string string 1
--- @param s2 string string 2
--- @param opts? table { context: number, language: string, delta_opts: DeltaOpts }
--- @return number | nil bufnr
M.text_diff = function(s1, s2, opts)
    opts = opts or {}
    local context = opts.context or 3

    local diffstring = vim.text.diff(s1, s2, { result_type = 'unified', ctxlen = context, algorithm = 'myers' })
    --- @cast diffstring string
    local file_data = M.get_diff_data(diffstring, opts.language)

    local buf_id = M.create_formatted_buffer({ file_data })
    return buf_id
end

--- creates a delta buffer based on a diff string (for example, the text contents of a patch file)
--- @param diffstring string
--- @param opts? table { git: boolean, language: string, delta_opts: DeltaOpts }
--- @return number | nil bufnr
M.diff_diffstring = function(diffstring, opts)
    if diffstring == "" then
        vim.notify("diffstring is empty", vim.log.levels.WARN)
        return
    end

    opts = opts or {}

    if opts.git then
        local data = M.get_diff_data_git(diffstring)
        local buf_id = M.create_formatted_buffer(data)
        return buf_id
    end

    local data = M.get_diff_data(diffstring, opts.language)
    local buf_id = M.create_formatted_buffer({ data })
    return buf_id
end


--- @param diff string the unified diff string format (starting from first @@ hunk header)
--- @param language string | nil the language to use downstream when parsing. If not specified, the language will be determined from the file extension
--- @return DiffData
M.get_diff_data = function(diff, language)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DiffData
    local file_data = {
        hunks = {},
        old_path = nil,
        new_path = nil,
        language = language
    }

    local current_hunk = nil
    local old_line_num = 0  -- Track line number in old file
    local new_line_num = 0  -- Track line number in new file
    local diff_line_num = 0 -- Track line number in diff output

    for _, line in ipairs(lines) do
        diff_line_num = diff_line_num + 1

        if line:match('^@@') then
            -- hunk header: @@ -old_start,old_count +new_start,new_count @@ [context]
            local old_info, new_info, context = line:match('^@@[%s]+%-([^%s]+)[%s]+%+([^%s]+)[%s]+@@(.*)$')

            if old_info and new_info then
                local old_start_str, old_count_str = old_info:match('(%d+),?(%d*)')
                local new_start_str, new_count_str = new_info:match('(%d+),?(%d*)')

                local old_start = tonumber(old_start_str) or 1
                local old_count = tonumber(old_count_str) or 1
                local new_start = tonumber(new_start_str) or 1
                local new_count = tonumber(new_count_str) or 1

                -- Trim leading/trailing whitespace from context
                local trimmed_context = context and context:match('^%s*(.-)%s*$')
                if trimmed_context == '' then
                    trimmed_context = nil
                end

                current_hunk = {
                    lines = {},
                    old_start = old_start,
                    old_count = old_count,
                    new_start = new_start,
                    new_count = new_count,
                    header = line,
                    context = trimmed_context
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


--- @param diff string the git diff string format, made up of multiple unified diff strings
--- @return DiffData[]
M.get_diff_data_git = function(diff)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DiffData[]
    local result = {}

    --- @type table<string>
    local current_file_lines = {}
    local current_old_path = nil
    local current_new_path = nil

    local function finalize_current_file(file_lines)
        if #file_lines > 0 and current_new_path then
            local file_diff_string = table.concat(file_lines, '\n')
            local language = utils.get_language_from_filename(current_new_path)
            local file_data = M.get_diff_data(file_diff_string, language)
            file_data.old_path = current_old_path
            file_data.new_path = current_new_path
            table.insert(result, file_data)
        end
    end

    for _, line in ipairs(lines) do
        if line:match('^diff %-%-git') then
            -- new file starting: calculate the diff for the old file
            finalize_current_file(current_file_lines)
            current_file_lines = {}
            current_old_path = nil
            current_new_path = nil
        elseif line:match('^%-%-%-') then
            -- file header: --- a/path/to/file or --- /dev/null
            current_old_path = line:match('^%-%-%-[%s]+[ab]/(.+)$') or line:match('^%-%-%-[%s]+/dev/null$')
        elseif line:match('^%+%+%+') then
            -- file header: +++ b/path/to/file or +++ /dev/null
            current_new_path = line:match('^%+%+%+[%s]+[ab]/(.+)$') or line:match('^%+%+%+[%s]+/dev/null$')
        elseif line:match('^index ') then
            -- skip git metadata line: index hash1..hash2 mode
        else
            table.insert(current_file_lines, line)
        end
    end

    finalize_current_file(current_file_lines)

    return result
end

--- Creates and formats the contents of the delta diff buffer.
--- @param diff_data_set DiffData[]
--- @return number buf_id
M.create_formatted_buffer = function(diff_data_set)
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = diff_bufnr })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = diff_bufnr })

    local output_lines = {}
    local current_line_num = 0
    local separator_width = utils.get_window_width(0) - 8

    -- Line number mapping for statuscolumn. 1-indexed
    --- @type table<number, {old: number|nil, new: number|nil, type: "added"|"removed"|"context"|nil}>
    local line_map = {}

    local bar = '─'
    local pipe = '│'
    local top_corner = '┐'
    local bottom_corner = '┘'

    --- @type DeltaArtifact[]
    local delta_artifacts = {}

    for _, file_data in ipairs(diff_data_set) do
        if file_data.new_path and file_data.old_path then
            local filename_delta = file_data.old_path .. " ⟶   " .. file_data.new_path
            local path_title = file_data.new_path == file_data.old_path and file_data.new_path or filename_delta
            table.insert(output_lines, path_title)
            table.insert(delta_artifacts, { row_number = current_line_num, content = path_title, type = "title" })
            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1
            table.insert(output_lines, bar:rep(separator_width))
            table.insert(delta_artifacts,
                { row_number = current_line_num, content = bar:rep(separator_width), type = "fence" })

            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1

            table.insert(output_lines, "")
            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1
        end

        for _, hunk in ipairs(file_data.hunks) do
            if #file_data.hunks > 1 then
                -- show hunk header if there is more than one hunk
                local context = hunk.context and string.format("%s ", hunk.context)
                local hunk_header = context
                    and string.format("Line %d: %s", hunk.new_start, context)
                    or string.format("Line %d ", hunk.new_start)
                local formatted_hunk_header = hunk_header .. pipe
                local formatted_hunk_header_top = bar:rep(#hunk_header) .. top_corner
                local formatted_hunk_header_bottom = bar:rep(#hunk_header) .. bottom_corner
                table.insert(output_lines, formatted_hunk_header_top)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header_top, type = "fence" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1

                table.insert(output_lines, formatted_hunk_header)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header, type = "title" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1

                table.insert(output_lines, formatted_hunk_header_bottom)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header_bottom, type = "fence" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1
            end

            for _, line in ipairs(hunk.lines) do
                table.insert(output_lines, line.content)
                line.formatted_diff_line_num = current_line_num

                -- store old and new line numbers for statuscolumn (1-based indexing)
                line_map[current_line_num + 1] = {
                    old = line.old_line_num,
                    new = line.new_line_num,
                    type = line.line_type
                }

                current_line_num = current_line_num + 1
            end

            table.insert(output_lines, "")
            line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
            current_line_num = current_line_num + 1
        end
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = diff_bufnr })
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, output_lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = diff_bufnr })

    -- delta_line_map is for status column
    vim.b[diff_bufnr].delta_line_map = line_map
    vim.b[diff_bufnr].delta_diff_data_set = diff_data_set
    vim.b[diff_bufnr].delta_artifacts = delta_artifacts

    return diff_bufnr
end

--- @param bufnr number
M.highlight_delta_artifacts = function(bufnr)
    local delta_artifacts = M.get_delta_artifact_data(bufnr)
    if (delta_artifacts == nil) then return end
    --- @cast delta_artifacts DeltaArtifact[]

    --- @type table<number, LineHighlight[]>
    local artifact_highlights = {}

    for _, artifact in ipairs(delta_artifacts) do
        local line_length = #artifact.content
        artifact_highlights[artifact.row_number] = {
            {
                col = 0,
                end_col = line_length,
                priority = 150,
                hl_group = 'DeltaTitle' -- Blue/gray color typically used for comments
            }
        }
    end

    utils.apply_highlights(bufnr, artifact_highlights)
end

--- applies treesitter syntax highlights to each file one by one, if inside git
--- @param bufnr number id of buffer with the diffed contents
M.syntax_highlight_git_diff = function(bufnr)
    local diff_data_set = M.get_buf_diff_data_set(bufnr)
    if (diff_data_set == nil) then return end
    --- @cast diff_data_set DiffData[]

    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if vim.v.shell_error ~= 0 then
        vim.notify("Not in a git repository", vim.log.levels.WARN)
        return
    end

    for _, diff_data in pairs(diff_data_set) do
        local source_path = git_root .. '/' .. diff_data.new_path

        if vim.fn.filereadable(source_path) == 0 then
            vim.notify("File not found: " .. source_path, vim.log.levels.WARN)
            goto continue
        end

        local lines = utils.read_file_lines(source_path)
        if not lines then
            vim.notify('Could not read file: ' .. source_path, vim.log.levels.WARN)
            return
        end
        local content = table.concat(lines, '\n')

        M.syntax_highlight_diff(bufnr, diff_data, content)
        ::continue::
    end
end

--- highlights a file by getting the treesitter captures on the full, original file
--- @param bufnr number
--- @param diff_data DiffData
--- @param source_lines string the full, original text the diff originated from. If from git, it is the source file
M.syntax_highlight_diff = function(bufnr, diff_data, source_lines)
    -- TODO source_lines here currently refers to the "after" state. not tested with non git workflow
    -- should really be allowing both sets of data to be highlighted. 
    if diff_data.language == nil then
        vim.notify('Could not recognize language for: ' .. (diff_data.new_path or 'undefined'), vim.log.levels.WARN)
        vim.notify('Treesitter syntax highlighting will not be applied.', vim.log.levels.WARN)
        return
    end
    local tokens = utils_treesitter.get_treesitter_highlight_captures(source_lines, diff_data.language)

    --- @type table<number, LineHighlight[]>
    local new_highlights = {}
    for _, hunk in ipairs(diff_data.hunks) do
        for _, line in ipairs(hunk.lines) do
            if line.line_type == 'context' or line.line_type == 'added' then
                new_highlights[line.formatted_diff_line_num] = tokens[line.new_line_num - 1]
            end
        end
    end
    utils.apply_highlights(bufnr, new_highlights)
end

--- can be used on single file diffs or git diffs.
--- @param bufnr number
--- @param opts DeltaOpts | nil Optional highlighting configuration overrides
M.diff_highlight_diff = function(bufnr, opts)
    local diff_data_set = M.get_buf_diff_data_set(bufnr)
    if (diff_data_set == nil) then return end
    --- @cast diff_data_set DiffData[]
    local highlight_opts = vim.tbl_deep_extend('force', config.options, opts or {})
    local file_highlights = utils_highlighting.get_highlights_multiple_files(diff_data_set, highlight_opts)
    utils.apply_highlights(bufnr, file_highlights)
end

--- @param bufnr number
--- @param winid number | nil defaults to current window
M.setup_delta_statuscolumn = function(bufnr, winid)
    local win = winid or vim.api.nvim_get_current_win()


    if vim.api.nvim_win_get_buf(win) ~= bufnr then
        error(string.format(
            "Buffer %d must be displayed in window %d before calling setup_delta_statuscolumn. " ..
            "Please display the buffer first: vim.api.nvim_win_set_buf(%d, %d)",
            bufnr, winid, win, bufnr
        ))
    end

    local current_statuscolumn = vim.api.nvim_get_option_value('statuscolumn', { win = win })

    vim.api.nvim_set_option_value('statuscolumn',
        '%{%v:lua.require("delta.statuscolumn").render(v:lnum)%}',
        { win = 0 }
    )

    vim.api.nvim_create_autocmd('BufLeave', {
        buffer = bufnr,
        once = true,
        callback = function()
            -- restore statuscolumn when leaving the buffer
            if vim.api.nvim_win_is_valid(0) then
                vim.api.nvim_set_option_value('statuscolumn', current_statuscolumn, { win = win })
            end
        end
    })
end

--- @param bufnr number
--- @return DiffData[] | nil
M.get_buf_diff_data_set = function(bufnr)
    local delta_files_data = vim.b[bufnr].delta_diff_data_set

    if delta_files_data == nil then
        vim.notify("Buffer did not contain delta diff data", vim.log.levels.WARN)
        return
    end
    return delta_files_data
end

--- @param bufnr number
--- @return DeltaArtifact[] | nil
M.get_delta_artifact_data = function(bufnr)
    local delta_artifacts = vim.b[bufnr].delta_artifacts

    if delta_artifacts == nil then
        vim.notify("Buffer did not contain delta artifact data", vim.log.levels.WARN)
        return
    end

    return delta_artifacts
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
--- @field context string|nil Function or context name from hunk header (e.g., "def my_function(")

--- @class DiffData
--- @field hunks Hunk[] Array of hunks for this file
--- @field old_path string | nil Path to old file (from --- a/...)
--- @field new_path string | nil Path to new file (from +++ b/...)
--- @field language string | nil language of file

-- originally the types were meant to allow different artifacts to have different highlights.
-- if I want this to be useful, I would need to update my code to identify artifacts by both row and column.
-- Would be a big implementation, for little gain.
-- for little gain.
--- @class DeltaArtifact
--- @field row_number number (0-indexed)
--- @field content string
--- @field type "title"|"fence"|
