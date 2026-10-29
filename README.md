# lua-an2k

A pure-Lua library for reading, editing, building and validating ANSI/NIST-ITL
transaction files: the binary container used for biometric data exchange, and the
format underneath FBI EBTS and DoD EBTS (`.eft`, `.ebts`, `.an2`, `.nist`).

- **Pure Lua.** Runs on Lua 5.1+ and LuaJIT, with no C modules or other dependencies.
- **Lossless.** Unmodified files are written back byte-for-byte. Edited files get LEN
  and CNT recomputed automatically.
- **Tagged and binary records.** Reads and writes tagged records (Types 1, 2, 9, 10,
  13–22, 98, 99, …) and fixed-layout binary records (Types 3–8).
- **Validation.** Checks transaction structure, and optionally checks against the
  NORAM, FBI EBTS 11 and DoD EBTS 4.1 application profiles.

The container layer is a port of the `an2k` library in NIST's NBIS (public domain).
Image payloads (WSQ, JPEG, JPEG 2000, PNG, …) are kept as raw bytes;
this library doesn't encode or decode images.

## Installation

Put `lua/` on your `package.path` and `require("an2k")`:

```lua
package.path = "/path/to/lua-an2k/lua/?.lua;/path/to/lua-an2k/lua/?/init.lua;" .. package.path
local an2k = require("an2k")
```

## Reading and editing

```lua
local an2k = require("an2k")

local file = assert(an2k.read_file("in.eft"))
local t2 = an2k.find_records(file, 2)[1]
print(an2k.get_value(t2, 18))                     -- 2.018 NAM
an2k.set_field(t2, 18, "DOE,JANE")
an2k.set_field(t2, 30, { { "A", "B" }, { "C" } }) -- subfields of items
an2k.delete_field(t2, 73)
assert(an2k.write_file(file, "out.eft"))          -- LEN and CNT recomputed
```

| Function | Description |
|---|---|
| `read_file(path)`, `read_string(s)` | Parse a transaction. Returns the model, or `nil, err`. |
| `write_file(file, path)`, `write_string(file)` | Serialize the model. Returns `true` or the bytes, or `nil, err`. |
| `new([version])` | Empty transaction holding only a Type-1 record (default version `"0500"`). |
| `find_records(file, type)` | All records of one type, in file order. |
| `add_record(file, record[, index])`, `delete_record(file, index)` | Insert or remove a record. Type-1 is fixed at index 1. |
| `new_tagged_record(type, idc)`, `new_binary_record(type, header, data)` | Construct records. |
| `get_field(record, num)`, `get_value(record, num)` | Return a field, or its first item (the raw bytes for field 999). |
| `set_field(record, num, value)`, `delete_field(record, num)` | Edit a tagged record. `value` is a string, a list of items, or a list of item lists. |

Read and write functions return `nil, err` on failure. The edit helpers raise an error on
misuse, such as setting LEN, deleting Type-1, or editing fields on a binary record.

## Building transactions

`an2k.builder` builds a transaction from scratch. It writes Type-1 in standard field order
and assigns IDCs sequentially. It adds DCS (1.015 = `3␟UTF-8`) when any text is non-ASCII.

```lua
local b = an2k.builder({
  tot = "CAR", dai = "DAI123456", ori = "ORI123456", tcn = "TCN1234567890",
  -- optional: ver (default an2k.VERSION_2015 = "0502"), dat (default today), pry, tcr,
  -- nsr, ntr, dom, gmt, aps
})
b:add(2, { [18] = "DOE,JANE", [64] = { { "784336970", "CRIMINAL" } } })
b:add_binary(4, { imp = 0, fgp = { 2 }, isr = 0, hll = 800, vll = 750, gca = 1 }, wsq_bytes)
b:add(10, { [3] = "FACE", [999] = jpeg_bytes })
local file = b:build()        -- the model; or b:to_string(), b:write("out.eft")
```

You can also build a transaction by hand from the model:

```lua
local file = an2k.new("0500")
local t2 = an2k.add_record(file, an2k.new_tagged_record(2, 0))
an2k.set_field(t2, 18, "DOE,JANE")
an2k.add_record(file, an2k.new_binary_record(4, { idc = 1, fgp = { 1 }, hll = 800, vll = 750, gca = 1 }, wsq_bytes))
```

## Validation

```lua
local ok, errors = an2k.validate(file)                          -- structure only
local ok, errors = an2k.validate(file, an2k.profiles.fbi_ebts_11)
for _, e in ipairs(errors) do
  print(e.code, e.record_index, e.field_number, e.detail)
end
```

The structural check requires a Type-1 record whose CNT (1.003) lists the actual records,
in order, with matching IDCs.

With a profile, the validator also checks:
- how many times each record type occurs (min/max)
- mandatory fields
- field length
- allowed values
- Lua `pattern`
- character type (A/AN/N/H)
- subfield counts and per-item constraints
- an optional `validator(value, ctx)` function

The profile names are listed in `an2k.profiles.names`: `noram`, `fbi_ebts_11` and
`dod_ebts_4_1`. Each profile is a plain Lua table in `lua/an2k/profiles/`.

## Model

A transaction is a plain Lua table:

```
file   = { records = { type1, ... } }
record = { type = n, tagged = true,  fields = { field, ... } }
       | { type = n, tagged = false, header = { idc=, imp=, fgp={6 bytes}, ... }, data = bytes }
field  = { tag = "2.018", type = 2, num = 18, subfields = { { item, ... }, ... } }
       | { tag = "10.999", type = 10, num = 999, data = bytes }
```

Item values are raw strings exactly as they appear in the file. Binary records are Types 3–8.
Types 3–6 have the header fields `idc imp fgp isr hll vll gca`, and Type-8 has
`idc sig srt isr hll vll`. For Type-7 only LEN and IDC are parsed, and the rest goes into `data`.
All other record types are parsed as tagged records, with field 999 kept as raw bytes.

## Writing

Each write recomputes the LEN of every record and the Type-1 CNT (1.003). Existing text that
is already correct is kept as-is, including old-style tags like `1.01`. As a result,
unmodified files round-trip byte-for-byte.

## Tests

```
lua test/run.lua      # or luajit test/run.lua
```

`test/fixtures/` holds NIST's sample transactions from NBIS (`misc/an2kconvert/testdata`).
