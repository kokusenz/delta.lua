local M = {}

--- @param files table<string, FileDiffData>
--- @return table<number, LineHighlight[]> diffs first key is filename, second key line number of the diff
M.get_highlights_directory = function(files)
    local highlights = {}
    for _, file in pairs(files) do
        local file_highlights = M.get_highlights_file(file)
        for line_number, highlight in pairs(file_highlights) do
            highlights[line_number] = highlight
        end
    end
    return highlights
end

--- @param file FileDiffData
--- @return table<number, LineHighlight[]> highlights a list of
M.get_highlights_file = function(file)
    local highlights = {}
    for _, hunk in ipairs(file.hunks) do
        -- normal line highlighting
        local line_highlights = M.get_line_highlights(hunk)
        for line_number, line_highlight in pairs(line_highlights) do
            local cur_highlights = highlights[line_number] or {}
            for _, highlight in ipairs(line_highlight) do
                table.insert(cur_highlights, highlight)
            end
            highlights[line_number] = cur_highlights
        end
        -- two tier highlighting
        -- within one hunk, check to see what lines are adjacent to each other that are not context
        local adjacent_lines_sets = M.get_adjacent_line_sets(hunk)
        -- maybe map where key is line nuber, value is diff
        local word_highlights = M.get_highlights(adjacent_lines_sets)
        for line_number, word_highlight in pairs(word_highlights) do
            local cur_highlights = highlights[line_number] or {}
            for _, highlight in ipairs(word_highlight) do
                table.insert(cur_highlights, highlight)
            end
            highlights[line_number] = cur_highlights
        end
    end
    return highlights
end

--- @param hunk Hunk
--- @return table<number, LineHighlight[]>
M.get_line_highlights = function(hunk)
    local line_highlights = {}
    for _, line in ipairs(hunk.lines) do
        if line.line_type == 'added' then
            local line_length = #line.content
            local add_highlight = {
                col = 0,
                end_col = line_length,
                priority = 200,
                hl_group = 'DiffAdd'
            }

            line_highlights[line.formatted_diff_line_num] = { add_highlight }
        elseif line.line_type == 'removed' then
            local line_length = #line.content
            local remove_highlight = {
                col = 0,
                end_col = line_length,
                priority = 200,
                hl_group = 'DiffDelete'
            }
            line_highlights[line.formatted_diff_line_num] = { remove_highlight }
        end
    end
    return line_highlights
end

--- @param adjacent_lines_sets table<number, DiffLine>[]
--- @return table<number, LineHighlight[]> highlights key: 1-indexed line number of the diff
M.get_highlights = function(adjacent_lines_sets)
    local highlights = {}
    for _, adjacent_lines in ipairs(adjacent_lines_sets) do
        -- sort keys so we can iterate the adjacents ino rder
        local keys = {}
        for k, _ in pairs(adjacent_lines) do
            table.insert(keys, k)
        end
        table.sort(keys)

        -- found pairs shouldn't be calculated again
        local tested_pairs = {}
        for _, i in ipairs(keys) do
            tested_pairs[i] = i
        end

        --- @type table<number, number[]>
        local combinations = {}

        -- within one block of diffed code (added or deleted), all lines will be compared against each other.
        -- if there are two added lines, and two deleted lines, each added line will be compared against both deleted lines
        -- this means that we can have multiple diffs for each line. Theoretically, we should only be looking at one though.
        for _, i in ipairs(keys) do
            --- @type DiffLine
            local diffline1 = adjacent_lines[i]
            for _, j in ipairs(keys) do
                --- @type DiffLine
                if tested_pairs[i] == j then
                    goto continue
                end

                local diffline2 = adjacent_lines[j]
                if (diffline1.new_line_num ~= nil and diffline2.old_line_num ~= nil) then
                    tested_pairs[i] = j
                    tested_pairs[j] = i
                    combinations[i] = combinations[i] or {}
                    table.insert(combinations[i], j)
                end

                if (diffline1.old_line_num ~= nil and diffline2.new_line_num ~= nil) then
                    tested_pairs[i] = j
                    tested_pairs[j] = i
                    combinations[j] = combinations[j] or {}
                    table.insert(combinations[j], i)
                end

                ::continue::
            end
        end

        -- given combinations, a list of potential "matches" for each added line, find the one with the most similarity
        for diff_line_num, potential_pairs in pairs(combinations) do
            if #potential_pairs == 0 then
                goto continue
            end

            local max_similarity = { 0, nil }
            for _, potential_pair_line_num in ipairs(potential_pairs) do
                local similarity = M.calculate_similarity(adjacent_lines[diff_line_num].content,
                    adjacent_lines[potential_pair_line_num].content)
                if similarity >= max_similarity[1] then
                    max_similarity[1] = similarity
                    max_similarity[2] = potential_pair_line_num
                end
            end

            -- if loop runs at least once, max_similarity[2] guaranteed to be non null
            local diff_highlights = M.get_word_diff_highlights(adjacent_lines[diff_line_num].content,
                adjacent_lines[max_similarity[2]].content)
            highlights[diff_line_num] = diff_highlights.added
            highlights[max_similarity[2]] = diff_highlights.removed

            ::continue::
        end
    end
    return highlights
