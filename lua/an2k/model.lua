-- In-memory model of an ANSI/NIST-ITL transaction, mirroring NBIS an2k:
--
--   file    = { records = { record, ... } }            records[1] is Type-1
--   record  = { type = n, tagged = true,  fields = { field, ... } }
--           | { type = n, tagged = false, header = { ... }, data = "bytes" }
--   field   = { tag = "2.018", type = 2, num = 18, subfields = { { "item", ... }, ... } }
--           | { tag = "10.999", type = 10, num = 999, data = "bytes" }  -- binary data field
--
-- Tagged item values are raw strings exactly as they appear in the file.

local M = {}

-- Binary (fixed-layout) record types and their header fields after LEN.
-- Each entry is { name, byte_count }; `fgp` is 6 single-byte finger positions.
-- Types 3-6 share one layout (NBIS reads all of them the same way).
local image_layout = {
  { "idc", 1 }, { "imp", 1 }, { "fgp", 6 }, { "isr", 1 },
  { "hll", 2 }, { "vll", 2 }, { "gca", 1 },
}
M.binary_layouts = {
  [3] = image_layout,
  [4] = image_layout,
  [5] = image_layout,
  [6] = image_layout,
  -- Type-7 is user-defined beyond LEN and IDC; everything after IDC is data.
  [7] = { { "idc", 1 } },
  [8] = {
    { "idc", 1 }, { "sig", 1 }, { "srt", 1 }, { "isr", 1 },
    { "hll", 2 }, { "vll", 2 },
  },
}
M.BINARY_LEN_BYTES = 4

function M.is_binary_type(t)
  return M.binary_layouts[t] ~= nil
end

-- Size of a binary record header, including LEN.
function M.binary_header_bytes(t)
  local n = M.BINARY_LEN_BYTES
  for _, f in ipairs(M.binary_layouts[t]) do
    n = n + f[2]
  end
  return n
end

function M.format_tag(record_type, num)
  return string.format("%d.%03d", record_type, num)
end

-- Parse "T.NNN" into record type and field number.
function M.parse_tag(tag)
  local t, n = tag:match("^(%d+)%.(%d+)$")
  if not t then
    return nil
  end
  return tonumber(t), tonumber(n)
end

-- Normalize a user-supplied value into the subfields form:
--   "x"                 -> { { "x" } }
--   { "a", "b" }        -> { { "a", "b" } }        one subfield, several items
--   { { "a" }, { "b" } } -> unchanged               several subfields
local function to_subfields(value)
  if type(value) == "string" or type(value) == "number" then
    return { { tostring(value) } }
  end
  assert(type(value) == "table" and #value > 0, "an2k: field value must be a string or non-empty table")
  if type(value[1]) == "table" then
    local out = {}
    for i, sub in ipairs(value) do
      out[i] = {}
      for j, item in ipairs(sub) do
        out[i][j] = tostring(item)
      end
    end
    return out
  end
  local items = {}
  for j, item in ipairs(value) do
    items[j] = tostring(item)
  end
  return { items }
end

function M.new_field(record_type, num, value)
  local f = { tag = M.format_tag(record_type, num), type = record_type, num = num }
  if num == 999 and record_type ~= 1 then
    assert(type(value) == "string", "an2k: field 999 data must be a byte string")
    f.data = value
  else
    f.subfields = to_subfields(value)
  end
  return f
end

-- New tagged record holding LEN (filled in on write) and IDC.
function M.new_tagged_record(record_type, idc)
  local r = { type = record_type, tagged = true, fields = {} }
  r.fields[1] = M.new_field(record_type, 1, "0")
  if record_type ~= 1 then
    r.fields[2] = M.new_field(record_type, 2, string.format("%02d", idc or 0))
  end
  return r
end

function M.new_binary_record(record_type, header, data)
  assert(M.is_binary_type(record_type), "an2k: Type-" .. tostring(record_type) .. " is not a binary record type")
  local h = {}
  for _, f in ipairs(M.binary_layouts[record_type]) do
    local name, n = f[1], f[2]
    local v = header and header[name]
    if name == "fgp" then
      h.fgp = {}
      for i = 1, n do
        h.fgp[i] = (v and v[i]) or 255
      end
    else
      h[name] = v or 0
    end
  end
  return { type = record_type, tagged = false, header = h, data = data or "" }
end

return M
