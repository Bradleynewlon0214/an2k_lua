-- Build a new transaction from scratch: standard Type-1 field order, sequential
-- IDCs and automatic DCS.  LEN and CNT come from the writer, as for any model.
--
--   local b = an2k.builder({ tot = "CAR", dai = "DAI123456", ori = "ORI123456", tcn = "TCN1" })
--   b:add(2, { [18] = "DOE,JANE" })
--   b:add(10, { [3] = "FACE", [999] = jpeg_bytes })
--   b:add_binary(4, { imp = 0, fgp = { 1 }, isr = 0, hll = 800, vll = 750, gca = 1 }, wsq_bytes)
--   local file = b:build()              -- or b:to_string(), b:write(path)

local model = require("an2k.model")
local write = require("an2k.write")

local M = {}

M.VERSION_2011 = "0500"
M.VERSION_2013 = "0501"
M.VERSION_2015 = "0502"

local Builder = {}
Builder.__index = Builder

-- Type-1 options and the field numbers they fill, in output order (DCS 15 is automatic).
local type1_fields = {
  { "ver", 2 }, { "tot", 4 }, { "dat", 5 }, { "pry", 6 }, { "dai", 7 }, { "ori", 8 },
  { "tcn", 9 }, { "tcr", 10 }, { "nsr", 11 }, { "ntr", 12 }, { "dom", 13 }, { "gmt", 14 },
  { "aps", 16 },
}
local required = { "tot", "dai", "ori", "tcn" }

function M.new(opts)
  opts = opts or {}
  for _, k in ipairs(required) do
    assert(opts[k], "an2k.builder: option '" .. k .. "' is required")
  end
  return setmetatable({ opts = opts, content = {} }, Builder)
end

-- Add a tagged record (Type-2, 9, 10, 13-22, 98, 99, ...).  `fields` maps field
-- number to a value in any form model.new_field accepts; 999 takes raw bytes.
function Builder:add(record_type, fields)
  assert(record_type ~= 1, "an2k.builder: Type-1 is built from the options")
  assert(not model.is_binary_type(record_type), "an2k.builder: use add_binary for Type-" .. record_type)
  fields = fields or {}
  assert(fields[1] == nil and fields[2] == nil, "an2k.builder: LEN (1) and IDC (2) are computed")
  self.content[#self.content + 1] = { type = record_type, fields = fields }
  return self
end

-- Add a binary record (Types 3-8).  `header` uses model.binary_layouts names; IDC is assigned.
function Builder:add_binary(record_type, header, data)
  assert(model.is_binary_type(record_type), "an2k.builder: Type-" .. record_type .. " is not a binary record type")
  self.content[#self.content + 1] = { type = record_type, header = header or {}, data = data or "" }
  return self
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    assert(type(k) == "number", "an2k.builder: field keys must be numbers")
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local function has_high_bytes(value)
  if type(value) == "table" then
    for _, v in ipairs(value) do
      if has_high_bytes(v) then
        return true
      end
    end
    return false
  end
  return tostring(value):find("[\128-\255]") ~= nil
end

function Builder:build()
  local opts = self.opts
  local records = {}
  local needs_utf8 = false

  for idc0, c in ipairs(self.content) do
    local idc = idc0 - 1
    local record
    if c.header then
      local header = {}
      for k, v in pairs(c.header) do
        header[k] = v
      end
      header.idc = idc
      record = model.new_binary_record(c.type, header, c.data)
    else
      record = model.new_tagged_record(c.type, idc)
      for _, num in ipairs(sorted_keys(c.fields)) do
        local value = c.fields[num]
        if num ~= 999 and has_high_bytes(value) then
          needs_utf8 = true
        end
        record.fields[#record.fields + 1] = model.new_field(c.type, num, value)
      end
    end
    records[#records + 1] = record
  end

  local type1 = model.new_tagged_record(1)
  local values = {
    ver = opts.ver or M.VERSION_2015,
    dat = opts.dat or os.date("%Y%m%d"),
  }
  for _, def in ipairs(type1_fields) do
    local key, num = def[1], def[2]
    local value = values[key] or opts[key]
    if value then
      type1.fields[#type1.fields + 1] = model.new_field(1, num, value)
    end
    if num == 2 then
      -- CNT placeholder; the writer fills it from the record list.
      type1.fields[#type1.fields + 1] = model.new_field(1, 3, { "1", "0" })
    end
  end
  for _, def in ipairs(type1_fields) do
    if def[1] ~= "ver" and opts[def[1]] and has_high_bytes(opts[def[1]]) then
      needs_utf8 = true
    end
  end
  if needs_utf8 then
    -- DCS goes between GMT (14) and APS (16).
    local at = #type1.fields + 1
    for i, f in ipairs(type1.fields) do
      if f.num > 15 then
        at = i
        break
      end
    end
    table.insert(type1.fields, at, model.new_field(1, 15, { "3", "UTF-8" }))
  end
  for _, num in ipairs(sorted_keys(opts.extra or {})) do
    assert(num > 16, "an2k.builder: extra Type-1 fields must be > 16 (got " .. num .. ")")
    type1.fields[#type1.fields + 1] = model.new_field(1, num, opts.extra[num])
  end

  table.insert(records, 1, type1)
  local file = { records = records }
  -- Fill LEN and CNT now so the returned model is complete before any write.
  write.write_string(file)
  return file
end

function Builder:to_string()
  return write.write_string(self:build())
end

function Builder:write(path)
  local s = self:to_string()
  local fh, err = io.open(path, "wb")
  if not fh then
    return nil, err
  end
  fh:write(s)
  fh:close()
  return true
end

return M
