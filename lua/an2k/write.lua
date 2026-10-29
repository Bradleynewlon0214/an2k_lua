-- Serialize the model (see model.lua) to ANSI/NIST-ITL bytes.
--
-- Unlike NBIS, which keeps LEN/CNT current through its update/insert helpers,
-- this writer recomputes them on every write.  Existing LEN/CNT text is kept
-- verbatim when it is already correct, so unmodified files round-trip
-- byte-for-byte.

local bytes = require("an2k.bytes")
local model = require("an2k.model")
local read = require("an2k.read")

local M = {}

local FS, GS, RS, US = bytes.FS, bytes.GS, bytes.RS, bytes.US

local function field_value(f)
  if f.data then
    return f.data
  end
  local subs = {}
  for i, sub in ipairs(f.subfields) do
    subs[i] = table.concat(sub, US)
  end
  return table.concat(subs, RS)
end

local function find_field(record, num)
  for _, f in ipairs(record.fields) do
    if f.num == num then
      return f
    end
  end
end

-- IDC as it should appear in CNT.
local function record_idc(record)
  if record.tagged then
    local f = find_field(record, 2)
    return f and f.subfields[1][1] or "00"
  end
  return string.format("%02d", record.header.idc)
end

-- Rewrite Type-1 CNT (1.003) if it no longer describes the records.
local function sync_cnt(file)
  local type1 = file.records[1]
  assert(type1 and type1.type == 1, "an2k: first record must be Type-1")
  local list, expected = read.contents(type1)
  local n = #file.records - 1
  local ok = list ~= nil and expected == n and #list == n
  if ok then
    for k = 1, n do
      local r = file.records[k + 1]
      if list[k].type ~= r.type or tonumber(list[k].idc) ~= tonumber(record_idc(r)) then
        ok = false
        break
      end
    end
  end
  if ok then
    return
  end
  local subfields = { { "1", tostring(n) } }
  for k = 1, n do
    local r = file.records[k + 1]
    subfields[k + 1] = { tostring(r.type), record_idc(r) }
  end
  local cnt = find_field(type1, 3)
  if cnt then
    cnt.subfields = subfields
  else
    -- Keep fields ordered by number: CNT goes right after LEN/VER.
    local at = #type1.fields + 1
    for i, f in ipairs(type1.fields) do
      if f.num > 3 then
        at = i
        break
      end
    end
    table.insert(type1.fields, at, { tag = model.format_tag(1, 3), type = 1, num = 3, subfields = subfields })
  end
end

local function write_tagged_record(record, out)
  local len_field = record.fields[1]
  assert(len_field and len_field.num == 1, "an2k: Type-" .. record.type .. " record must start with LEN (field 1)")
  local parts = {}
  for i = 2, #record.fields do
    local f = record.fields[i]
    parts[#parts + 1] = f.tag .. ":" .. field_value(f)
  end
  local rest = (#parts > 0 and (GS .. table.concat(parts, GS)) or "") .. FS
  -- LEN counts its own digits, so solve total = base + #tostring(total).
  local base = #len_field.tag + 1 + #rest
  local old = len_field.subfields and len_field.subfields[1] and len_field.subfields[1][1]
  local len_text
  if old and tonumber(old) == base + #old then
    len_text = old
  else
    for d = 1, 15 do
      if #tostring(base + d) == d then
        len_text = tostring(base + d)
        break
      end
    end
  end
  len_field.subfields = { { len_text } }
  out[#out + 1] = len_field.tag .. ":" .. len_text .. rest
end

local function write_binary_record(record, out)
  local layout = model.binary_layouts[record.type]
  assert(layout, "an2k: Type-" .. record.type .. " is not a binary record type")
  local parts = {}
  for _, f in ipairs(layout) do
    local name, n = f[1], f[2]
    if name == "fgp" then
      local fgp = record.header.fgp
      for i = 1, n do
        parts[#parts + 1] = string.char(fgp[i] or 255)
      end
    else
      parts[#parts + 1] = bytes.uint(record.header[name] or 0, n)
    end
  end
  local body = table.concat(parts) .. record.data
  out[#out + 1] = bytes.uint(model.BINARY_LEN_BYTES + #body, model.BINARY_LEN_BYTES) .. body
end

function M.write_string(file)
  sync_cnt(file)
  local out = {}
  for _, record in ipairs(file.records) do
    if record.tagged then
      write_tagged_record(record, out)
    else
      write_binary_record(record, out)
    end
  end
  return table.concat(out)
end

M.find_field = find_field

return M
