# lua-an2k

Read and write ANSI/NIST-ITL transaction files (the container format under FBI EBTS)
in pure Lua. Runs on LuaJIT / Neovim and Lua 5.1+, no C dependencies.

It is a port of the container layer of NIST's NBIS `an2k` library (public domain).
Image payloads (WSQ, JPEG, JP2, …) are passed through as raw bytes; EBTS rules
(which fields each TOT requires, Type-2 field definitions) are not checked here.

```lua
local an2k = require("an2k")

local file = assert(an2k.read_file("in.eft"))
local t2 = an2k.find_records(file, 2)[1]
print(an2k.get_value(t2, 18))                     -- 2.018 NAM
an2k.set_field(t2, 18, "DOE,JANE")
an2k.set_field(t2, 30, { { "A", "B" }, { "C" } }) -- subfields of items
assert(an2k.write_file(file, "out.eft"))          -- LEN and CNT recomputed
```

Building a transaction from scratch:

```lua
local file = an2k.new("0500")
local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 0))
an2k.set_field(t2, 18, "DOE,JANE")
local t14 = an2k.add_record(file, an2k.new_tagged_record(14, 1))
an2k.set_field(t14, 999, wsq_bytes)
an2k.add_record(file, an2k.new_binary_record(4, { idc = 2, fgp = { 1 }, hll = 800, vll = 750, gca = 1 }, wsq_bytes))
```

## Building transactions

`an2k.builder` builds a transaction from options: Type-1 is written in
standard field order, IDCs are assigned sequentially, DCS (1.015 = `3␟UTF-8`) is added when any
text is non-ASCII, and LEN/CNT are computed.

```lua
local b = an2k.builder({
  tot = "CAR", dai = "DAI123456", ori = "ORI123456", tcn = "TCN1234567890",
  -- optional: ver (default "0502"), dat (default today), pry, tcr, nsr, ntr, dom, gmt, aps,
  -- extra = { [17] = "..." }  -- additional Type-1 fields > 16
})
b:add(2, { [18] = "DOE,JANE", [64] = { { "784336970", "CRIMINAL" } } })
b:add_binary(4, { imp = 0, fgp = { 2 }, isr = 0, hll = 800, vll = 750, gca = 1 }, wsq_bytes)
b:add(10, { [3] = "FACE", [999] = jpeg_bytes })
local file = b:build()        -- model; or b:to_string(), b:write("out.eft")
```

## Validation

```lua
local ok, errors = an2k.validate(file)                        -- structure: Type-1, CNT vs records
local ok, errors = an2k.validate(file, an2k.profiles.fbi_ebts_11)
for _, e in ipairs(errors) do print(e.code, e.record_index, e.field_number, e.detail) end
```

Profiles `noram`, `fbi_ebts_11` and `dod_ebts_4_1` are included. Checks: record min/max occurrences,
mandatory fields, length, allowed values, Lua `pattern`, character type (A/AN/N/H), subfield
counts and per-item constraints, and an optional `validator(value, ctx)` function. The CNT check
is stricter: 1.003 must list the actual records in order with matching IDCs.

## Model

```
file   = { records = { type1, ... } }
record = { type = n, tagged = true,  fields = { field, ... } }
       | { type = n, tagged = false, header = { idc=, imp=, fgp={6 bytes}, ... }, data = bytes }
field  = { tag = "2.018", type = 2, num = 18, subfields = { { item, ... }, ... } }
       | { tag = "10.999", type = 10, num = 999, data = bytes }
```

Binary records are Types 3–8 (Type-7: only LEN and IDC are parsed; the rest is `data`).
Every other type is parsed as tagged, with field 999 as raw bytes.

## Writing

LEN for each record and Type-1 CNT (1.003) are recomputed on every write. Existing
text is kept as-is when it is already correct, so unmodified files round-trip
byte-for-byte (including old-style tags like `1.01`).

## Neovim

The Neovim viewer/editor lives in its own plugin, [an2k.nvim](../an2k.nvim).

## Tests

```
lua test/run.lua      # or luajit / nvim -l
```

`test/fixtures/` holds NIST's sample files from NBIS (`misc/an2kconvert/testdata`).
