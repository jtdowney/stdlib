local gleam = require("gleam")
local M = {}

-- Helpers -------------------------------------------------------------------

local function list_to_array(list)
  return gleam.listToArray(list)
end

local function array_to_list(arr)
  return gleam.toList(arr)
end

local function is_list(data)
  if type(data) ~= "table" then return false end
  local tag = rawget(data, "__gleam_tag")
  return tag == "Empty" or tag == "NonEmpty"
end

local function is_result(data)
  if type(data) ~= "table" then return false end
  local tag = rawget(data, "__gleam_tag")
  return tag == "Ok" or tag == "Error"
end

-- Identity ------------------------------------------------------------------

function M.identity(x)
  return x
end

-- Int parsing / formatting --------------------------------------------------

function M.parse_int(value)
  if type(value) == "string" and string.match(value, "^[%-%+]?%d+$") then
    local n = math.tointeger(tonumber(value))
    if n then return gleam.Ok(n) end
  end
  return gleam.Error(gleam.Nil)
end

function M.parse_float(value)
  if type(value) ~= "string" then
    return gleam.Error(gleam.Nil)
  end
  if string.match(value, "^[%-%+]?%d+%.%d+$")
    or string.match(value, "^[%-%+]?%d+%.%d+[eE][%-%+]?%d+$") then
    local n = tonumber(value)
    if n then return gleam.Ok(n * 1.0) end
  end
  return gleam.Error(gleam.Nil)
end

function M.to_string(term)
  return tostring(term)
end

