local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

-- usage: add the following to a pre_case hook
-- child.lua(test_logging)
local test_logging = [[
    _G.test_logs = {}
    _G.captured_prints = {}
    local original_print = print
    print = function(...)
      local args = {...}
      local msg = table.concat(vim.tbl_map(tostring, args), ' ')
      table.insert(_G.captured_prints, msg)
      original_print(...)  -- Still call original for child's output
    end
]]

-- usage: add the following to the new_set
-- post_case = print_test_logging
local print_test_logging = function()
    local captured_prints = child.lua_get('_G.captured_prints')
    if captured_prints == vim.NIL or captured_prints == nil then return end
    if #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- fixtures

-- A temp git repo with one .lua file committed and a working-tree change ready to diff.
-- Sets cwd to tmpdir and opens the file so the plugin can find git root.
local setup_tmpdir_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    -- Make a working-tree change
    local f2 = io.open(tmpdir .. '/test.lua', 'w')
    f2:write('local x = 1\nlocal y = 99\n')
    f2:close()
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
    _G.fixture = { tmpdir = tmpdir }
]]

-- A clean temp git repo (no working-tree changes) — used to trigger the "no changes" branch.
local setup_tmpdir_clean_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    -- No working-tree change: repo is clean
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
    _G.fixture = { tmpdir = tmpdir }
]]

local text_diff_original = "local x = 1\nlocal y = 2\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'original'"
local text_diff_modified = "local x = 1\nlocal y = 10\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'new'"

local patch_fixture = table.concat({
    "@@ -1,4 +1,4 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
    " local w = 4",
}, "\n")

local git_diff_fixture = table.concat({
    "diff --git a/foo.lua b/foo.lua",
    "index abc1234..def5678 100644",
    "--- a/foo.lua",
    "+++ b/foo.lua",
    "@@ -1,4 +1,4 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
    " local w = 4",
}, "\n")

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- top-level set

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                M = require('delta')
                M.setup({})
                _G.fixture = {}
            ]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- git_diff integration

T['git_diff integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)
        end,
    },
})

T['git_diff integration']['happy path: returns a valid buffer with delta data'] = function()
    local bufnr = child.lua_get('M.git_diff("HEAD", nil, {})')
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local has_line_map = child.lua_get(string.format('vim.b[%d].delta_line_map ~= nil', bufnr))
    eq(has_line_map, true)
    local has_diff_data = child.lua_get(string.format('vim.b[%d].delta_diff_data_set ~= nil', bufnr))
    eq(has_diff_data, true)
end

T['git_diff integration']['happy path: full sequence sets statuscolumn on window'] = function()
    child.lua([[
        local bufnr = M.git_diff('HEAD', nil, {})
        vim.api.nvim_win_set_buf(0, bufnr)
        M.highlight_delta_artifacts(bufnr)
        M.syntax_highlight_git_diff(bufnr)
        M.diff_highlight_diff(bufnr)
        M.setup_delta_statuscolumn(bufnr)
        _G.fixture.bufnr = bufnr
    ]])
    local bufnr = child.lua_get('_G.fixture.bufnr')
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local statuscolumn = child.lua_get('vim.api.nvim_get_option_value("statuscolumn", { win = 0 })')
    eq(statuscolumn:find('delta.statuscolumn', 1, true) ~= nil, true)
end

T['git_diff integration']['failure path: not in a git repo returns nil and notifies'] = function()
    -- cd to /tmp which is never inside a git repo
    child.lua([[
        _G.fixture.notify_called = false
        _G.fixture.notify_msg = nil
        vim.notify = function(msg, _level)
            _G.fixture.notify_called = true
            _G.fixture.notify_msg = msg
        end
        vim.cmd('cd /tmp')
    ]])
    local result = child.lua_get('M.git_diff("HEAD", nil, {})')
    eq(result, vim.NIL)
    local notify_called = child.lua_get('_G.fixture.notify_called')
    eq(notify_called, true)
end

