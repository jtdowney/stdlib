local gleam = require("gleam")

local M = {}

-- TODO: This is a simple O(n) implementation using a flat list of key-value
-- pairs with structural equality comparison. It is correct but slow.
-- Replace with a proper HAMT/CHAMP implementation for production use.

-- Dict structure:
--   { __gleam_tag = "Dict", _entries = { {key, value}, {key, value}, ... } }
--
-- We store entries as an array of {key, value} pairs. Key lookup uses
-- structural equality via gleam.isEqual(). Mutations return a new dict
-- (copy-on-write) so the data structure appears immutable from the outside.

local function find_index(entries, key)
  for i = 1, #entries do
    if gleam.isEqual(entries[i][1], key) then
      return i
    end
  end
  return nil
end

local function copy_entries(entries)
  local new = {}
  for i = 1, #entries do
    new[i] = entries[i]
  end
  return new
end

local function make_dict(entries)
  return { __gleam_tag = "Dict", _entries = entries }
end

-- Create an empty dict
function M.make()
  return make_dict({})
end

-- Return the number of entries
function M.size(dict)
  return #dict._entries
end

-- Convert dict to a Gleam list of #(key, value) tuples
function M.to_list(dict)
  local entries = dict._entries
  local result = gleam.Empty
  for i = #entries, 1, -1 do
    local entry = entries[i]
    result = gleam.prepend({ entry[1], entry[2] }, result)
  end
  return result
end

-- Check if a key exists
function M.has(dict, key)
  return find_index(dict._entries, key) ~= nil
end

-- Fetch a value, returning Ok(value) or Error(Nil)
function M.get(dict, key)
  local idx = find_index(dict._entries, key)
  if idx then
    return gleam.Ok(dict._entries[idx][2])
  end
  return gleam.Error(gleam.Nil)
end

-- Insert a key-value pair, returning a new dict
function M.insert(dict, key, value)
  local entries = dict._entries
  local idx = find_index(entries, key)
  local new_entries = copy_entries(entries)
  if idx then
    new_entries[idx] = { key, value }
  else
    new_entries[#new_entries + 1] = { key, value }
  end
  return make_dict(new_entries)
end

-- Transient operations: for Lua we use the same copy-on-write approach.
-- The "transient" is just a mutable wrapper around entries that we mutate
-- in place, then freeze when converting back to a dict.

function M.toTransient(dict)
  return { _entries = copy_entries(dict._entries), _dict = dict }
end

function M.fromTransient(transient)
  return make_dict(transient._entries)
end

function M.destructiveTransientInsert(key, value, transient)
  local entries = transient._entries
  local idx = find_index(entries, key)
  if idx then
    entries[idx] = { key, value }
  else
    entries[#entries + 1] = { key, value }
  end
  return transient
end

function M.destructiveTransientDelete(key, transient)
  local entries = transient._entries
  local idx = find_index(entries, key)
  if idx then
    local last = #entries
    entries[idx] = entries[last]
    entries[last] = nil
  end
  return transient
end

function M.destructiveTransientUpdateWith(key, fun, value, transient)
  local entries = transient._entries
  local idx = find_index(entries, key)
  if idx then
    entries[idx] = { key, fun(entries[idx][2]) }
  else
    entries[#entries + 1] = { key, value }
  end
  return transient
end

-- Map over values, returning a new dict
function M.map(dict, fun)
  local entries = dict._entries
  local new_entries = {}
  for i = 1, #entries do
    local entry = entries[i]
    new_entries[i] = { entry[1], fun(entry[1], entry[2]) }
  end
  return make_dict(new_entries)
end

-- Fold over all entries
function M.fold(dict, state, fun)
  local entries = dict._entries
  for i = 1, #entries do
    local entry = entries[i]
    state = fun(state, entry[1], entry[2])
  end
  return state
end

return M
