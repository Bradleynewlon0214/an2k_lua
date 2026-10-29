-- Application profiles for an2k.validate().

local M = {}

M.names = { "noram", "fbi_ebts_11", "dod_ebts_4_1" }

return setmetatable(M, {
  __index = function(t, name)
    for _, n in ipairs(M.names) do
      if n == name then
        local profile = require("an2k.profiles." .. name)
        rawset(t, name, profile)
        return profile
      end
    end
  end,
})
