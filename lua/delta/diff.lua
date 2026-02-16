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
    local buf_id = M.create_formatted_buffer(data)
    return buf_id
end

--- creates a delta buffer based on two texts
--- @param s1 string string 1
--- @param s2 string string 2
--- @param opts? table { context: number, language: string, filename: string, delta_opts: DeltaOpts }
--- @return number | nil bufnr
M.text_diff = function(s1, s2, opts)
    opts = opts or {}
    local context = opts.context or 3
    local provided_language = opts.language
    local provided_filename = opts.filename

    -- Determine final filename and check for conflicts
    local filename
    if provided_filename then
        filename = provided_filename
        -- If both filename and language provided, check for conflict
        if provided_language then
            local inferred_language = utils.get_language_from_filename(filename)
            if inferred_language and inferred_language ~= provided_language then
                vim.notify(string.format(
                    "Language conflict: filename '%s' implies language '%s' but opts.language is '%s'",
                    filename, inferred_language, provided_language
                ), vim.log.levels.ERROR)
                return
            end
        end
    elseif provided_language then
        local extension = utils.get_extension_from_language(provided_language)
        if extension then
            filename = "diff." .. extension
        else
            vim.notify(string.format("Unknown language '%s', using 'diff' as filename", provided_language), vim.log.levels.WARN)
            filename = "unspecified_language"
        end
    else
        -- Neither provided, use default
        filename = "unspecified_language"
    end

    local diffstring = vim.text.diff(s1, s2, { result_type = 'unified', ctxlen = context, algorithm = 'myers' })
    --- @cast diffstring string
    local file_data = M.get_diff_data_file(diffstring)
    file_data.new_path = filename
    file_data.old_path = filename

    local files = {}
    files[filename] = file_data
    --- @type DirectoryDiffData
    local directory_diff_data = { files = files }
    local buf_id = M.create_formatted_buffer(directory_diff_data)
    return buf_id
end

--- creates a delta buffer based on a diff string (for example, the text contents of a patch file)
--- @param diffstring string string
--- @return number | nil bufnr
M.diff_diffstring = function(diffstring)
    if diffstring == "" then
        vim.notify("diffstring is empty", vim.log.levels.WARN)
        return
    end

    local data = M.get_diff_data_directory(diffstring)
    local buf_id = M.create_formatted_buffer(data)
    return buf_id
end

--- @param diff string a diff output
--- @return DirectoryDiffData
M.get_diff_data_directory = function(diff)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DirectoryDiffData
    local result = {
        files = {},
    }

    --- @type table<string>
    local current_file_lines = {}
    local current_old_path = nil
    local current_new_path = nil

    local function finalize_current_file(file_lines)
        if #file_lines > 0 and current_new_path then
            local file_diff_string = table.concat(file_lines, '\n')
            local file_data = M.get_diff_data_file(file_diff_string)
            file_data.old_path = current_old_path
            file_data.new_path = current_new_path
            result.files[current_new_path] = file_data
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

-- TODO implement a create_formatted_buffer like function that works on files and doesn't contain artifacts.
-- hopefully without too much overlap between what create_formatted_buffer already has in code
-- maybe can use some of the file level functions we've made that are unused. Need to more clearly distinguish between DirectoryDiffData and FileDiffData in code
-- for example, text_diff honestly should be file only, not directory level. No need for that top header. Currently using directory because i only have that function built

