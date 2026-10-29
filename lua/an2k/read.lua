-- Parse ANSI/NIST-ITL bytes into the model (see model.lua).
-- Port of NBIS an2k fmtstd.c read routines; errors are raised with error().

local bytes = require("an2k.bytes")
local model = require("an2k.model")

local M = {}

local FS, GS, RS, US = bytes.FS, bytes.GS, bytes.RS, bytes.US

local function fail(ctx, pos, msg)
  error(string.format("an2k: record %d (Type-%s) at byte %d: %s", ctx.index, tostring(ctx.type), pos - 1, msg), 0)
end

local function parse_value(value)
  local subfields = bytes.split(value, RS)
  for i, sub in ipairs(subfields) do
    subfields[i] = bytes.split(sub, US)
  end
  return subfields
end

-- Read the LEN field of the tagged record starting at `pos`; returns the record length.
local function tagged_record_length(s, pos, ctx)
  local colon = s:find(":", pos, true)
  if not colon or colon - pos > 12 then
    fail(ctx, pos, "missing LEN field ID")
  end
  local t, n = model.parse_tag(s:sub(pos, colon - 1))
  if not t or n ~= 1 then
    fail(ctx, pos, "first field is not LEN (" .. s:sub(pos, colon - 1) .. ")")
  end
  if ctx.type and t ~= ctx.type then
    fail(ctx, pos, string.format("record is Type-%d but CNT lists Type-%d", t, ctx.type))
  end
  local stop = s:find("[\28\29]", colon + 1)
  local len = stop and tonumber(s:sub(colon + 1, stop - 1))
  if not len then
    fail(ctx, pos, "malformed LEN value")
  end
  return t, len
end

-- Parse one tagged record occupying s[pos, pos+len-1].
local function read_tagged_record(s, pos, ctx)
  local record_type, len = tagged_record_length(s, pos, ctx)
  ctx.type = record_type
  local stop = pos + len - 1
  if stop > #s then
    fail(ctx, pos, string.format("LEN %d runs past end of data (%d bytes left)", len, #s - pos + 1))
  end
  if s:sub(stop, stop) ~= FS then
    fail(ctx, stop, "record does not end with FS")
  end

  local record = { type = record_type, tagged = true, fields = {} }
  local i = pos
  while i <= stop do
    local colon = s:find(":", i, true)
    if not colon or colon > stop then
      fail(ctx, i, "missing field ID")
    end
    local tag = s:sub(i, colon - 1)
    local t, n = model.parse_tag(tag)
    if not t then
      fail(ctx, i, "malformed field ID '" .. tag .. "'")
    end
    if t ~= record_type then
      fail(ctx, i, string.format("field %s inside Type-%d record", tag, record_type))
    end
    local field = { tag = tag, type = t, num = n }
    if n == 999 and record_type ~= 1 then
      -- Binary data runs to the record's trailing FS (may contain separator bytes).
      field.data = s:sub(colon + 1, stop - 1)
      i = stop + 1
    else
      local d = s:find("[\28\29]", colon + 1)
      if not d or d > stop then
        fail(ctx, colon, "field " .. tag .. " is not terminated")
      end
      if s:sub(d, d) == FS and d ~= stop then
        fail(ctx, d, string.format("FS before end of record (LEN says %d bytes)", len))
      end
      field.subfields = parse_value(s:sub(colon + 1, d - 1))
      i = d + 1
    end
    record.fields[#record.fields + 1] = field
  end
  return record, stop + 1
end

local function read_binary_record(s, pos, ctx)
  local record_type = ctx.type
  local len = bytes.read_uint(s, pos, model.BINARY_LEN_BYTES)
  if not len then
    fail(ctx, pos, "truncated LEN")
  end
  local header_bytes = model.binary_header_bytes(record_type)
  if len < header_bytes then
    fail(ctx, pos, string.format("LEN %d smaller than %d-byte header", len, header_bytes))
  end
  if pos + len - 1 > #s then
    fail(ctx, pos, string.format("LEN %d runs past end of data (%d bytes left)", len, #s - pos + 1))
  end
  local header = {}
  local p = pos + model.BINARY_LEN_BYTES
  for _, f in ipairs(model.binary_layouts[record_type]) do
    local name, n = f[1], f[2]
    if name == "fgp" then
      header.fgp = { s:byte(p, p + n - 1) }
    else
      header[name] = bytes.read_uint(s, p, n)
    end
    p = p + n
  end
  local record = { type = record_type, tagged = false, header = header, data = s:sub(p, pos + len - 1) }
  return record, pos + len
end

-- Extract the (type, idc) list from Type-1 field 1.003 (CNT).
function M.contents(type1)
  for _, f in ipairs(type1.fields) do
    if f.num == 3 then
      local first = f.subfields[1]
      local expected = tonumber(first[2])
      local list = {}
      for k = 2, #f.subfields do
        local sub = f.subfields[k]
        list[#list + 1] = { type = tonumber(sub[1]), idc = sub[2] }
      end
      return list, expected
    end
  end
  return nil
end

function M.read_string(s)
  local ctx = { index = 1, type = 1 }
  local type1, pos = read_tagged_record(s, 1, ctx)
  local file = { records = { type1 } }

  local list, expected = M.contents(type1)
  if not list then
    fail(ctx, 1, "Type-1 has no CNT (1.003) field")
  end
  if expected and expected ~= #list then
    fail(ctx, 1, string.format("CNT says %d records but lists %d", expected, #list))
  end
  for k, entry in ipairs(list) do
    ctx.index, ctx.type = k + 1, entry.type
    if not entry.type then
      fail(ctx, pos, "CNT entry has non-numeric record type")
    end
    if pos > #s then
      fail(ctx, pos, "data ends before all CNT records were read")
    end
    local record
    if model.is_binary_type(entry.type) then
      record, pos = read_binary_record(s, pos, ctx)
    else
      record, pos = read_tagged_record(s, pos, ctx)
    end
    file.records[#file.records + 1] = record
  end
  if pos <= #s then
    ctx.index = #file.records + 1
    ctx.type = "?"
    fail(ctx, pos, string.format("%d trailing bytes after last CNT record", #s - pos + 1))
  end
  return file
end

return M
