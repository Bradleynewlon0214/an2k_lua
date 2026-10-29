-- Validate a transaction model, optionally against an application profile.
--
-- A profile (see lua/an2k/profiles/) is:
--   { name, version, description, records = { [type] = {
--       min_occurs?, max_occurs?, fields = { {
--         field, mandatory?, min_length?, max_length?, character_type?,  -- A AN N H checked
--         allowed_values?, pattern? (Lua pattern), validator?(value, ctx) -> nil | error,
--         subfields? = { min_subfields?, max_subfields?, items? = { constraint | false, ... } },
--       }, ... } } } }
--
-- Each error is { code, detail, record_type?, record_index?, field_number?, subfield_index? }
-- (record_index and subfield_index are 1-based).

local read = require("an2k.read")

local M = {}

local char_patterns = {
  A = "^[%a]*$",
  AN = "^[%w]*$",
  N = "^[%d]*$",
  H = "^[%x]*$",
}

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function find_field(record, num)
  for _, f in ipairs(record.fields) do
    if f.num == num then
      return f
    end
  end
end

local function record_idc(record)
  if record.tagged then
    local f = find_field(record, 2)
    return f and f.subfields and tonumber(f.subfields[1][1])
  end
  return record.header.idc
end

local function check_character_type(value, ctype)
  local pat = char_patterns[ctype]
  if pat and not value:find(pat) then
    return { code = "FIELD_CHARACTER_TYPE_MISMATCH", detail = string.format('Value "%s" does not match character type %s', value, ctype) }
  end
end

local function with_ctx(err, ctx, extra)
  for k, v in pairs(ctx) do
    if err[k] == nil then
      err[k] = v
    end
  end
  for k, v in pairs(extra or {}) do
    err[k] = v
  end
  return err
end