T['git_diff integration']['failure path: no working-tree changes returns nil and notifies'] = function()
    -- restart with a clean repo (no modifications)
    child.lua(setup_tmpdir_clean_git_repo)
    child.lua([[
        _G.fixture.notify_called = false
        _G.fixture.notify_msg = nil
        vim.notify = function(msg, _level)
            _G.fixture.notify_called = true
            _G.fixture.notify_msg = msg
        end
    ]])
    local result = child.lua_get('M.git_diff("HEAD", nil, {})')
    eq(result, vim.NIL)
    local notify_called = child.lua_get('_G.fixture.notify_called')
    eq(notify_called, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- text_diff integration

T['text_diff integration'] = new_set()

T['text_diff integration']['happy path: returns a valid buffer with delta data'] = function()
    child.lua(string.format([[
        _G.fixture.s1 = %q
        _G.fixture.s2 = %q
    ]], text_diff_original, text_diff_modified))
    local bufnr = child.lua_get("M.text_diff(_G.fixture.s1, _G.fixture.s2, 'lua', {})")
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local has_line_map = child.lua_get(string.format('vim.b[%d].delta_line_map ~= nil', bufnr))
    eq(has_line_map, true)
    local has_diff_data = child.lua_get(string.format('vim.b[%d].delta_diff_data_set ~= nil', bufnr))
    eq(has_diff_data, true)
    -- text_diff wraps the result in a single-element set
    local diff_data_set_len = child.lua_get(string.format('#vim.b[%d].delta_diff_data_set', bufnr))
    eq(diff_data_set_len, 1)
end

T['text_diff integration']['happy path: full sequence sets statuscolumn on window'] = function()
    child.lua(string.format([[
        _G.fixture.s1 = %q
        _G.fixture.s2 = %q
        local bufnr = M.text_diff(_G.fixture.s1, _G.fixture.s2, 'lua', {})
        vim.api.nvim_win_set_buf(0, bufnr)
        M.highlight_delta_artifacts(bufnr)
        M.syntax_highlight_diff_set(bufnr)
        M.diff_highlight_diff(bufnr)
        M.setup_delta_statuscolumn(bufnr)
        _G.fixture.bufnr = bufnr
    ]], text_diff_original, text_diff_modified))
    local bufnr = child.lua_get('_G.fixture.bufnr')
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local statuscolumn = child.lua_get('vim.api.nvim_get_option_value("statuscolumn", { win = 0 })')
    eq(statuscolumn:find('delta.statuscolumn', 1, true) ~= nil, true)
end

T['text_diff integration']['buffer has content'] = function()
    child.lua(string.format([[
        _G.fixture.s1 = %q
        _G.fixture.s2 = %q
    ]], text_diff_original, text_diff_modified))
    local bufnr = child.lua_get("M.text_diff(_G.fixture.s1, _G.fixture.s2, 'lua', {})")
    local line_count = child.lua_get(string.format('vim.api.nvim_buf_line_count(%d)', bufnr))
    eq(line_count > 0, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- patch_diff integration

T['patch_diff integration'] = new_set()

T['patch_diff integration']['happy path (plain unified diff): returns a valid buffer with delta data'] = function()
    child.lua(string.format([[_G.fixture.patch = %q]], patch_fixture))
    local bufnr = child.lua_get("M.patch_diff(_G.fixture.patch, false, 'lua', {})")
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local has_line_map = child.lua_get(string.format('vim.b[%d].delta_line_map ~= nil', bufnr))
    eq(has_line_map, true)
    local has_diff_data = child.lua_get(string.format('vim.b[%d].delta_diff_data_set ~= nil', bufnr))
    eq(has_diff_data, true)
end

T['patch_diff integration']['happy path (git diff format): returns a valid buffer with paths set'] = function()
    child.lua(string.format([[_G.fixture.patch = %q]], git_diff_fixture))
    local bufnr = child.lua_get("M.patch_diff(_G.fixture.patch, true, nil, {})")
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local old_path = child.lua_get(string.format('vim.b[%d].delta_diff_data_set[1].old_path', bufnr))
    local new_path = child.lua_get(string.format('vim.b[%d].delta_diff_data_set[1].new_path', bufnr))
    eq(old_path, 'foo.lua')
    eq(new_path, 'foo.lua')
end

T['patch_diff integration']['happy path: full sequence sets statuscolumn on window'] = function()
    child.lua(string.format([[
        _G.fixture.patch = %q
        local bufnr = M.patch_diff(_G.fixture.patch, false, 'lua', {})
        vim.api.nvim_win_set_buf(0, bufnr)
        M.highlight_delta_artifacts(bufnr)
        M.syntax_highlight_diff_set(bufnr)
        M.diff_highlight_diff(bufnr)
        M.setup_delta_statuscolumn(bufnr)
        _G.fixture.bufnr = bufnr
    ]], patch_fixture))
    local bufnr = child.lua_get('_G.fixture.bufnr')
    eq(type(bufnr), 'number')
    local is_valid = child.lua_get(string.format('vim.api.nvim_buf_is_valid(%d)', bufnr))
    eq(is_valid, true)
    local statuscolumn = child.lua_get('vim.api.nvim_get_option_value("statuscolumn", { win = 0 })')
    eq(statuscolumn:find('delta.statuscolumn', 1, true) ~= nil, true)
end

T['patch_diff integration']['failure path: empty diffstring returns nil and notifies'] = function()
    child.lua([[
        _G.fixture.notify_called = false
        vim.notify = function(_msg, _level)
            _G.fixture.notify_called = true
        end
    ]])
    local result = child.lua_get("M.patch_diff('', false, 'lua', {})")
    eq(result, vim.NIL)
    local notify_called = child.lua_get('_G.fixture.notify_called')
    eq(notify_called, true)
end

return T
