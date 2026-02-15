local M = {}

--- @type DeltaOpts
M.defaults = {
    highlighting = {
        max_similarity_threshold = 0.6  -- delta's default threshold for word-level highlighting
    }
}

-- Current options (merged config)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration by merging user options with defaults
--- @param opts DeltaOpts | nil User configuration options
M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M

--- @class HighlightingOpts
--- @field max_similarity_threshold number | nil defaults to 0.6

--- @class DeltaOpts
--- @field highlighting HighlightingOpts | nil