end

--- in a hunk, get all the sets of adjacent lines. returns a list of maps where the key is the 1-indexed line number in the diff
--- @param hunk Hunk
--- @return table<number, DiffLine>[] adjacent_line_sets
M.get_adjacent_line_sets = function(hunk)
    --- @type table<number, DiffLine>[]
    local adjacent_lines_sets = {}
    for i = 1, #hunk.lines, 1 do
        local line = hunk.lines[i]
        -- initialize first set as empty
        if line.line_type ~= 'context' then
            -- theoretically, there should never be duplicate diff_line_num's in a input.
            for _, adjacent_lines in ipairs(adjacent_lines_sets) do
                if adjacent_lines[line.formatted_diff_line_num] ~= nil then
                    adjacent_lines[line.formatted_diff_line_num] = line
                    adjacent_lines[line.formatted_diff_line_num - 1] = adjacent_lines[line.formatted_diff_line_num - 1] or
                        ''
                    adjacent_lines[line.formatted_diff_line_num + 1] = adjacent_lines[line.formatted_diff_line_num + 1] or
                        ''
                    goto adjacent_line_set_found
                end
            end
            -- if you couldn't find a set in adjacent_lines_sets for the line, then make a new set and add it
            --- @type table<number, DiffLine>
            local adjacent_lines = {}
            adjacent_lines[line.formatted_diff_line_num] = line
            adjacent_lines[line.formatted_diff_line_num - 1] = adjacent_lines[line.formatted_diff_line_num - 1] or ''
            adjacent_lines[line.formatted_diff_line_num + 1] = adjacent_lines[line.formatted_diff_line_num + 1] or ''

            table.insert(adjacent_lines_sets, adjacent_lines)

            ::adjacent_line_set_found::
        end
    end
    -- reiterate adjacent_lines_sets to remove empty strings
    for _, adjacent_lines in ipairs(adjacent_lines_sets) do
        for idx, value in pairs(adjacent_lines) do
            if value == '' then
                adjacent_lines[idx] = nil
            end
        end
    end
    return adjacent_lines_sets
end

--- Levenshtein distance
--- @param str1 string
--- @param str2 string
--- @return number similarity (0.0 = completely different, 1.0 = identical)
M.calculate_similarity = function(str1, str2)
    if str1 == str2 then return 1.0 end
    if str1 == "" or str2 == "" then return 0.0 end

    local len1, len2 = #str1, #str2
    local matrix = {}

    for i = 0, len1 do matrix[i] = { [0] = i } end
    for j = 0, len2 do matrix[0][j] = j end

    for i = 1, len1 do
        for j = 1, len2 do
            local cost = (str1:sub(i, i) == str2:sub(j, j)) and 0 or 1
            matrix[i][j] = math.min(
                matrix[i - 1][j] + 1,   -- deletion
                matrix[i][j - 1] + 1,   -- insertion
                matrix[i - 1][j - 1] + cost -- substitution
            )
        end
    end

    local distance = matrix[len1][len2]
    local max_len = math.max(len1, len2)

    return 1.0 - (distance / max_len)