--- Creates and formats the contents of the delta diff buffer. 
--- @param diff_data DirectoryDiffData
--- @return number buf_id
M.create_formatted_buffer = function(diff_data)
    -- TODO verify that this is generating the files/hunks in the same consistent order as git diff is
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = diff_bufnr })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = diff_bufnr })

    local output_lines = {}
    local current_line_num = 0
    local separator_width = utils.get_window_width(0) - 8

    -- Line number mapping for statuscolumn
    --- @type table<number, {old: number|nil, new: number|nil, type: "added"|"removed"|"context"|nil}>
    local line_map = {}

    local bar = '─'
    local pipe = '│'
    local top_corner = '┐'
    local bottom_corner = '┘'

    --- @type DeltaArtifact[]
    local delta_artifacts = {}

    for filename, file_data in pairs(diff_data.files) do
        table.insert(output_lines, filename)
        table.insert(delta_artifacts, { row_number = current_line_num, content = filename, type = "title" })
        line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
        current_line_num = current_line_num + 1

        table.insert(output_lines, bar:rep(separator_width))
        table.insert(delta_artifacts, { row_number = current_line_num, content = bar:rep(separator_width), type = "fence" })
        line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
        current_line_num = current_line_num + 1

        table.insert(output_lines, "")
        line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
        current_line_num = current_line_num + 1

        for _, hunk in ipairs(file_data.hunks) do
            local context = hunk.context and string.format("%s ", hunk.context)
            local hunk_header = context
                and string.format("Line %d: %s", hunk.new_start, context)
                or string.format("Line %d ", hunk.new_start)
            local formatted_hunk_header = hunk_header .. pipe
            local formatted_hunk_header_top = bar:rep(#hunk_header) .. top_corner
            local formatted_hunk_header_bottom = bar:rep(#hunk_header) .. bottom_corner
            table.insert(output_lines, formatted_hunk_header_top)
            table.insert(delta_artifacts, { row_number = current_line_num, content = formatted_hunk_header_top, type = "fence" })
            line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
            current_line_num = current_line_num + 1

            table.insert(output_lines, formatted_hunk_header)
            table.insert(delta_artifacts, { row_number = current_line_num, content = formatted_hunk_header, type = "title" })
            line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
            current_line_num = current_line_num + 1

            table.insert(output_lines, formatted_hunk_header_bottom)
            table.insert(delta_artifacts, { row_number = current_line_num, content = formatted_hunk_header_bottom, type = "fence" })
            line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
            current_line_num = current_line_num + 1

            for _, line in ipairs(hunk.lines) do
                table.insert(output_lines, line.content)

                line.formatted_diff_line_num = current_line_num

                -- Store old and new line numbers for statuscolumn (1-based indexing)
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
    vim.b[diff_bufnr].delta_files_data = diff_data.files
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
    local diff_data = M.get_diff_data(bufnr)
    if (diff_data == nil) then return end
    --- @cast diff_data DirectoryDiffData
 
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if vim.v.shell_error ~= 0 then
        vim.notify("Not in a git repository", vim.log.levels.WARN)
        return
    end

    for filename, file_data in pairs(diff_data.files) do
        local source_path = git_root .. '/' .. filename

        if vim.fn.filereadable(source_path) == 0 then
            vim.notify("File not found: " .. source_path, vim.log.levels.WARN)
            goto continue
        end

        M.syntax_highlight_git_diff_file(file_data, bufnr, source_path)
        ::continue::
    end
end

--- highlights a file by getting the treesitter captures on the full, original file
--- @param file_data FileDiffData
--- @param bufnr number
--- @param filepath string Full path to the source file
M.syntax_highlight_git_diff_file = function(file_data, bufnr, filepath)
    local lang = utils.get_language_from_filename(file_data.new_path)

    if lang == nil then
        vim.notify('Could not recognize language from: ' .. file_data.new_path, vim.log.levels.WARN)
        vim.notify('Treesitter syntax highlighting will not be applied.', vim.log.levels.WARN)
        return
    end

    local lines = utils.read_file_lines(filepath)
    if not lines then
        vim.notify('Could not read file: ' .. filepath, vim.log.levels.WARN)
        return
    end

    local content = table.concat(lines, '\n')
    local tokens = utils_treesitter.get_treesitter_highlight_captures(content, lang)

    --- @type table<number, LineHighlight[]>
    local new_highlights = {}
    for _, hunk in ipairs(file_data.hunks) do
        for _, line in ipairs(hunk.lines) do
            if line.line_type == 'context' or line.line_type == 'added' then
                new_highlights[line.formatted_diff_line_num] = tokens[line.new_line_num - 1]
            end
        end
    end
    utils.apply_highlights(bufnr, new_highlights)
end

--- @param bufnr number
--- @param opts DeltaOpts | nil Optional highlighting configuration overrides
M.diff_highlight_diff_directory = function(bufnr, opts)
    local diff_data = M.get_diff_data(bufnr)
    if (diff_data == nil) then return end
    --- @cast diff_data DirectoryDiffData
    local highlight_opts = vim.tbl_deep_extend('force', config.options, opts or {})
    local file_highlights = utils_highlighting.get_highlights_directory(diff_data.files, highlight_opts)
    utils.apply_highlights(bufnr, file_highlights)
end

--- CURRENTLY UNUSED
--- @param file_data FileDiffData
--- @param filename string
--- @param bufnr number
--- @param opts DeltaOpts | nil Optional highlighting configuration overrides
M.diff_highlight_diff_file = function(file_data, filename, bufnr, opts)
    local highlight_opts = vim.tbl_deep_extend('force', config.options, opts or {})
    local file_highlights = utils_highlighting.get_highlights_file(file_data, filename, highlight_opts)
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
--- @return DirectoryDiffData | nil
M.get_diff_data = function(bufnr)
    local delta_files_data = vim.b[bufnr].delta_files_data

    if delta_files_data == nil then
        vim.notify("Buffer did not contain delta diff data", vim.log.levels.WARN)
        return
    end
    --- @type DirectoryDiffData
    return { files = delta_files_data }
end

--- @param bufnr number
--- @return DeltaArtifact[] | nil
M.get_delta_artifact_data = function(bufnr)
    local delta_artifacts = vim.b[bufnr].delta_artifacts

    if delta_artifacts == nil then
        vim.notify("Buffer did not contain delta artifact data", vim.log.levels.WARN)
        return
    end
    --- @type DirectoryDiffData
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

--- @class FileDiffData
--- @field hunks Hunk[] Array of hunks for this file
--- @field old_path string|nil Path to old file (from --- a/...)
--- @field new_path string|nil Path to new file (from +++ b/...)

-- originally the types were meant to allow different artifacts to have different highlights.
-- if I want this to be useful, I would need to update my code to identify artifacts by both row and column.
-- Would be a big implementation, for little gain.
-- for little gain.
--- @class DeltaArtifact
--- @field row_number number (0-indexed)
--- @field content string
--- @field type "title"|"fence"|

--- @class DirectoryDiffData
--- @field files table<string, FileDiffData> Map of filename to file diff data
