local M = {}

--- @type DeltaOpts
M.defaults = {
    highlighting = {
        max_similarity_threshold = 0.6  -- delta's default threshold for word-level highlighting
    },
    highlight_groups = {
        dark = {
            DeltaDiffAddedLine = {
                bg = '#002800',  -- dark green background
                default = true
            },
            DeltaDiffRemovedLine = {
                bg = '#3f0001',  -- dark red background
                default = true
            },
            DeltaDiffAddedWord = {
                bg = '#006000',  -- brighter green
                default = true
            },
            DeltaDiffRemovedWord = {
                bg = '#901011',  -- brighter red
                default = true
            },
            DeltaTitle = {
                fg = '#24acd4',  -- light blue
                default = true
            }
        },
        light = {
            DeltaDiffAddedLine = {
                bg = '#cfffd0',  -- light green background
                default = true
            },
            DeltaDiffRemovedLine = {
                bg = '#ffdee2',  -- light red background
                default = true
            },
            DeltaDiffAddedWord = {
                bg = '#9df0a2',  -- darker green (word level)
                default = true
            },
            DeltaDiffRemovedWord = {
                bg = '#ffc1bf',  -- darker red (word level)
                default = true
            },
            DeltaTitle = {
                fg = '#0088aa',  -- darker blue for light backgrounds
                default = true
            }
        }
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

--- @class HighlightGroupDef
--- @field fg string | nil Foreground color
--- @field bg string | nil Background color
--- @field default boolean | nil Whether to use default (won't override user customizations)

--- @class HighlightGroupSet
--- @field DeltaDiffAddedLine HighlightGroupDef | nil
--- @field DeltaDiffRemovedLine HighlightGroupDef | nil
--- @field DeltaDiffAddedWord HighlightGroupDef | nil
--- @field DeltaDiffRemovedWord HighlightGroupDef | nil
--- @field DeltaTitle HighlightGroupDef | nil

--- @class HighlightGroupsOpts
--- @field dark HighlightGroupSet | nil Highlight groups for dark backgrounds
--- @field light HighlightGroupSet | nil Highlight groups for light backgrounds

--- @class DeltaOpts
--- @field highlighting HighlightingOpts | nil
--- @field highlight_groups HighlightGroupsOpts | nil