end

--- @param str1 string (the added/green line)
--- @param str2 string (the removed/red line)
--- @return TwoTierHighlights highlights for both strings
M.get_word_diff_highlights = function(str1, str2)
    -- insert a \n between every word to force line-based diff to work word-by-word
    -- Word boundaries: spaces, operators, punctuation (but keep dots within words like foo.bar as one word)
    local new_lined_str1 = str1:gsub("([%w_]+)([^%w_]?)", "%1\n%2\n")
    local new_lined_str2 = str2:gsub("([%w_]+)([^%w_]?)", "%1\n%2\n")

    -- build token maps to convert line numbers back to character positions
    --- @return Token[] tokens
    local function build_token_map(original_str, newlined_str)
        --- @class Token
        --- @field start number
        --- @field len number
        local tokens = {}
        local pos = 1
        for token in newlined_str:gmatch("([^\n]+)") do
            local token_start = original_str:find(token, pos, true)
            if token_start then
                table.insert(tokens, { start = token_start - 1, len = #token }) -- 0-indexed
                pos = token_start + #token
            end
        end
        return tokens
    end

    local tokens1 = build_token_map(str1, new_lined_str1)
    local tokens2 = build_token_map(str2, new_lined_str2)

    local diff = vim.text.diff(
        new_lined_str1,
        new_lined_str2,
        { result_type = 'indices', algorithm = 'myers', ctxlen = 0 })

    --- @type TwoTierHighlights
    local highlights = {
        added = {},
        removed = {}
    }

    for _, change in ipairs(diff) do
        local old_start, old_count, new_start, new_count = change[1] - 1, change[2], change[3] - 1, change[4]

        -- highlight changed parts of str1 (added/green line)
        -- convert line numbers to character positions using token map
        if old_count > 0 and tokens1[old_start + 1] then
            local start_token = tokens1[old_start + 1]
            local end_token = tokens1[math.min(old_start + old_count, #tokens1)]

            table.insert(highlights.added, {
                col = start_token.start,
                end_col = end_token and (end_token.start + end_token.len) or (start_token.start + start_token.len),
                priority = 250,
                hl_group = 'RedrawDebugComposed'
            })
        end

        -- Highlight changed parts of str2 (removed/red line)
        if new_count > 0 and tokens2[new_start + 1] then
            local start_token = tokens2[new_start + 1]
            local end_token = tokens2[math.min(new_start + new_count, #tokens2)]

            table.insert(highlights.removed, {
                col = start_token.start,
                end_col = end_token and (end_token.start + end_token.len) or (start_token.start + start_token.len),
                priority = 250,
                hl_group = 'RedrawDebugRecompose'
            })
        end
    end

    -- if all the word level highlights cover the entire line, do not display any
    if #highlights.added > 0 then
        local min_col = math.huge
        local max_end_col = 0
        for _, hl in ipairs(highlights.added) do
            min_col = math.min(min_col, hl.col)
            max_end_col = math.max(max_end_col, hl.end_col)
        end
        if min_col == 0 and max_end_col >= #str1 then
            highlights.added = {}
        end
    end

    if #highlights.removed > 0 then
        local min_col = math.huge
        local max_end_col = 0
        for _, hl in ipairs(highlights.removed) do
            min_col = math.min(min_col, hl.col)
            max_end_col = math.max(max_end_col, hl.end_col)
        end
        if min_col == 0 and max_end_col >= #str2 then
            highlights.removed = {}
        end
    end

    return highlights
end


return M

--- @class TwoTierHighlights
--- @field added LineHighlight[]
--- @field removed LineHighlight[]