local function structural(file, errors)
  if #file.records < 2 then
    errors[#errors + 1] = {
      code = "TOO_FEW_RECORDS",
      detail = "Transaction must contain at least a Type-1 record and one other record",
    }
  end
  local type1 = file.records[1]
  if not type1 or type1.type ~= 1 or not type1.tagged then
    errors[#errors + 1] = { code = "MISSING_TYPE1", detail = "Transaction must start with a Type-1 record" }
    return
  end
  local list = read.contents(type1)
  if not list then
    errors[#errors + 1] = { code = "CNT_MISMATCH", detail = "Field 1.003 (CNT) is missing", record_type = 1, field_number = 3 }
    return
  end
  -- CNT must list the records actually present, in order, with matching IDCs.
  local n = math.max(#list, #file.records - 1)
  for k = 1, n do
    local entry, record = list[k], file.records[k + 1]
    if not record then
      errors[#errors + 1] = {
        code = "CNT_MISMATCH",
        detail = string.format("Field 1.003 declares Type-%s IDC %s but no such record found", tostring(entry.type), tostring(entry.idc)),
        record_type = 1,
        field_number = 3,
      }
    elseif not entry then
      errors[#errors + 1] = {
        code = "CNT_MISMATCH",
        detail = string.format("Record %d (Type-%d) is not listed in field 1.003", k + 1, record.type),
        record_type = 1,
        field_number = 3,
      }
    elseif entry.type ~= record.type or tonumber(entry.idc) ~= record_idc(record) then
      errors[#errors + 1] = {
        code = "CNT_MISMATCH",
        detail = string.format(
          "Field 1.003 entry %d declares Type-%s IDC %s but record %d is Type-%d IDC %s",
          k, tostring(entry.type), tostring(entry.idc), k + 1, record.type, tostring(record_idc(record))
        ),
        record_type = 1,
        field_number = 3,
      }
    end
  end
end

local function validate_subfields(field, fp, ctx, errors)
  local sc = fp.subfields
  local subfields = field.subfields
  local id = field.tag
  if sc.min_subfields and #subfields < sc.min_subfields then
    errors[#errors + 1] = with_ctx({
      code = "TOO_FEW_SUBFIELDS",
      detail = string.format("Field %s has %d subfields, minimum is %d", id, #subfields, sc.min_subfields),
    }, ctx)
  end
  if sc.max_subfields and #subfields > sc.max_subfields then
    errors[#errors + 1] = with_ctx({
      code = "TOO_MANY_SUBFIELDS",
      detail = string.format("Field %s has %d subfields, maximum is %d", id, #subfields, sc.max_subfields),
    }, ctx)
  end
  if not sc.items then
    return
  end
  for si, sf in ipairs(subfields) do
    local ictx = { subfield_index = si }
    for ii, ic in ipairs(sc.items) do
      if ic then
        local item = sf[ii]
        local where = string.format("Field %s subfield %d item %d", id, si, ii)
        if item == nil then
          if ic.mandatory then
            errors[#errors + 1] = with_ctx({
              code = "MISSING_SUBFIELD_ITEM",
              detail = string.format("%s (%s) is mandatory but missing", where, ic.name or ""),
            }, ctx, ictx)
          end
        else
          if ic.min_length and #item < ic.min_length then
            errors[#errors + 1] = with_ctx({ code = "SUBFIELD_ITEM_TOO_SHORT", detail = where .. " too short" }, ctx, ictx)
          end
          if ic.max_length and #item > ic.max_length then
            errors[#errors + 1] = with_ctx({ code = "SUBFIELD_ITEM_TOO_LONG", detail = where .. " too long" }, ctx, ictx)
          end
          if ic.character_type then
            local err = check_character_type(item, ic.character_type)
            if err then
              errors[#errors + 1] = with_ctx(err, ctx, ictx)
            end
          end
          if ic.allowed_values and not contains(ic.allowed_values, item) then
            errors[#errors + 1] = with_ctx({ code = "SUBFIELD_ITEM_VALUE_NOT_ALLOWED", detail = where .. " invalid value" }, ctx, ictx)
          end
          if ic.pattern and not item:find(ic.pattern) then
            errors[#errors + 1] = with_ctx({ code = "SUBFIELD_ITEM_PATTERN_MISMATCH", detail = where .. " pattern mismatch" }, ctx, ictx)
          end
        end
      end
    end
  end
end

local function validate_fields(record, rp, record_index, version, errors)
  for _, fp in ipairs(rp.fields) do
    local tag = string.format("%d.%03d", record.type, fp.field)
    local field = find_field(record, fp.field)
    local ctx = {
      record_type = record.type,
      record_index = record_index,
      field_number = fp.field,
    }
    if not field then
      if fp.mandatory then
        errors[#errors + 1] = with_ctx({ code = "MISSING_FIELD", detail = string.format("Mandatory field %s is missing", tag) }, ctx)
      end
    else
      -- Binary data fields (.999) only get presence checks.
      local value = field.subfields and field.subfields[1] and field.subfields[1][1]
      if value then
        if fp.min_length and #value < fp.min_length then
          errors[#errors + 1] = with_ctx({
            code = "FIELD_TOO_SHORT",
            detail = string.format("Field %s has length %d, minimum is %d", tag, #value, fp.min_length),
          }, ctx)
        end
        if fp.max_length and #value > fp.max_length then
          errors[#errors + 1] = with_ctx({
            code = "FIELD_TOO_LONG",
            detail = string.format("Field %s has length %d, maximum is %d", tag, #value, fp.max_length),
          }, ctx)
        end
        if fp.allowed_values and not contains(fp.allowed_values, value) then
          errors[#errors + 1] = with_ctx({
            code = "FIELD_VALUE_NOT_ALLOWED",
            detail = string.format('Field %s value "%s" not in allowed set: %s', tag, value, table.concat(fp.allowed_values, ", ")),
          }, ctx)
        end
        if fp.pattern and not value:find(fp.pattern) then
          errors[#errors + 1] = with_ctx({
            code = "FIELD_PATTERN_MISMATCH",
            detail = string.format('Field %s value "%s" does not match pattern %s', tag, value, fp.pattern),
          }, ctx)
        end
        if fp.character_type then
          local err = check_character_type(value, fp.character_type)
          if err then
            errors[#errors + 1] = with_ctx(err, ctx)
          end
        end
        if fp.validator then
          local err = fp.validator(value, {
            record_type = record.type,
            record_index = record_index,
            field_number = fp.field,
            subfield_index = 1,
            transaction_version = version,
          })
          if err then
            errors[#errors + 1] = with_ctx(err, ctx)
          end
        end
      end
      if fp.subfields and field.subfields then
        validate_subfields(field, fp, ctx, errors)
      end
    end
  end
end

local function with_profile(file, profile, errors)
  local counts = {}
  for _, r in ipairs(file.records) do
    counts[r.type] = (counts[r.type] or 0) + 1
  end
  local types = {}
  for t in pairs(profile.records) do
    types[#types + 1] = t
  end
  table.sort(types)
  for _, t in ipairs(types) do
    local rp = profile.records[t]
    local count = counts[t] or 0
    if rp.min_occurs and count < rp.min_occurs then
      errors[#errors + 1] = {
        code = "TOO_FEW_RECORDS",
        detail = string.format("Expected at least %d Type-%d record(s), found %d", rp.min_occurs, t, count),
        record_type = t,
      }
    end
    if rp.max_occurs and count > rp.max_occurs then
      errors[#errors + 1] = {
        code = "TOO_MANY_RECORDS",
        detail = string.format("Expected at most %d Type-%d record(s), found %d", rp.max_occurs, t, count),
        record_type = t,
      }
    end
  end

  local type1 = file.records[1]
  local version = type1 and type1.tagged and find_field(type1, 2)
  version = version and version.subfields and version.subfields[1][1] or ""
  for i, record in ipairs(file.records) do
    local rp = profile.records[record.type]
    if rp and record.tagged then
      validate_fields(record, rp, i, version, errors)
    end
  end
end

-- Returns true, {} when valid, otherwise false and the list of errors.
function M.validate(file, profile)
  local errors = {}
  structural(file, errors)
  if profile then
    with_profile(file, profile, errors)
  end
  return #errors == 0, errors
end

return M
