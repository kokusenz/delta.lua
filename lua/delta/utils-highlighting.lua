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
        -- within one hunk, check to see what lines are adjacent to each other that are not context
        local adjacent_lines_sets = M.get_adjacent_line_sets(hunk)
        -- maybe map where key is line nuber, value is diff
        local new_highlights = M.get_highlights(adjacent_lines_sets)
        for line_number, new_highlight in pairs(new_highlights) do
            highlights[line_number] = new_highlight
        end
    end
    return highlights
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
            local diff_highlights = M.get_diff_highlight(adjacent_lines[diff_line_num].content,
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
                    adjacent_lines[line.formatted_diff_line_num - 1] = adjacent_lines[line.formatted_diff_line_num - 1] or ''
                    adjacent_lines[line.formatted_diff_line_num + 1] = adjacent_lines[line.formatted_diff_line_num + 1] or ''
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

--- @param str1 string
--- @param str2 string
--- @return number similarity (0.0 = completely different, 1.0 = identical)
M.calculate_similarity = function(str1, str2)
    if str1 == str2 then return 1.0 end
    if str1 == "" or str2 == "" then return 0.0 end

    -- Simple approach: ratio of common characters
    local len1, len2 = #str1, #str2
    local max_len = math.max(len1, len2)

    -- Use vim.diff to count differences
    local diff = vim.text.diff(str1, str2, {
        result_type = 'indices',
        algorithm = 'myers',
        ctxlen = 0
    })

    -- Calculate changed characters
    local changed = 0
    for _, change in ipairs(diff or {}) do
        changed = changed + math.max(change[2] or 0, change[4] or 0)
    end

    return 1.0 - (changed / max_len)
end

--- @param str1 string (the added/green line)
--- @param str2 string (the removed/red line)
--- @return TwoTierHighlights highlights for both strings
M.get_diff_highlight = function(str1, str2)
    -- Use 'indices' to get character-level changes
    -- insert a \n between every character to force line-based diff to work character-by-character
    local new_lined_str1 = str1:gsub("(.)", "%1\n")
    local new_lined_str2 = str2:gsub("(.)", "%1\n")

    local diff = vim.text.diff(
        new_lined_str1,
        new_lined_str2,
        { result_type = 'indices', algorithm = 'myers', ctxlen = 0 })

    local not_indice_diff = vim.text.diff(
        new_lined_str1,
        new_lined_str2,
        { algorithm = 'myers', ctxlen = 0 })

    print("str1:", str1)
    print("str2:", str2)
    print("newlined str1:", new_lined_str1)
    vim.print(not_indice_diff)

    local add_highlight_line = {
        col = 0,
        end_col = #str1,
        priority = 200,
        hl_group = 'DiffAdd'
    }

    local remove_highlight_line = {
        col = 0,
        end_col = #str2,
        priority = 200,
        hl_group = 'DiffDelete'
    }

    --- @type TwoTierHighlights
    local highlights = {
        added = { },
        removed = { }
    }

    for _, change in ipairs(diff) do
        local old_start, old_count, new_start, new_count = change[1], change[2], change[3], change[4]

        -- Highlight changed parts of str1 (added/green line)
        -- Divide by 2 since each character is now 2 chars (char + \n)
        if old_count > 0 then
            table.insert(highlights.added, {
                col = math.floor((old_start - 1) / 2), -- Convert from line-based to char-based
                end_col = math.floor((old_start - 1 + old_count) / 2),
                priority = 250,                        -- Higher priority for two-tier highlighting
                hl_group = 'DiffAdd'                   -- Brighter green for added parts
            })
        end

        -- Highlight changed parts of str2 (removed/red line)
        if new_count > 0 then
            table.insert(highlights.removed, {
                col = math.floor((new_start - 1) / 2), -- Convert from line-based to char-based
                end_col = math.floor((new_start - 1 + new_count) / 2),
                priority = 250,                        -- Higher priority for two-tier highlighting
                hl_group = 'DiffDelete'                -- Brighter red for removed parts
            })
        end
    end


    return highlights
end


return M

--- @class TwoTierHighlights
--- @field added LineHighlight[]
--- @field removed LineHighlight[]
