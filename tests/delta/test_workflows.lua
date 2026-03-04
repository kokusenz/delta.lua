local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ─── Fixtures ────────────────────────────────────────────────────────────────

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

-- ─── Test suite ──────────────────────────────────────────────────────────────

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('delta.diff')]])
        end,
        post_once = child.stop,
    },
})

-- ─── git_diff() ──────────────────────────────────────────────────────────────

T['git_diff()'] = new_set()

T['git_diff()']['returns nil when git produces no output'] = function()
    child.lua([[
        io.popen = function(cmd)
            return { read = function() return '' end, close = function() end }
        end
    ]])
    local is_nil = child.lua_get([[M.git_diff('HEAD', nil, {}) == nil]])
    eq(is_nil, true)
end

T['git_diff()']['returns valid bufnr when diff has changes'] = function()
    child.lua([[
        _G.fixture = ...
        io.popen = function(cmd)
            return { read = function() return _G.fixture end, close = function() end }
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
        _G.fixture = ...
        io.popen = function(cmd)
            return { read = function() return _G.fixture end, close = function() end }
        end
    ]], { git_diff_fixture })
    local path = child.lua_get([[(function()
        local bufnr = M.git_diff('HEAD', nil, {})
        return vim.b[bufnr].delta_diff_data_set[1].new_path
    end)()]])
    eq(path, 'foo.lua')
end

-- ─── text_diff() ─────────────────────────────────────────────────────────────

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

-- ─── patch_diff() ────────────────────────────────────────────────────────────

T['patch_diff()'] = new_set()

T['patch_diff()']['returns nil when diffstring is empty'] = function()
    local is_nil = child.lua_get([[M.patch_diff('', false, 'lua', {}) == nil]])
    eq(is_nil, true)
end

T['patch_diff()']['plain unified diff: returns valid bufnr'] = function()
    child.lua([[_G.fixture = ...]], { patch_fixture })
    local valid = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture, false, 'lua', {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['patch_diff()']['plain unified diff: buffer has delta_diff_data_set'] = function()
    child.lua([[_G.fixture = ...]], { patch_fixture })
    local has_data = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture, false, 'lua', {})
        return vim.b[bufnr].delta_diff_data_set ~= nil
    end)()]])
    eq(has_data, true)
end

T['patch_diff()']['git diff format: returns valid bufnr'] = function()
    child.lua([[_G.fixture = ...]], { git_diff_fixture })
    local valid = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture, true, nil, {})
        return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['patch_diff()']['git diff format: delta_diff_data_set has correct file path'] = function()
    child.lua([[_G.fixture = ...]], { git_diff_fixture })
    local path = child.lua_get([[(function()
        local bufnr = M.patch_diff(_G.fixture, true, nil, {})
        return vim.b[bufnr].delta_diff_data_set[1].new_path
    end)()]])
    eq(path, 'foo.lua')
end

return T
