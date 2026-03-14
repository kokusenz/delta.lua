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

local git_diff_fixture = table.concat({
    "diff --git a/foo.lua b/foo.lua",
    "index abc1234..def5678 100644",
    "--- a/foo.lua",
    "+++ b/foo.lua",
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

local patch_fixture = table.concat({
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Stub module-level dependencies before require so M sees the stubs
                package.loaded['delta.config'] = {
                    options = {
                        context = 3,
                        highlighting = { max_similarity_threshold = 0.6 },
                        new_file = false,
                    },
                }
                package.loaded['delta.utils'] = {
                    build_git_diff_cmd_with_flags = function(_effective, _ref, _path)
                        return { 'git', 'diff', 'HEAD' }
                    end,
                    get_window_width = function(_winid) return 80 end,
                    apply_highlights  = function(_bufnr, _highlights) end,
                    get_language_from_filename = function(filename)
                        local ext = filename:match('%.([^%.]+)$')
                        local map = { lua = 'lua', py = 'python' }
                        return map[ext]
                    end,
                }
                package.loaded['delta.utils_treesitter'] = {
                    get_treesitter_highlight_captures = function(_content, _lang) return {} end,
                    get_treesitter_token_strings      = function(_str, _lang) return {} end,
                    get_lua_pattern_token_strings     = function(_str) return {} end,
                }
                package.loaded['delta.utils_highlighting'] = {
                    get_highlights_multiple_files = function(_files, _opts) return {} end,
                }

                vim.fn.systemlist = function(_cmd) return {} end
                -- Note: vim.v.shell_error is read-only; stubbing systemlist above
                -- prevents the real shell command from running, keeping shell_error = 0
            ]])
            child.lua([[M = require('delta.diff')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- git_diff() - example based tests

T['git_diff()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.system = function(_cmd, _opts)
                    return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
                end
                -- Stub systemlist to return a fake git root; this also prevents the real
                -- shell command from running, keeping vim.v.shell_error at 0 (its default)
                vim.fn.systemlist = function(_cmd) return { '/fake/git/root' } end
            ]])
        end,
    },
})

T['git_diff()']['returns nil when git produces no output'] = function()
    local is_nil = child.lua_get([[M.git_diff('HEAD', nil, {}) == nil]])
    eq(is_nil, true)
end

T['git_diff()']['returns valid bufnr when diff has changes'] = function()
    child.lua([[
        _G.fixture.diff_output = ...
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 0, stdout = _G.fixture.diff_output, stderr = '' } end }
        end
    ]], { git_diff_fixture })
    local valid = child.lua_get([[(function()
        local bufnr = M.git_diff('HEAD', nil, {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['git_diff()']['delta_diff_data_set contains the parsed file path'] = function()
    child.lua([[
        _G.fixture.diff_output = ...
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 0, stdout = _G.fixture.diff_output, stderr = '' } end }
        end
    ]], { git_diff_fixture })
    local path = child.lua_get([[(function()
        local bufnr = M.git_diff('HEAD', nil, {})
        return vim.b[bufnr].delta_diff_data_set[1].new_path
    end)()]])
    eq(path, 'foo.lua')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- text_diff() - example based tests

T['text_diff()'] = new_set()

T['text_diff()']['returns valid bufnr for two differing strings'] = function()
    local valid = child.lua_get([[(function()
        local bufnr = M.text_diff('local x = 1\nlocal y = 2', 'local x = 1\nlocal y = 10', 'lua', {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['text_diff()']['buffer is not modifiable'] = function()
    local modifiable = child.lua_get([[(function()
        local bufnr = M.text_diff('local x = 1\nlocal y = 2', 'local x = 1\nlocal y = 10', 'lua', {})
        return vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
    end)()]])
    eq(modifiable, false)
end

T['text_diff()']['falls back to vim.diff when vim.text is unavailable'] = function()
    local used_vim_diff = child.lua_get([[(function()
        local called = false
        vim.text = nil
        vim.diff = function(s1, s2, opts)
            called = true
            return '@@ -1,2 +1,2 @@\n local x = 1\n-local y = 2\n+local y = 10\n'
        end
        M.text_diff('local x = 1\nlocal y = 2', 'local x = 1\nlocal y = 10', 'lua', {})
        return called
    end)()]])
    eq(used_vim_diff, true)
end

T['text_diff()']['delta_diff_data_set contains a hunk for the changed line'] = function()
    local hunk_count = child.lua_get([[(function()
        local bufnr = M.text_diff('local x = 1\nlocal y = 2', 'local x = 1\nlocal y = 10', 'lua', {})
        return #vim.b[bufnr].delta_diff_data_set[1].hunks
    end)()]])
    eq(hunk_count, 1)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- patch_diff() - example based tests

T['patch_diff()'] = new_set()

T['patch_diff()']['returns nil when diffstring is empty'] = function()
    local is_nil = child.lua_get([[M.patch_diff('', false, 'lua', {}) == nil]])
    eq(is_nil, true)
end

T['patch_diff()']['plain unified diff: returns valid bufnr'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { patch_fixture })
    local valid = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture.diff_input, false, 'lua', {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['patch_diff()']['plain unified diff: buffer has delta_diff_data_set'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { patch_fixture })
    local has_data = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture.diff_input, false, 'lua', {})
        return vim.b[bufnr].delta_diff_data_set ~= nil
    end)()]])
    eq(has_data, true)
end

T['patch_diff()']['git diff format: returns valid bufnr'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { git_diff_fixture })
    local valid = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture.diff_input, true, nil, {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['patch_diff()']['git diff format: delta_diff_data_set has correct file path'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { git_diff_fixture })
    local path = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture.diff_input, true, nil, {})
        return vim.b[bufnr].delta_diff_data_set[1].new_path
    end)()]])
    eq(path, 'foo.lua')
end

return T
