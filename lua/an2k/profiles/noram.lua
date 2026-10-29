-- NORAM application profile for an2k.validate().

return {
  name = "NORAM",
  version = "1.0.0",
  description = "North American Domain baseline profile (FBI CJIS EBTS subset)",
  records = {
    [1] = {
      min_occurs = 1,
      max_occurs = 1,
      fields = {
        { field = 1, mandatory = true },
        { field = 2, mandatory = true, min_length = 3, max_length = 4, character_type = "N" },
        {
          field = 3,
          mandatory = true,
          subfields = {
            max_subfields = 99,
            items = {
              false,
              false,
            },
          },
        },
        { field = 4, mandatory = true, min_length = 3, max_length = 16, character_type = "AN" },
        { field = 5, mandatory = true, min_length = 8, max_length = 8, character_type = "N" },
        { field = 6, mandatory = false, min_length = 1, max_length = 1, pattern = "^[1-9]$" },
        { field = 7, mandatory = true, max_length = 35 },
        { field = 8, mandatory = true, max_length = 35 },
        { field = 9, mandatory = true, max_length = 48 },
        { field = 10, mandatory = false, max_length = 48 },
        { field = 11, mandatory = false, max_length = 5, pattern = "^%d%d%.%d%d$" },
        { field = 12, mandatory = false, max_length = 5, pattern = "^%d%d%.%d%d$" },
        { field = 13, mandatory = false, max_length = 125 },
        { field = 14, mandatory = false, min_length = 15, max_length = 15 },
      },
    },
    [2] = {
      min_occurs = 0,
      max_occurs = 1,
      fields = {
        { field = 1, mandatory = true },
        { field = 2, mandatory = true, character_type = "N" },
      },
    },
    [4] = { min_occurs = 0, max_occurs = 14, fields = {  } },
    [10] = {
      min_occurs = 0,
      max_occurs = 99,
      fields = {
        { field = 1, mandatory = true },
        { field = 2, mandatory = true, character_type = "N" },
        { field = 3, mandatory = true },
        { field = 4, mandatory = true },
        { field = 5, mandatory = true, min_length = 8, max_length = 8, character_type = "N" },
        { field = 6, mandatory = true, character_type = "N" },
        { field = 7, mandatory = true, character_type = "N" },
        { field = 8, mandatory = true, character_type = "N" },
        { field = 9, mandatory = true, character_type = "N" },
        { field = 10, mandatory = true, character_type = "N" },
        { field = 11, mandatory = true },
        { field = 12, mandatory = true },
        { field = 13, mandatory = false },
        { field = 20, mandatory = false },
        { field = 999, mandatory = false },
      },
    },
    [14] = {
      min_occurs = 0,
      max_occurs = 14,
      fields = {
        { field = 1, mandatory = true },
        { field = 2, mandatory = true, character_type = "N" },
        { field = 4, mandatory = true },
        { field = 5, mandatory = true, min_length = 8, max_length = 8, character_type = "N" },
        { field = 13, mandatory = true },
        { field = 999, mandatory = false },
      },
    },
  },
}
