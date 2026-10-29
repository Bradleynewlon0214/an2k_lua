-- Test runner.  Usage (from the repo root):  lua test/run.lua
-- (any Lua 5.1+ / LuaJIT, or nvim -l test/run.lua)

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local an2k = require("an2k")

local FIXTURES = "test/fixtures/"
local fixtures = {
  "face_jpb_DOM_GMT_DCS.an2", "sign_raw.an2", "sign_vec.an2",
  "type_3_wvu.an2", "type_5_wvu.an2", "type_6_wvu.an2",
  "valid1.1.an2", "valid1.2.an2", "valid1.3.an2", "valid1.4.an2",
  "valid1.5.an2", "valid1.6.an2", "valid1.7.an2", "valid1.8.an2",
  "valid1.9.an2", "valid1.10.an2", "valid1.11.an2", "valid1.13.an2",
  "valid1.14.an2", "valid1.15.an2", "valid1.16.an2", "sre_with_face.tdf",
}

local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL ", name, "\n    ", tostring(err), "\n")
  end
end

local function slurp(path)
  local fh = assert(io.open(path, "rb"))
  local s = fh:read("*a")
  fh:close()
  return s
end

local function eq(a, b, what)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", what or "value", tostring(b), tostring(a)), 2)
  end
end

local function first_diff(a, b)
  for i = 1, math.max(#a, #b) do
    if a:byte(i) ~= b:byte(i) then
      return i - 1
    end
  end
end

local function reread(file)
  local s = assert(an2k.write_string(file))
  return assert(an2k.read_string(s)), s
end

---------------------------------------------------------------------------
-- Round trip every NIST sample byte-for-byte.

for _, name in ipairs(fixtures) do
  test("round-trip " .. name, function()
    local src = slurp(FIXTURES .. name)
    local file = assert(an2k.read_string(src))
    local out = assert(an2k.write_string(file))
    if out ~= src then
      error(string.format("output differs at byte %s (%d vs %d bytes)", tostring(first_diff(out, src)), #out, #src))
    end
  end)
end

---------------------------------------------------------------------------
-- Parsing details.

test("Type-1 fields and CNT", function()
  local file = assert(an2k.read_file(FIXTURES .. "valid1.1.an2"))
  local t1 = file.records[1]
  eq(an2k.get_value(t1, 2), "0201", "VER")
  eq(an2k.get_field(t1, 3).subfields[2][1], "2", "CNT[2] type")
  eq(#file.records, 3, "record count")
  eq(file.records[2].type, 2, "record 2 type")
  eq(file.records[3].type, 4, "record 3 type")
  eq(file.records[3].tagged, false, "Type-4 is binary")
  eq(an2k.get_value(file.records[2], 18), "JOHN,CLINTON", "2.018")
end)

test("binary Type-4 header", function()
  local file = assert(an2k.read_file(FIXTURES .. "valid1.1.an2"))
  local r = file.records[3]
  eq(r.header.idc, 1, "IDC")
  eq(#r.header.fgp, 6, "FGP count")
  assert(r.header.hll > 0 and r.header.vll > 0, "image dimensions")
end)

test("Type-8 signature header", function()
  local file = assert(an2k.read_file(FIXTURES .. "sign_vec.an2"))
  local r = an2k.find_records(file, 8)[1]
  assert(r, "has Type-8")
  eq(r.header.sig, 0, "SIG")
  eq(r.header.srt, 2, "SRT (vector)")
end)

test("tagged image field 999 is raw bytes", function()
  local file = assert(an2k.read_file(FIXTURES .. "face_jpb_DOM_GMT_DCS.an2"))
  local r = an2k.find_records(file, 10)[1]
  assert(r, "has Type-10")
  local data = an2k.get_value(r, 999)
  eq(data:sub(1, 2), "\255\216", "JPEG SOI marker")
end)

---------------------------------------------------------------------------
-- Editing: LEN and CNT bookkeeping.

test("edit text field updates LEN", function()
  local file = assert(an2k.read_file(FIXTURES .. "valid1.1.an2"))
  local t2 = file.records[2]
  an2k.set_field(t2, 18, "A,VERY LONG NAME THAT CHANGES THE RECORD LENGTH")
  local again = reread(file)
  eq(an2k.get_value(again.records[2], 18), "A,VERY LONG NAME THAT CHANGES THE RECORD LENGTH", "2.018")
end)

test("LEN digit-count boundary", function()
  -- Grow a record so its LEN crosses from 2 to 3 digits.
  local file = an2k.new()
  local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 1))
  for n = 1, 120 do
    an2k.set_field(t2, 900, string.rep("x", n))
    local again, s = reread(file)
    local len = tonumber(an2k.get_value(again.records[2], 1))
    local t2_bytes = #s - tonumber(an2k.get_value(again.records[1], 1))
    eq(len, t2_bytes, "LEN at n=" .. n)
  end
end)

test("new_field rejects malformed values", function()
  assert(not pcall(an2k.new_field, 2, 18, {}), "empty table")
end)

test("subfields and items", function()
  local file = an2k.new()
  local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 1))
  an2k.set_field(t2, 30, { { "A", "B" }, { "C", "", "E" } })
  local again = reread(file)
  local f = an2k.get_field(again.records[2], 30)
  eq(#f.subfields, 2, "subfields")
  eq(f.subfields[2][3], "E", "item")
  eq(f.subfields[2][2], "", "empty item")
end)

test("fields are kept in numeric order", function()
  local file = an2k.new()
  local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 1))
  an2k.set_field(t2, 20, "b")
  an2k.set_field(t2, 10, "a")
  an2k.set_field(t2, 30, "c")
  local nums = {}
  for _, f in ipairs(t2.fields) do
    nums[#nums + 1] = f.num
  end
  eq(table.concat(nums, ","), "1,2,10,20,30", "order")
end)

test("add records updates CNT", function()
  local file = an2k.new()
  local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 0))
  an2k.set_field(t2, 18, "DOE,JANE")
  an2k.add_record(file, an2k.new_binary_record(4, { idc = 1, imp = 0, fgp = { 2 }, isr = 0, hll = 2, vll = 2, gca = 1 }, "\1\2\3\4"))
  local t10 = an2k.add_record(file, an2k.new_tagged_record(10, 2))
  an2k.set_field(t10, 999, "\28\29\30\31binary with separators")
  local again = reread(file)
  eq(#again.records, 4, "records")
  local cnt = an2k.get_field(again.records[1], 3).subfields
  eq(cnt[1][2], "3", "CNT count")
  eq(cnt[3][1], "4", "CNT record 3 type")
  eq(cnt[4][2], "02", "CNT record 4 IDC")
  eq(again.records[3].data, "\1\2\3\4", "Type-4 data")
  eq(again.records[3].header.fgp[1], 2, "FGP[1]")
  eq(again.records[3].header.fgp[2], 255, "FGP[2] default")
  eq(an2k.get_value(again.records[4], 999), "\28\29\30\31binary with separators", "10.999")
end)

