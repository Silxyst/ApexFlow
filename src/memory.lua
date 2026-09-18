-- src/memory.lua
-- Minimal persistence helper for ApexFlow.
-- (Exists mainly so older builds that `require("src.memory")` won’t hard-fail.)

local M = {}

local function safeLog(msg)
  if ac and ac.log then ac.log(msg) end
end

-- If caller passes an existing memory table, return it (keeps references stable)
function M.getMemory(defaultTable)
  if type(defaultTable) == "table" then return defaultTable end
  return { tracks = {}, drivers = {} }
end

function M.load(path)
  local chunk, err = loadfile(path)
  if not chunk then
    safeLog(string.format("[ApexFlow] Memory load skipped: %s", tostring(err)))
    return nil
  end
  local ok, data = pcall(chunk)
  if ok and type(data) == "table" then
    return data
  end
  safeLog("[ApexFlow] Memory load failed (bad table).")
  return nil
end

-- Very small serializer; supports numbers/strings/bools/tables only
local function serializeTable(tbl, indent)
  indent = indent or ""
  local nextIndent = indent .. "  "
  local parts = {}
  parts[#parts + 1] = "{\n"

  for k, v in pairs(tbl) do
    local key
    if type(k) == "string" then
      key = string.format("%s[%q] = ", nextIndent, k)
    else
      key = string.format("%s[%d] = ", nextIndent, k)
    end

    local t = type(v)
    local valueStr
    if t == "number" or t == "boolean" then
      valueStr = tostring(v)
    elseif t == "string" then
      valueStr = string.format("%q", v)
    elseif t == "table" then
      valueStr = serializeTable(v, nextIndent)
    else
      valueStr = "nil"
    end

    parts[#parts + 1] = key .. valueStr .. ",\n"
  end

  parts[#parts + 1] = indent .. "}"
  return table.concat(parts)
end

function M.save(tbl, path)
  if type(tbl) ~= "table" then return end
  local f, err = io.open(path, "w")
  if not f then
    safeLog(string.format("[ApexFlow] Failed to save memory: %s", tostring(err)))
    return
  end
  f:write("return ")
  f:write(serializeTable(tbl, ""))
  f:write("\n")
  f:close()
  safeLog("[ApexFlow] Memory saved to " .. tostring(path))
end

return M
