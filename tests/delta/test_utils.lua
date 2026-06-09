local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

-- usage: add the following to a pre case
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
    if captured_prints and #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('delta.utils')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_git_root() - example based tests

T['get_git_root()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.fn.isdirectory = function(_) return 0 end
                vim.fn.fnamemodify = function(path, _) return path end
                vim.system = function(_cmd, _opts)
                    return { wait = function()
                        return { code = 0, stdout = '/fake/git/root\n', stderr = '' }
                    end }
                end
            ]])
        end,
    },
})

T['get_git_root()']['returns trimmed stdout when git succeeds (code 0)'] = function()
    local result = child.lua_get([[(function()
        local ok, val = pcall(M.get_git_root, '/some/file.lua')
        if not ok then return nil end
        return val
    end)()]])

    eq(result, '/fake/git/root')
end

T['get_git_root()']['uses fnamemodify to get parent dir when path is not a directory'] = function()
    child.lua([[
        _G.fixture.fnamemodify_args = nil
        vim.fn.isdirectory = function(_) return 0 end
        vim.fn.fnamemodify = function(path, mod)
            _G.fixture.fnamemodify_args = { path = path, mod = mod }
            return '/parent/dir'
        end
    ]])

    child.lua([[ pcall(M.get_git_root, '/some/file.lua') ]])

    local args = child.lua_get([[_G.fixture.fnamemodify_args]])
    eq(args.path, '/some/file.lua')
    eq(args.mod, ':h')
end

T['get_git_root()']['uses path directly when it is a directory'] = function()
    child.lua([[
        _G.fixture.system_dir = nil
        vim.fn.isdirectory = function(_) return 1 end
        vim.system = function(cmd, _opts)
            _G.fixture.system_dir = cmd[3]  -- git -C <dir> rev-parse ...
            return { wait = function()
                return { code = 0, stdout = '/fake/git/root\n', stderr = '' }
            end }
        end
    ]])

    child.lua([[ pcall(M.get_git_root, '/some/dir') ]])

    local dir = child.lua_get([[_G.fixture.system_dir]])
    eq(dir, '/some/dir')
end

T['get_git_root()']['asserts and throws when git returns a non-zero exit code'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function()
                return { code = 128, stdout = '', stderr = 'not a git repo' }
            end }
        end
    ]])

    local ok = child.lua_get([[(function()
        local ok, _ = pcall(M.get_git_root, '/some/file.lua')
        return ok
    end)()]])

    eq(ok, false)
end

T['get_git_root()']['asserts and throws when git returns code 1'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function()
                return { code = 1, stdout = '', stderr = '' }
            end }
        end
    ]])

    local ok = child.lua_get([[(function()
        local ok, _ = pcall(M.get_git_root, '/some/file.lua')
        return ok
    end)()]])

    eq(ok, false)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- build_git_diff_cmd_with_flags() - example based tests

T['build_git_diff_cmd_with_flags()'] = new_set()

T['build_git_diff_cmd_with_flags()']['returns base command with --full-index always present'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo')
    end)()]])

    eq(result[1], 'git')
    eq(result[2], '-C')
    eq(result[3], '/repo')
    eq(result[4], 'diff')
    eq(result[5], '--no-ext-diff')
    eq(result[6], '--full-index')
end

T['build_git_diff_cmd_with_flags()']['inserts -U<n> context flag when context is set'] = function()
    eq(child.lua_get([[
        (function()
            local cmd = M.build_git_diff_cmd_with_flags({ context = 5 }, 'HEAD', '/repo')
            for _, v in ipairs(cmd) do
                if v == '-U5' then return true end
            end
            return false
        end)()
    ]]), true)
end

T['build_git_diff_cmd_with_flags()']['omits context flag when context is nil'] = function()
    local result = child.lua_get([[
        (function()
            local cmd = M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo')
            for _, v in ipairs(cmd) do
                if v:sub(1, 2) == '-U' then return false end
            end
            return true
        end)()
    ]])

    eq(result, true)
end

T['build_git_diff_cmd_with_flags()']['includes ref when new_file is not true and ref is provided'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD~1', '/repo')
    end)()]])

    local found = false
    for _, v in ipairs(result) do
        if v == 'HEAD~1' then found = true end
    end
    eq(found, true)
end

T['build_git_diff_cmd_with_flags()']['excludes ref and adds --no-index when new_file is true'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({ new_file = true }, 'HEAD', '/repo')
    end)()]])

    local has_ref = false
    local has_no_index = false
    for _, v in ipairs(result) do
        if v == 'HEAD' then has_ref = true end
        if v == '--no-index' then has_no_index = true end
    end
    eq(has_ref, false)
    eq(has_no_index, true)
end

T['build_git_diff_cmd_with_flags()']['appends -- and path when path is provided'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo', '/repo/foo.lua')
    end)()]])

    local n = #result
    eq(result[n], '/repo/foo.lua')
    eq(result[n - 1], '--')
end

T['build_git_diff_cmd_with_flags()']['inserts /dev/null before path when new_file is true'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({ new_file = true }, nil, '/repo', '/repo/new.lua')
    end)()]])

    local n = #result
    eq(result[n], '/repo/new.lua')
    eq(result[n - 1], '/dev/null')
    eq(result[n - 2], '--')
end

T['build_git_diff_cmd_with_flags()']['omits -- separator and path when path is nil'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo', nil)
    end)()]])

    for _, v in ipairs(result) do
        eq(v == '--', false)
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_window_width()

T['get_window_width()'] = new_set()

-- regression: 'foldcolumn' accepts the 'auto'/'auto:N' forms, not just a plain
-- number. tonumber('auto:9') is nil, which previously crashed get_window_width
-- with "attempt to perform arithmetic on a nil value".
T['get_window_width()']['does not error with auto:N foldcolumn'] = function()
    local result = child.lua_get([[(function()
        vim.o.foldcolumn = 'auto:9'
        vim.o.number = true
        vim.o.signcolumn = 'yes'
        local ok, val = pcall(M.get_window_width, 0)
        return { ok = ok, val = val }
    end)()]])

    eq(result.ok, true)
    eq(type(result.val), 'number')
end

-- width is the window's full width minus the rendered gutter ('textoff').
T['get_window_width()']['subtracts the rendered gutter width'] = function()
    local result = child.lua_get([[(function()
        vim.o.foldcolumn = 'auto:9'
        vim.o.number = true
        vim.o.signcolumn = 'yes'
        local win = vim.api.nvim_get_current_win()
        local full = vim.api.nvim_win_get_width(win)
        local textoff = vim.fn.getwininfo(win)[1].textoff
        return { expected = full - textoff, actual = M.get_window_width(0) }
    end)()]])

    eq(result.actual, result.expected)
end

-- with no gutter, the full window width is returned.
T['get_window_width()']['returns full width when no gutter is shown'] = function()
    local result = child.lua_get([[(function()
        vim.o.foldcolumn = '0'
        vim.o.number = false
        vim.o.relativenumber = false
        vim.o.signcolumn = 'no'
        local win = vim.api.nvim_get_current_win()
        return { full = vim.api.nvim_win_get_width(win), actual = M.get_window_width(0) }
    end)()]])

    eq(result.actual, result.full)
end

return T
