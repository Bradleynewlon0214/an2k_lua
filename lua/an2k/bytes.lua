-- Big-endian integer helpers and separator constants.
-- Plain arithmetic only, so this runs on Lua 5.1 / LuaJIT as well as 5.2+.

local M = {}

M.FS = "\28" -- record separator (terminates every tagged record)
M.GS = "\29" -- field separator
M.RS = "\30" -- subfield separator
M.US = "\31" -- information item separator

local byte, char, floor = string.byte, string.char, math.floor
local unpack = table.unpack or unpack

-- Read an unsigned big-endian integer of `n` bytes from `s` at 1-based `pos`.
-- Returns nil if fewer than `n` bytes remain.
function M.read_uint(s, pos, n)
  if pos + n - 1 > #s then
    return nil
  end
  local v = 0
  for i = pos, pos + n - 1 do
    v = v * 256 + byte(s, i)
  end
  return v
end

-- Encode `v` as an unsigned big-endian integer of `n` bytes.
function M.uint(v, n)
  assert(v >= 0 and v < 256 ^ n and v == floor(v), "an2k: integer out of range for " .. n .. " bytes: " .. tostring(v))
  local t = {}
  for i = n, 1, -1 do
    t[i] = v % 256
    v = floor(v / 256)
  end
  return char(unpack(t))
end

-- Split `s` on the single-character separator `sep`, keeping empty pieces.
function M.split(s, sep)
  local out, i = {}, 1
  while true do
    local j = s:find(sep, i, true)
    if not j then
      out[#out + 1] = s:sub(i)
      return out
    end
    out[#out + 1] = s:sub(i, j - 1)
    i = j + 1
  end
end

return M
