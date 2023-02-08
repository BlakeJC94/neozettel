local M = {}

local opts = require("neozettel.opts")
local core = require("neozettel.core")

function M.setup(config)
    opts.set(config or {})
    core.setup_command()
end

-- local note_functions = require("neozettel.note")
-- M = vim.tbl_deep_extend("force", M, note_functions)

-- TODO remove once core command is set
M.note = require("neozettel.core.note").note
M.daily = require("neozettel.core.daily").daily
M.weekly = require("neozettel.core.weekly").weekly
M.monthly = require("neozettel.core.monthly").monthly

M.neozettel = require("neozettel.core").neozettel

return M
