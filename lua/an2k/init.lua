-- an2k: read/write ANSI/NIST-ITL (and FBI EBTS) transaction files.
-- Pure Lua port of the NBIS an2k container layer; runs on LuaJIT / Lua 5.1+.
--
--   local an2k = require("an2k")
--   local file = assert(an2k.read_file("in.eft"))
--   local t2 = an2k.find_records(file, 2)[1]
--   print(an2k.get_value(t2, 18))          -- 2.018 NAM
--   an2k.set_field(t2, 18, "DOE,JANE")
--   assert(an2k.write_file(file, "out.eft"))
--
-- See model.lua for the table layout.  Read/write functions return nil, err
-- on failure; edit helpers raise errors on misuse.

local model = require("an2k.model")
local read = require("an2k.read")
local write = require("an2k.write")
local builder = require("an2k.builder")
local validate = require("an2k.validate")

local M = {}

M.builder = builder.new
M.validate = validate.validate
M.profiles = require("an2k.profiles")
M.VERSION_2011, M.VERSION_2013, M.VERSION_2015 = builder.VERSION_2011, builder.VERSION_2013, builder.VERSION_2015

M.new_field = model.new_field
M.new_tagged_record = model.new_tagged_record
M.new_binary_record = model.new_binary_record

function M.read_string(s)
  local ok, res = pcall(read.read_string, s)
  if not ok then
    return nil, res
  end
  return res
end

function M.read_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then
    return nil, err
  end
  local s = fh:read("*a")
  fh:close()
  return M.read_string(s)
end

function M.write_string(file)
  local ok, res = pcall(write.write_string, file)
  if not ok then
    return nil, res
  end
  return res
end

function M.write_file(file, path)
  local s, err = M.write_string(file)
  if not s then
    return nil, err
  end
  local fh
  fh, err = io.open(path, "wb")
  if not fh then
    return nil, err
  end
  fh:write(s)
  fh:close()
  return true
end

-- New transaction holding a Type-1 record with LEN, VER and an empty CNT.
function M.new(version)
  local type1 = model.new_tagged_record(1)
  type1.fields[2] = model.new_field(1, 2, version or "0500")
  type1.fields[3] = model.new_field(1, 3, { "1", "0" })
  return { records = { type1 } }
end

---------------------------------------------------------------------------
-- Records

-- All records of `record_type`, in file order.
function M.find_records(file, record_type)
  local out = {}
  for _, r in ipairs(file.records) do
    if r.type == record_type then
      out[#out + 1] = r
    end
  end
  return out
end

-- Insert `record` at `index` (default: end).  CNT is updated on write.
function M.add_record(file, record, index)
  assert(record.type ~= 1, "an2k: a file has exactly one Type-1 record")
  index = index or #file.records + 1
  assert(index >= 2 and index <= #file.records + 1, "an2k: record index out of range")
  table.insert(file.records, index, record)
  return record
end

function M.delete_record(file, index)
  assert(index >= 2 and index <= #file.records, "an2k: record index out of range (Type-1 cannot be deleted)")
  return table.remove(file.records, index)
end

---------------------------------------------------------------------------
-- Fields (tagged records only)

local function check_tagged(record)
  assert(record.tagged, "an2k: Type-" .. record.type .. " is a binary record; use record.header / record.data")
end

M.get_field = function(record, num)
  check_tagged(record)
  return write.find_field(record, num)
end

-- First item of the first subfield (or binary data for field 999).
function M.get_value(record, num)
  local f = M.get_field(record, num)
  if not f then
    return nil
  end
  if f.data then
    return f.data
  end
  return f.subfields[1][1]
end

-- Create or replace field `num`.  `value` is a string, a list of items
-- (one subfield), or a list of item lists (several subfields).  New fields
-- are inserted in field-number order.
function M.set_field(record, num, value)
  check_tagged(record)
  assert(num ~= 1, "an2k: LEN (field 1) is computed on write")
  local new = model.new_field(record.type, num, value)
  for i, f in ipairs(record.fields) do
    if f.num == num then
      new.tag = f.tag -- keep the original tag spelling (e.g. "1.03")
      record.fields[i] = new
      return new
    end
    if f.num > num then
      table.insert(record.fields, i, new)
      return new
    end
  end
  record.fields[#record.fields + 1] = new
  return new
end

function M.delete_field(record, num)
  check_tagged(record)
  assert(num ~= 1, "an2k: LEN (field 1) cannot be deleted")
  for i, f in ipairs(record.fields) do
    if f.num == num then
      return table.remove(record.fields, i)
    end
  end
end

return M