function M.int_to_base_string(int, base)
  if base == 10 then return tostring(int) end

  local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local negative = int < 0
  if negative then int = -int end
  if int == 0 then return "0" end

  local result = {}
  while int > 0 do
    local d = (int % base) + 1
    result[#result + 1] = digits:sub(d, d)
    int = int // base
  end

  if negative then result[#result + 1] = "-" end

  -- reverse
  local i, j = 1, #result
  while i < j do
    result[i], result[j] = result[j], result[i]
    i = i + 1
    j = j - 1
  end
  return table.concat(result)
end

function M.int_from_base_string(str, base)
  local clean = str:gsub("^%-", ""):lower()
  if clean == "" then return gleam.Error(gleam.Nil) end

  local valid_chars = "0123456789abcdefghijklmnopqrstuvwxyz"
  local max_char = valid_chars:sub(base, base)

  for i = 1, #clean do
    local c = clean:sub(i, i)
    local pos = valid_chars:find(c, 1, true)
    if not pos or pos > base then
      return gleam.Error(gleam.Nil)
    end
  end

  local n = tonumber(str, base)
  if not n then return gleam.Error(gleam.Nil) end
  return gleam.Ok(math.tointeger(n))
end

-- Float formatting ----------------------------------------------------------

function M.float_to_string(float)
  local s = string.format("%.17g", float)
  -- Remove explicit '+' from exponent
  s = s:gsub("%+", "")
  if not s:find("%.") and not s:find("e") then
    s = s .. ".0"
  elseif s:find("e") and not s:find("%.") then
    local idx = s:find("e")
    s = s:sub(1, idx - 1) .. ".0" .. s:sub(idx)
  end
  return s
end

-- String operations ---------------------------------------------------------

-- UTF-8 grapheme helpers.
-- Lua 5.4 has a built-in utf8 library for codepoints, but grapheme cluster
-- segmentation is complex (requires Unicode tables). We approximate by treating
-- each codepoint as a grapheme, which is correct for most text but not for
-- combining characters or emoji sequences.

local function utf8_next_codepoint_size(s, i)
  local b = string.byte(s, i)
  if not b then return nil end
  if b < 0x80 then return 1
  elseif b < 0xE0 then return 2
  elseif b < 0xF0 then return 3
  else return 4
  end
end

function M.string_length(str)
  if str == "" then return 0 end
  local len = 0
  for _ in utf8.codes(str) do
    len = len + 1
  end
  return len
end

function M.graphemes(str)
  if str == "" then return gleam.Empty end
  local result = {}
  for _, code in utf8.codes(str) do
    result[#result + 1] = utf8.char(code)
  end
  return array_to_list(result)
end

function M.pop_grapheme(str)
  if str == "" then return gleam.Error(gleam.Nil) end
  local i = 1
  local size = utf8_next_codepoint_size(str, i)
  if not size then return gleam.Error(gleam.Nil) end
  local first = str:sub(1, size)
  local rest = str:sub(size + 1)
  return gleam.Ok({ first, rest })
end

function M.pop_codeunit(str)
  local byte = string.byte(str, 1) or 0
  return { byte, str:sub(2) }
end

function M.string_grapheme_slice(str, idx, len)
  if len <= 0 then return "" end
  local result = {}
  local pos = 0
  for _, code in utf8.codes(str) do
    if pos >= idx and pos < idx + len then
      result[#result + 1] = utf8.char(code)
    end
    pos = pos + 1
    if pos >= idx + len then break end
  end
  return table.concat(result)
end

function M.string_byte_slice(str, index, length)
  return str:sub(index + 1, index + length)
end

function M.string_codeunit_slice(str, from, length)
  return str:sub(from + 1, from + length)
end

function M.lowercase(str)
  -- NOTE: ASCII-only lowercase; full Unicode lowercasing would require ICU
  return str:lower()
end

function M.uppercase(str)
  -- NOTE: ASCII-only uppercase; full Unicode uppercasing would require ICU
  return str:upper()
end

function M.less_than(a, b)
  return a < b
end

-- String replace, crop, contains, starts_with, ends_with -------------------

function M.string_replace(str, target, substitute)
  -- Replace all occurrences (plain string, not pattern)
  local result = {}
  local tlen = #target
  if tlen == 0 then
    -- Empty target: insert substitute between each character and at edges
    for i = 1, #str do
      result[#result + 1] = substitute
      result[#result + 1] = str:sub(i, i)
    end
    result[#result + 1] = substitute
    return table.concat(result)
  end
  local i = 1
  while true do
    local j = str:find(target, i, true)
    if not j then
      result[#result + 1] = str:sub(i)
      break
    end
    result[#result + 1] = str:sub(i, j - 1)
    result[#result + 1] = substitute
    i = j + tlen
  end
  return table.concat(result)
end

function M.crop_string(str, substring)
  local idx = str:find(substring, 1, true)
  if idx then
    return str:sub(idx)
  end
  return str
end

function M.contains_string(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

function M.starts_with(haystack, needle)
  return haystack:sub(1, #needle) == needle
end

function M.ends_with(haystack, needle)
  if #needle == 0 then return true end
  return haystack:sub(-#needle) == needle
end

-- Split / Join / Concat -----------------------------------------------------

function M.split(str, pattern)
  if pattern == "" then
    return M.graphemes(str)
  end
  local parts = {}
  local plen = #pattern
  local i = 1
  while true do
    local j = str:find(pattern, i, true)
    if not j then
      parts[#parts + 1] = str:sub(i)
      break
    end
    parts[#parts + 1] = str:sub(i, j - 1)
    i = j + plen
  end
  return array_to_list(parts)
end

function M.split_once(haystack, needle)
  local idx = haystack:find(needle, 1, true)
  if idx then
    local before = haystack:sub(1, idx - 1)
    local after = haystack:sub(idx + #needle)
    return gleam.Ok({ before, after })
  end
  return gleam.Error(gleam.Nil)
end

function M.concat(xs)
  local parts = {}
  local current = xs
  while type(current) == "table" and rawget(current, "__gleam_tag") == "NonEmpty" do
    parts[#parts + 1] = current.head
    current = current.tail
  end
  return table.concat(parts)
end

function M.add(a, b)
  return a .. b
end

function M.length(data)
  return #data
end

-- Trim ----------------------------------------------------------------------

local whitespace_pattern = "[ \t\n\v\f\r\xC2\x85\xE2\x80\xA8\xE2\x80\xA9]"

function M.trim_start(str)
  -- Trim leading whitespace (common ASCII whitespace + Unicode whitespace)
  local result = str:gsub("^%s+", "")
  return result
end

function M.trim_end(str)
  local result = str:gsub("%s+$", "")
  return result
end

-- IO ------------------------------------------------------------------------

function M.print(str)
  io.write(str)
  io.flush()
  return gleam.Nil
end

function M.print_error(str)
  io.stderr:write(str)
  io.stderr:flush()
  return gleam.Nil
end

function M.console_log(str)
  print(str)
  return gleam.Nil
end

function M.console_error(str)
  io.stderr:write(str .. "\n")
  io.stderr:flush()
  return gleam.Nil
end

-- Math (Float) --------------------------------------------------------------

function M.ceiling(float)
  return math.ceil(float) * 1.0
end

function M.floor(float)
  return math.floor(float) * 1.0
end

function M.round(float)
  -- Lua 5.4 math.floor returns integer; we want banker-style rounding
  -- matching JS Math.round: rounds half towards +Infinity
  return math.floor(float + 0.5)
end

function M.truncate(float)
  if float >= 0 then
    return math.floor(float)
  else
    return math.ceil(float)
  end
end

function M.power(base, exponent)
  return base ^ exponent
end

function M.random_uniform()
  return math.random()
end

function M.log(x)
  return math.log(x)
end

function M.exp(x)
  return math.exp(x)
end

-- Crash ---------------------------------------------------------------------

function M.crash(message)
  error(message)
end

-- BitArray operations -------------------------------------------------------

function M.bit_array_from_string(str)
  return gleam.BitArray.new(str)
end

function M.bit_array_bit_size(bit_array)
  return bit_array.bit_size
end

function M.bit_array_byte_size(bit_array)
  return math.ceil(bit_array.bit_size / 8)
end

function M.bit_array_pad_to_bytes(bit_array)
  local trailing = bit_array.bit_size % 8
  if trailing == 0 then return bit_array end
  -- Pad: zero out unused trailing bits in last byte
  local buf = bit_array.buffer
  local last = string.byte(buf, #buf)
  local unused = 8 - trailing
  local corrected = ((last >> unused) << unused)
  if last == corrected then
    -- Re-use buffer, just update bit_size
    local new = gleam.BitArray.new(buf)
    new.bit_size = #buf * 8
    return new
  end
  local new_buf = buf:sub(1, #buf - 1) .. string.char(corrected)
  local new = gleam.BitArray.new(new_buf)
  new.bit_size = #new_buf * 8
  return new
end

function M.bit_array_concat(bit_arrays)
  local parts = list_to_array(bit_arrays)
  local bufs = {}
  for _, ba in ipairs(parts) do
    bufs[#bufs + 1] = ba.buffer
  end
  return gleam.BitArray.new(table.concat(bufs))
end

function M.bit_array_slice(bits, position, length)
  local start = math.min(position, position + length)
  local stop = math.max(position, position + length)

  if start < 0 or stop * 8 > bits.bit_size then
    return gleam.Error(gleam.Nil)
  end

  local buf = bits.buffer:sub(start + 1, stop)
  return gleam.Ok(gleam.BitArray.new(buf))
end

function M.bit_array_to_string(bit_array)
  if bit_array.bit_size % 8 ~= 0 then
    return gleam.Error(gleam.Nil)
  end
  local str = bit_array.buffer
  -- Validate UTF-8
  local ok, _ = pcall(utf8.len, str)
  if ok and utf8.len(str) then
    return gleam.Ok(str)
  end
  return gleam.Error(gleam.Nil)
end

function M.bit_array_to_int_and_size(bits)
  local trailing = bits.bit_size % 8
  local unused = (trailing == 0) and 0 or (8 - trailing)
  local first_byte = string.byte(bits.buffer, 1) or 0
  return { first_byte >> unused, bits.bit_size }
end

function M.bit_array_starts_with(bits, prefix)
  if prefix.bit_size > bits.bit_size then return false end
  local byte_count = prefix.bit_size // 8
  for i = 1, byte_count do
    if string.byte(bits.buffer, i) ~= string.byte(prefix.buffer, i) then
      return false
    end
  end
  if prefix.bit_size % 8 ~= 0 then
    local unused = 8 - (prefix.bit_size % 8)
    local a = string.byte(bits.buffer, byte_count + 1) >> unused
    local b = string.byte(prefix.buffer, byte_count + 1) >> unused
    if a ~= b then return false end
  end
  return true
end

-- Codepoints ----------------------------------------------------------------

function M.codepoint(int)
  return gleam.utfCodepoint(int)
end

function M.string_to_codepoint_integer_list(str)
  local result = {}
  for _, code in utf8.codes(str) do
    result[#result + 1] = code
  end
  return array_to_list(result)
end

function M.utf_codepoint_list_to_string(codepoint_list)
  local arr = list_to_array(codepoint_list)
  local chars = {}
  for _, cp in ipairs(arr) do
    chars[#chars + 1] = utf8.char(cp.value)
  end
  return table.concat(chars)
end

function M.utf_codepoint_to_int(codepoint)
  return codepoint.value
end

-- Byte size -----------------------------------------------------------------

function M.byte_size(str)
  return #str
end

-- Bitwise operations --------------------------------------------------------
-- Lua 5.4 has native bitwise operators

function M.bitwise_and(x, y)
  return x & y
end

function M.bitwise_or(x, y)
  return x | y
end

function M.bitwise_exclusive_or(x, y)
  return x ~ y
end

function M.bitwise_not(x)
  return ~x
end

function M.bitwise_shift_left(x, y)
  return x << y
end

function M.bitwise_shift_right(x, y)
  return x >> y
end

-- Inspect -------------------------------------------------------------------
-- Delegate to the prelude's inspect and wrap as StringTree (which is just a
-- string on the Lua target)

function M.inspect(v)
  return gleam.inspect(v)
end

-- Base64 encode/decode ------------------------------------------------------

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local b64lookup = {}
for i = 1, 64 do
  b64lookup[b64chars:sub(i, i)] = i - 1
end

function M.base64_encode(bit_array, padding)
  bit_array = M.bit_array_pad_to_bytes(bit_array)
  local bytes = bit_array.buffer
  local result = {}
  local m = #bytes

  for i = 1, m, 3 do
    local b1 = string.byte(bytes, i)
    local b2 = string.byte(bytes, i + 1) or 0
    local b3 = string.byte(bytes, i + 2) or 0

    local n = (b1 << 16) + (b2 << 8) + b3

    result[#result + 1] = b64chars:sub((n >> 18) + 1, (n >> 18) + 1)
    result[#result + 1] = b64chars:sub(((n >> 12) & 0x3F) + 1, ((n >> 12) & 0x3F) + 1)

    if i + 1 <= m then
      result[#result + 1] = b64chars:sub(((n >> 6) & 0x3F) + 1, ((n >> 6) & 0x3F) + 1)
    end
    if i + 2 <= m then
      result[#result + 1] = b64chars:sub((n & 0x3F) + 1, (n & 0x3F) + 1)
    end
  end

  if padding then
    local rem = m % 3
    if rem == 1 then
      result[#result + 1] = "=="
    elseif rem == 2 then
      result[#result + 1] = "="
    end
  end

  return table.concat(result)
end

function M.base64_decode(str)
  -- Remove padding
  str = str:gsub("=", "")

  local ok, result = pcall(function()
    local bytes = {}
    local acc = 0
    local bits = 0

    for i = 1, #str do
      local c = str:sub(i, i)
      local val = b64lookup[c]
      if not val then error("invalid base64") end
      acc = (acc << 6) | val
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        bytes[#bytes + 1] = string.char((acc >> bits) & 0xFF)
      end
    end
    return table.concat(bytes)
  end)

  if ok then
    return gleam.Ok(gleam.BitArray.new(result))
  else
    return gleam.Error(gleam.Nil)
  end
end

-- Base16 encode/decode ------------------------------------------------------

function M.base16_encode(bit_array)
  local trailing = bit_array.bit_size % 8
  local bytes = bit_array.buffer
  local result = {}

  for i = 1, #bytes do
    local byte = string.byte(bytes, i)
    if i == #bytes and trailing ~= 0 then
      local unused = 8 - trailing
      byte = ((byte >> unused) << unused)
    end
    result[#result + 1] = string.format("%02X", byte)
  end

  return table.concat(result)
end

function M.base16_decode(str)
  if #str % 2 ~= 0 then
    return gleam.Error(gleam.Nil)
  end

  local bytes = {}
  for i = 1, #str, 2 do
    local hex = str:sub(i, i + 1)
    local n = tonumber(hex, 16)
    if not n then return gleam.Error(gleam.Nil) end
    bytes[#bytes + 1] = string.char(n)
  end

  return gleam.Ok(gleam.BitArray.new(table.concat(bytes)))
end

-- Percent encoding/decoding (URI) -------------------------------------------

local function is_unreserved(byte)
  return (byte >= 0x41 and byte <= 0x5A)  -- A-Z
      or (byte >= 0x61 and byte <= 0x7A)  -- a-z
      or (byte >= 0x30 and byte <= 0x39)  -- 0-9
      or byte == 0x2D  -- -
      or byte == 0x2E  -- .
      or byte == 0x5F  -- _
      or byte == 0x7E  -- ~
end

function M.percent_encode(str)
  local result = {}
  for i = 1, #str do
    local byte = string.byte(str, i)
    if is_unreserved(byte) then
      result[#result + 1] = string.char(byte)
    elseif byte == 0x2B then  -- + is passed through per JS encodeURIComponent behavior
      result[#result + 1] = "+"
    else
      result[#result + 1] = string.format("%%%02X", byte)
    end
  end
  return table.concat(result)
end

function M.percent_decode(str)
  local ok, result = pcall(function()
    local decoded = str:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
    return decoded
  end)
  if ok then
    return gleam.Ok(result)
  else
    return gleam.Error(gleam.Nil)
  end
end

-- Parse query ---------------------------------------------------------------

function M.parse_query(query)
  local ok, result = pcall(function()
    local pairs = {}
    for section in query:gmatch("[^&]+") do
      local eq_idx = section:find("=", 1, true)
      local key, value
      if eq_idx then
        key = section:sub(1, eq_idx - 1)
        value = section:sub(eq_idx + 1)
      else
        key = section
        value = ""
      end
      if key == "" then goto continue end

      -- Decode percent-encoded and + as space
      local function decode_query_component(s)
        s = s:gsub("+", " ")
        s = s:gsub("%%(%x%x)", function(hex)
          return string.char(tonumber(hex, 16))
        end)
        return s
      end

      pairs[#pairs + 1] = { decode_query_component(key), decode_query_component(value) }
      ::continue::
    end
    return pairs
  end)

  if ok then
    return gleam.Ok(array_to_list(result))
  else
    return gleam.Error(gleam.Nil)
  end
end

-- Dynamic / classify --------------------------------------------------------

function M.classify_dynamic(data)
  if type(data) == "string" then
    return "String"
  elseif type(data) == "boolean" then
    return "Bool"
  elseif is_result(data) then
    return "Result"
  elseif is_list(data) then
    return "List"
  elseif type(data) == "table" and getmetatable(data) == gleam.BitArray then
    return "BitArray"
  elseif type(data) == "number" then
    if math.type(data) == "integer" then
      return "Int"
    else
      return "Float"
    end
  elseif rawequal(data, gleam.Nil) then
    return "Nil"
  elseif data == nil then
    return "Nil"
  elseif type(data) == "table" then
    return "Dict"
  elseif type(data) == "function" then
    return "Function"
  else
    local t = type(data)
    return t:sub(1, 1):upper() .. t:sub(2)
  end
end

function M.list_to_array(list)
  return gleam.listToArray(list)
end

-- Decode helpers (for dynamic/decode module) --------------------------------

function M.index(data, key)
  -- Import Some/None constructors
  local function make_some(v)
    return { __gleam_tag = "Some", 0, v }
  end
  local function make_none()
    return { __gleam_tag = "None" }
  end

  -- Dict-like tables
  if type(data) == "table" then
    local tag = rawget(data, "__gleam_tag")

    -- Gleam dict (we check for __gleam_dict marker or just use raw table indexing)
    if type(key) == "number" and math.type(key) == "integer" then
      -- Integer key: index into lists (elements 0-7) and tuple-like tables
      if is_list(data) and key >= 0 and key < 8 then
        local i = 0
        local current = data
        while type(current) == "table" and rawget(current, "__gleam_tag") == "NonEmpty" do
          if i == key then return gleam.Ok(make_some(current.head)) end
          i = i + 1
          current = current.tail
        end
        return gleam.Error("Indexable")
      end
      -- Tuple-like (integer-indexed table)
      if not tag and data[key + 1] ~= nil then
        return gleam.Ok(make_some(data[key + 1]))
      end
    end

    -- String key on a regular table (like a JS object / Gleam dict)
    if not tag or tag == nil then
      if data[key] ~= nil then
        return gleam.Ok(make_some(data[key]))
      else
        return gleam.Ok(make_none())
      end
    end

    -- Custom type fields
    if tag then
      if data[key] ~= nil then
        return gleam.Ok(make_some(data[key]))
      end
      return gleam.Ok(make_none())
    end
  end

  if type(key) == "number" and math.type(key) == "integer" then
    return gleam.Error("Indexable")
  end
  return gleam.Error("Dict")
end

function M.list(data, decode, pushPath, idx, emptyList)
  if not is_list(data) then
    local error_val = { __gleam_tag = "DecodeError", 0, "List", M.classify_dynamic(data), emptyList }
    return { emptyList, gleam.toList({ error_val }) }
  end

  local decoded = {}
  local current = data
  while type(current) == "table" and rawget(current, "__gleam_tag") == "NonEmpty" do
    local layer = { decode(current.head) }
    local out = layer[1]
    local errors = layer[2]
    -- Check for actual result tuple
    if type(out) == "table" and #out == 2 then
      errors = out[2]
      out = out[1]
    end

    -- Check if there are errors
    if type(errors) == "table" and rawget(errors, "__gleam_tag") == "NonEmpty" then
      local pushed = { pushPath({ out, errors }, tostring(idx)) }
      return { emptyList, pushed[2] or (type(pushed[1]) == "table" and pushed[1][2]) or errors }
    end
    decoded[#decoded + 1] = out
    idx = idx + 1
    current = current.tail
  end

  return { array_to_list(decoded), emptyList }
end

function M.dict(data)
  if type(data) ~= "table" then
    return gleam.Error("Dict")
  end
  if data == nil then
    return gleam.Error("Dict")
  end
  -- Already a dict-like table: return as-is for now
  -- TODO: proper Dict wrapper
  return gleam.Ok(data)
end

function M.bit_array(data)
  if type(data) == "table" and getmetatable(data) == gleam.BitArray then
    return gleam.Ok(data)
  end
  return gleam.Error(gleam.BitArray.new(""))
end

function M.float(data)
  if type(data) == "number" then
    return gleam.Ok(data * 1.0)
  end
  return gleam.Error(0.0)
end

function M.int(data)
  if type(data) == "number" and math.type(data) == "integer" then
    return gleam.Ok(data)
  end
  return gleam.Error(0)
end

function M.string(data)
  if type(data) == "string" then
    return gleam.Ok(data)
  end
  return gleam.Error("")
end

function M.is_null(data)
  return data == nil or rawequal(data, gleam.Nil)
end

return M
