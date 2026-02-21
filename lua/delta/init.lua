local M = {}
local config = require('delta.config')
local utils_highlighting = require('delta.utils_highlighting')
local diff = require('delta.diff')

---@param opts DeltaOpts
M.setup = function(opts)
    config.setup(opts)
    utils_highlighting.initialize_hl_groups()
end

-- API
M.git_diff = diff.git_diff
M.text_diff = diff.text_diff
M.patch_diff = diff.patch_diff
M.highlight_delta_artifacts = diff.highlight_delta_artifacts
M.syntax_highlight_git_diff = diff.syntax_highlight_git_diff
M.syntax_highlight_diff_set = diff.syntax_highlight_diff_set
M.diff_highlight_diff = diff.diff_highlight_diff
M.setup_delta_statuscolumn = diff.setup_delta_statuscolumn

M.parse = {}
M.parse.get_diff_data_git = diff.get_diff_data_git
M.parse.get_diff_data = diff.get_diff_data

-- Example Usages of Api

--- Test function for git diff workflow. This is a typical sequence.
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

    local bufnr = M.git_diff(ref, nil, {})
    if bufnr == nil then
        return -- Error already notified
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_git_diff(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

--- Test function for text diff workflow. This is a typical sequence.
M._test_text_diff = function()
    local original =
    "local x = 1\nlocal y = 2\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'original'"
    local modified =
    "local x = 1\nlocal y = 10\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'new'"

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

--- Test function for patch_diff workflow. This is a typical sequence.
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

-- TODO update documentation explaining how to configure lua_ls to read this global variable, and to use Delta when using this api.
_G.Delta = M
return M