test("delete record updates CNT", function()
  local file = assert(an2k.read_file(FIXTURES .. "valid1.1.an2"))
  an2k.delete_record(file, 3)
  local again = reread(file)
  eq(#again.records, 2, "records")
  eq(an2k.get_field(again.records[1], 3).subfields[1][2], "1", "CNT count")
end)

test("delete field", function()
  local file = assert(an2k.read_file(FIXTURES .. "valid1.1.an2"))
  assert(an2k.delete_field(file.records[2], 18))
  local again = reread(file)
  eq(an2k.get_field(again.records[2], 18), nil, "2.018 gone")
end)

---------------------------------------------------------------------------
-- Malformed input produces errors, not crashes.

local function expect_error(name, s, pattern)
  test("malformed: " .. name, function()
    local file, err = an2k.read_string(s)
    assert(file == nil, "expected failure")
    assert(type(err) == "string" and err:find(pattern), "unexpected error: " .. tostring(err))
  end)
end

local good = slurp(FIXTURES .. "valid1.1.an2")
expect_error("empty", "", "LEN")
expect_error("truncated", good:sub(1, #good - 100), "past end")
expect_error("trailing bytes", good .. "xx", "trailing")
expect_error("bad LEN", (good:gsub("^1%.01:129", "1.01:130", 1)), "does not end with FS")
expect_error("not ANSI/NIST", "hello world", "LEN")
expect_error("wrong record type", (good:gsub("2%.001:", "9.001:", 1)), "CNT lists")

---------------------------------------------------------------------------
-- Builder.

local function base_builder(extra_opts)
  local opts = { tot = "CAR", dat = "20260101", dai = "DAI123456", ori = "ORI123456", tcn = "TCN1234567890" }
  for k, v in pairs(extra_opts or {}) do
    opts[k] = v
  end
  return an2k.builder(opts)
end

local function field_nums(record)
  local nums = {}
  for _, f in ipairs(record.fields) do
    nums[#nums + 1] = f.num
  end
  return table.concat(nums, ",")
end

test("builder: mixed transaction round-trips with LEN/CNT/IDC", function()
  local s = base_builder({ pry = "1", nsr = "19.69", ntr = "19.69", dom = "NORAM", aps = "X" })
    :add(2, { [18] = "DOE,JANE", [26] = { { "A", "B" }, { "C" } } })
    :add_binary(4, { imp = 1, fgp = { 1 }, isr = 0, hll = 2, vll = 2, gca = 1 }, "\255\160wsq")
    :add(10, { [3] = "FACE", [999] = "\255\216\255jpeg\28\29" })
    :add(14, { [13] = "1", [999] = "\255\160wsq" })
    :to_string()
  local file = assert(an2k.read_string(s))
  eq(#file.records, 5, "records")
  eq(field_nums(file.records[1]), "1,2,3,4,5,6,7,8,9,11,12,13,16", "Type-1 field order")
  eq(an2k.get_value(file.records[1], 2), "0502", "default VER")
  local cnt = an2k.get_field(file.records[1], 3).subfields
  eq(cnt[1][2], "4", "CNT count")
  eq(cnt[2][1] .. "/" .. cnt[2][2], "2/00", "CNT Type-2")
  eq(cnt[3][1] .. "/" .. cnt[3][2], "4/01", "CNT Type-4")
  eq(cnt[5][1] .. "/" .. cnt[5][2], "14/03", "CNT Type-14")
  eq(file.records[3].header.idc, 1, "binary IDC")
  eq(an2k.get_value(file.records[4], 2), "02", "tagged IDC")
  eq(an2k.get_value(file.records[4], 999), "\255\216\255jpeg\28\29", "10.999")
  eq(an2k.get_field(file.records[1], 15), nil, "no DCS for ASCII")
  assert(an2k.validate(file), "structurally valid")
end)

test("builder: non-ASCII text adds DCS before APS", function()
  local file = base_builder({ aps = "X" }):add(2, { [18] = "MÜLLER,JÖRG" }):build()
  eq(field_nums(file.records[1]), "1,2,3,4,5,7,8,9,15,16", "DCS position")
  local dcs = an2k.get_field(file.records[1], 15).subfields[1]
  eq(dcs[1] .. "/" .. dcs[2], "3/UTF-8", "DCS value")
  file = base_builder():add(10, { [999] = "\200\201" }):build()
  eq(an2k.get_field(file.records[1], 15), nil, "binary 999 doesn't trigger DCS")
end)

test("builder: extra Type-1 fields and defaults", function()
  local file = base_builder({ dat = false, extra = { [20] = "x", [17] = "y" } }):add(2):build()
  eq(field_nums(file.records[1]), "1,2,3,4,5,7,8,9,17,20", "extras sorted after 16")
  eq(an2k.get_value(file.records[1], 5), os.date("%Y%m%d"), "default DAT")
end)

test("builder: rejects misuse", function()
  assert(not pcall(an2k.builder, { tot = "CAR" }), "missing required options")
  assert(not pcall(function() base_builder():add(2, { [2] = "05" }) end), "caller IDC")
  assert(not pcall(function() base_builder():add(4, {}) end), "binary type via add")
  assert(not pcall(function() base_builder():add_binary(10, {}) end), "tagged type via add_binary")
  assert(not pcall(function() base_builder({ extra = { [9] = "x" } }):build() end), "extra <= 16")
end)

---------------------------------------------------------------------------
-- Validation.

local NORAM = an2k.profiles.noram

local function minimal()
  return base_builder():add(2):build()
end

local function find_err(errors, pred)
  for _, e in ipairs(errors) do
    if pred(e) then
      return e
    end
  end
end

test("validate: valid transaction with matching CNT", function()
  local ok, errors = an2k.validate(minimal())
  assert(ok, errors[1] and errors[1].detail)
end)

test("validate: CNT mismatch when declared records are missing", function()
  local file = minimal()
  an2k.get_field(file.records[1], 3).subfields = { { "1", "2" }, { "10", "00" }, { "14", "01" } }
  local ok, errors = an2k.validate(file)
  assert(not ok)
  assert(find_err(errors, function(e) return e.code == "CNT_MISMATCH" end), "CNT_MISMATCH")
end)

test("validate: NORAM minimal Type-1 + Type-2", function()
  local ok, errors = an2k.validate(minimal(), NORAM)
  assert(ok, errors[1] and errors[1].detail)
end)

test("validate: NORAM Type-1 + Type-2 + Type-14", function()
  local file = base_builder():add(2, { [3] = "test" }):add(14, { [4] = "SRC123", [5] = "20260101", [13] = "1" }):build()
  local ok, errors = an2k.validate(file, NORAM)
  assert(ok, errors[1] and errors[1].detail)
end)

test("validate: NORAM missing mandatory 1.004 TOT", function()
  local file = minimal()
  an2k.delete_field(file.records[1], 4)
  local ok, errors = an2k.validate(file, NORAM)
  assert(not ok)
  local e = find_err(errors, function(x) return x.field_number == 4 end)
  eq(e and e.code, "MISSING_FIELD", "code")
end)

test("validate: NORAM invalid PRY", function()
  local file = minimal()
  an2k.set_field(file.records[1], 6, "0")
  local _, errors = an2k.validate(file, NORAM)
  local e = find_err(errors, function(x) return x.field_number == 6 end)
  eq(e and e.code, "FIELD_PATTERN_MISMATCH", "code")
end)

test("validate: record min_occurs", function()
  local profile = { name = "t", records = {} }
  for k, v in pairs(NORAM.records) do
    profile.records[k] = v
  end
  profile.records[10] = { min_occurs = 1, max_occurs = 99, fields = {} }
  local _, errors = an2k.validate(minimal(), profile)
  assert(find_err(errors, function(e) return e.code == "TOO_FEW_RECORDS" and e.record_type == 10 end), "TOO_FEW_RECORDS")
end)

test("validate: NORAM VER not numeric", function()
  local file = minimal()
  an2k.set_field(file.records[1], 2, "ABCD")
  local _, errors = an2k.validate(file, NORAM)
  local e = find_err(errors, function(x) return x.field_number == 2 end)
  eq(e and e.code, "FIELD_CHARACTER_TYPE_MISMATCH", "code")
end)

test("validate: CNT subfield count within and over limit", function()
  assert(an2k.validate(minimal(), NORAM))
  local file = minimal()
  local subs = {}
  for i = 1, 100 do
    subs[i] = { "99", "00" }
  end
  an2k.get_field(file.records[1], 3).subfields = subs
  local _, errors = an2k.validate(file, NORAM)
  assert(find_err(errors, function(e) return e.code == "TOO_MANY_SUBFIELDS" end), "TOO_MANY_SUBFIELDS")
end)

test("validate: sre_with_face.tdf", function()
  local file = assert(an2k.read_file(FIXTURES .. "sre_with_face.tdf"))
  eq(an2k.get_value(file.records[1], 2), "0500", "version")
  assert(an2k.validate(file), "valid without profile")
  local ok, errors = an2k.validate(file, NORAM)
  assert(not ok)
  local e = find_err(errors, function(x) return x.field_number == 4 and x.record_type == 10 end)
  eq(e and e.code, "MISSING_FIELD", "10.004 SRC missing")
end)

test("validate: subfield item constraints", function()
  local profile = { name = "t", records = { [2] = { fields = {
    { field = 30, subfields = { min_subfields = 2, items = {
      { name = "CODE", mandatory = true, character_type = "N", max_length = 2, allowed_values = { "1", "22" } },
      false,
      { name = "TAIL", mandatory = true, pattern = "^x" },
    } } },
  } } } }
  local file = base_builder():add(2, { [30] = { { "1", "q", "xy" }, { "ABC", "q" } } }):build()
  local _, errors = an2k.validate(file, profile)
  local codes = {}
  for _, e in ipairs(errors) do
    codes[#codes + 1] = e.code .. "@" .. tostring(e.subfield_index)
  end
  eq(table.concat(codes, " "),
    "SUBFIELD_ITEM_TOO_LONG@2 FIELD_CHARACTER_TYPE_MISMATCH@2 SUBFIELD_ITEM_VALUE_NOT_ALLOWED@2 MISSING_SUBFIELD_ITEM@2",
    "item errors")
end)

test("validate: custom validator function", function()
  local profile = { name = "t", records = { [1] = { fields = {
    { field = 9, validator = function(value, ctx)
      if ctx.transaction_version ~= "0502" or not value:find("^TCN") then
        return { code = "BAD_TCN", detail = "bad" }
      end
    end },
  } } } }
  assert(an2k.validate(minimal(), profile))
  local file = minimal()
  an2k.set_field(file.records[1], 9, "nope")
  local _, errors = an2k.validate(file, profile)
  eq(errors[1] and errors[1].code, "BAD_TCN", "custom error")
  eq(errors[1].field_number, 9, "ctx filled in")
end)

test("validate: every fixture against every profile without crashing", function()
  for _, name in ipairs(fixtures) do
    local file = assert(an2k.read_file(FIXTURES .. name))
    assert(an2k.validate(file), name .. " structurally valid")
    for _, pname in ipairs(an2k.profiles.names) do
      an2k.validate(file, an2k.profiles[pname])
    end
  end
end)

io.write(string.format("%d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
