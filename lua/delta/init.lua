local M = {}
local config = require('delta.config')
local utils_highlighting = require('delta.utils_highlighting')
local diff = require('delta.diff')

-- TODO verify what flags delta has that I want to support. For example, similarity threshold

---@param opts DeltaOpts
M.setup = function(opts)
    config.setup(opts)
    utils_highlighting.initialize_hl_groups()

    -- Testing commands - will be removed before 1.0 release
    vim.api.nvim_create_user_command('TestDeltaDiff', function(topts)
        local ref = topts.args ~= '' and topts.args or 'HEAD'
        M._test_git_diff(ref)
    end, { desc = "[TEST ONLY] Run delta git diff on current buffer", nargs = '?' })

    vim.api.nvim_create_user_command('TestDeltaTextDiff', function()
        M._test_text_diff()
    end, { desc = "[TEST ONLY] Run delta text diff with mock data" })

    vim.api.nvim_create_user_command('TestDeltaPatchDiff', function()
        M._test_patch_diff()
    end, { desc = "[TEST ONLY] Run delta patch_diff with a hardcoded unified diff" })
end

M.git_diff = diff.git_diff
M.text_diff = diff.text_diff
M.patch_diff = diff.patch_diff
M.highlight_delta_artifacts = diff.highlight_delta_artifacts
M.syntax_highlight_git_diff = diff.syntax_highlight_git_diff
M.syntax_highlight_diff_set = diff.syntax_highlight_diff_set
M.diff_highlight_diff = diff.diff_highlight_diff
M.setup_delta_statuscolumn = diff.setup_delta_statuscolumn

--- @param ref string
M._test_git_diff = function(ref)
    ref = ref or 'HEAD'
    local cur_path
    local ok, expanded = pcall(vim.fn.expand, '%:p')
    if ok and expanded ~= '' then
        cur_path = expanded
    else
        cur_path = nil
    end

    local bufnr = M.git_diff(ref, cur_path, {})
    if bufnr == nil then
        return -- Error already notified
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_git_diff(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

--- Test function for text diff workflow
--- Typical sequence: text_diff -> display -> highlight_artifacts -> diff_highlight -> statuscolumn
M._test_text_diff = function()
    local original = "local x = 1\nlocal y = 2\nlocal z = 3"
    local modified = "local x = 1\nlocal y = 10\nlocal z = 3"

    local bufnr = M.text_diff(original, modified, 'lua', {})
    if bufnr == nil then
        return
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_diff_set(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

--- Test function for patch_diff workflow
--- Typical sequence: patch_diff -> display -> highlight_artifacts -> diff_highlight -> statuscolumn
M._test_patch_diff = function()
    local diffstring = table.concat({
        "@@ -1,4 +1,4 @@",
        " local x = 1",
        "-local y = 2",
        "+local y = 10",
        " local z = 3",
        " local w = 4",
    }, "\n")

    local bufnr = M.patch_diff(diffstring, false, 'lua', {})
    if bufnr == nil then
        return
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_diff_set(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

-- Typical usage sequences for library consumers:
--
-- Git diff workflow:
--   1. bufnr = delta.git_diff(ref, path)
--   2. <display buffer in window>
--   3. delta.highlight_delta_artifacts(bufnr)
--   4. delta.syntax_highlight_git_diff(bufnr)
--   5. delta.diff_highlight_diff(bufnr, opts)
--   6. delta.setup_delta_statuscolumn(bufnr, winid)
--
-- Text diff workflow:
--   1. bufnr = delta.text_diff(s1, s2, opts)
--   2. <display buffer in window>
--   3. delta.highlight_delta_artifacts(bufnr)
--   4. delta.syntax_highlight_diff_set(bufnr)
--   5. delta.diff_highlight_diff(bufnr, opts)
--   6. delta.setup_delta_statuscolumn(bufnr, winid)
--
-- Patch/diffstring workflow:
--   1. bufnr = delta.patch_diff(diffstring)
--   2. <display buffer in window>
--   3. delta.highlight_delta_artifacts(bufnr)
--   4. delta.syntax_highlight_diff_set(bufnr)  -- or syntax_highlight_git_diff if in git repo with new_path available
--   5. delta.diff_highlight_diff(bufnr, opts)
--   6. delta.setup_delta_statuscolumn(bufnr, winid)

return M
