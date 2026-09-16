-- RaceFlow AI Controller
-- Aggression classes + Pace Pack + Racecraft + Engine safety + Blue flags
-- + Physics-forward shaping (turn-phase brake/throttle + top speed shaping + basic grip budget)

local M = {}

-- ==========================================================
-- Learning Implementation Probe (UI-facing telemetry)
-- ==========================================================
M._implProbe = M._implProbe or {}


-- ==========================================================
-- Event/Accident Probe (UI + CSP log)
--   _eventProbe[index] = last hard-event snapshot for that AI
--   _eventLog          = ring buffer of recent hard-events
-- ==========================================================
M._eventProbe = M._eventProbe or {}
M._eventLog   = M._eventLog   or {}

local drivers = {}
local lastSessionIndex = -1
local lastCarsCount    = -1
local lastAggression   = -1

local memory = nil
local memoryDirty = false

-- -------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------
local function markMemoryDirty()
  memoryDirty = true
  -- also tell RaceFlow (global) so it can save to disk
  if _G.RARE2_API then
    RARE2_API._memoryDirty = true
  end
end

local function getMemory()
  if not memory and _G.RARE2_API and RARE2_API.getMemory then
    memory = RARE2_API.getMemory()
  end
  return memory
end

local function getTrackId(sim)
  if ac.getTrackID then
    local ok, id = pcall(ac.getTrackID)
    if ok and id and id ~= "" then
      return id
    end
  end
  return sim and sim.trackName or "unknown"
end

local function clamp

-- RARE2_API guard
_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API
(v, minV, maxV)
  if v < minV then return minV end
  if v > maxV then return maxV end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- ==========================================================
-- Danger Zone: driven entirely from RaceFlow memory.
-- Reads spline_N keys from the current track's turn data.
-- Each bucket with danger > dangerZoneThreshold contributes a
-- bell-shaped influence around its lap position.
-- Returns 0..1 — the peak danger influence at the car's current sp.
--
-- cfg.dangerZoneThreshold  = minimum danger to count (default 3.0)
-- cfg.dangerZoneCap        = danger value that maps to strength 1.0 (default 12)
-- cfg.dangerZoneHalfWidth  = influence radius in spline fraction (default 1.5 buckets)
-- ==========================================================
local function getDangerZoneStrength(car, cfg, sim)
  if not car then return 0 end

  local sp = tonumber(car.splinePosition) or 0

  local mem = getMemory()
  if not mem then return 0 end

  local trackId = getTrackId(sim)
  local tdata = mem.tracks and mem.tracks[trackId]
  if not tdata then return 0 end

  local turns = tdata.turns
  if not turns then return 0 end

  local bucketCount = tonumber(tdata.bucketCount) or 60
  local threshold   = tonumber(cfg.dangerZoneThreshold or 3.0) or 3.0
  local cap         = tonumber(cfg.dangerZoneCap or 12.0) or 12.0
  local halfWidth   = tonumber(cfg.dangerZoneHalfWidth or (1.5 / bucketCount)) or (1.5 / bucketCount)

  local best = 0.0

  for key, node in pairs(turns) do
    -- Only consider frozen=false nodes with real danger
    local frozen = (node.dangerFrozen == true) or (node.locked == true)
    local danger = (not frozen) and (tonumber(node.danger or 0) or 0) or 0.0
    if danger >= threshold then
      -- Parse bucket index from key "spline_N"
      local n = tonumber(key:match("spline_(%d+)"))
      if n then
        local bucketSP = n / bucketCount  -- 0..1 lap position of this bucket

        -- Shortest circular distance between sp and bucketSP
        local d = math.abs(sp - bucketSP)
        if d > 0.5 then d = 1.0 - d end  -- wrap

        if d <= halfWidth then
          -- Bell curve: 1 at center, 0 at halfWidth
          local t = 1.0 - (d / halfWidth)
          local influence = t * t  -- smooth falloff
          -- Scale by danger magnitude (clamped to 0..1)
          local dangerNorm = clamp(danger / cap, 0.0, 1.0)
          local contribution = influence * dangerNorm
          if contribution > best then best = contribution end
        end
      end
    end
  end

  return clamp(best, 0.0, 1.0)
end

local function applyBrakeHintMul(curr, mul, cfg)
  -- If invertBrakeHint=true, "more braking" is achieved by HIGHER values
  if cfg and cfg.invertBrakeHint then
    return curr * mul
  end

  -- Default: "more braking" is achieved by LOWER values
  return curr / mul
end

local function safeNumber(getter, default)
  local ok, v = pcall(getter)
  if ok then
    v = tonumber(v)
    if v ~= nil then return v end
  end
  return default
end

local function safeBool(getter, default)
  local ok, v = pcall(getter)
  if ok then
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
  end
  return default
end

-- Best-effort off-track detection across CSP/AC API variants.
-- Returns true/false; if no signal exists, returns false (no learning penalty).
local function isOffTrack(car)
  if not car then return false end

  -- Common CSP flag
  local onTrack = safeBool(function() return car.isOnTrack end, nil)
  if onTrack ~= nil then
    return not onTrack
  end

  -- Alternate naming
  local offTrack = safeBool(function() return car.isOffTrack end, nil)
  if offTrack ~= nil then
    return offTrack
  end

  -- Some builds expose surface grip / surface type per car
  local surf = safeNumber(function() return car.surfaceType end, nil)
  if surf ~= nil then
    -- Heuristic: 0=asphalt in many mods, but not universal. Treat unknown as on-track.
    return false
  end

  return false
end

-- ===== ui_car.json session scan (Option 2) =====
local CAR_SCAN_CONFIG_PATH = "apps/lua/RaceFlow/data/car_scan_config.json"
local carScanConfig = nil
local sessionCarDB = nil

local function loadCarScanConfig()
  if carScanConfig then return end  -- load once

  local f = io.open(CAR_SCAN_CONFIG_PATH, "r")
  if f then
    local text = f:read("*a") or ""
    f:close()

    -- Strip UTF-8 BOM if present
    text = text:gsub("^\239\187\191", "")

    -- Try to decode JSON
    local obj = nil
    if ac and ac.decodeJson then
      local okJ, out = pcall(ac.decodeJson, text)
      if okJ and type(out) == "table" then obj = out end
    end

    if obj then
      if obj.acCarsFolder then
        obj.acCarsFolder = tostring(obj.acCarsFolder):gsub("\\", "/")
      end
      carScanConfig = obj
      return
    end
  end

  -- fallback defaults
  carScanConfig = {
    acCarsFolder = "C:/Program Files (x86)/Steam/steamapps/common/assettocorsa/content/cars",
    metric = "p2w",
    kwToHpThreshold = 200,
    defaultClassCount = 2,
    minCarsWithMetric = 4,
    minCarsPerClass = 4,
    gapSplit = true,
    gapSplitMinPercent = 0.06
  }
end

local function extractNumber(x)
  if x == nil then return nil end
  if type(x) == "number" then return x end
  if type(x) == "string" then
    local s = x:gsub(",", "") -- handle "1,310" etc
    local n = s:match("([%d%.]+)")
    if n then return tonumber(n) end
  end
  return nil
end

local function normalizePowerToHP(p)
  if not p then return nil end
  local threshold = (carScanConfig and carScanConfig.kwToHpThreshold) or 200
  if p < threshold then
    return p * 1.34102209
  end
  return p
end

local function loadCarUIData(carId)

  -- Prefer CSP-provided content folder if available:
  local base = carScanConfig.acCarsFolder
  if (not base or base == "" or base == "AUTO") and ac.getFolder and ac.FolderID then
    local ok, contentDir = pcall(ac.getFolder, ac.FolderID.Content)
    if ok and contentDir and contentDir ~= "" then
      base = (tostring(contentDir):gsub("\\", "/")) .. "/cars"
    end
  end

  if not base or base == "" then
    return nil, "Missing cars folder path (set acCarsFolder or use AUTO)"
  end

  base = tostring(base):gsub("\\", "/")
  local path = string.format("%s/%s/ui/ui_car.json", base, carId)

  -- ---------- Load + parse ----------
  local ok, data = pcall(io.load, path)

  -- Some CSP builds return a string (raw JSON) for io.load on .json files
  if ok and type(data) == "string" then
    if ac and ac.decodeJson then
      local okJ, obj = pcall(ac.decodeJson, data)
      if okJ and type(obj) == "table" then data = obj end
    elseif JSON and JSON.parse then
      local okJ, obj = pcall(JSON.parse, data)
      if okJ and type(obj) == "table" then data = obj end
    elseif json and json.decode then
      local okJ, obj = pcall(json.decode, data)
      if okJ and type(obj) == "table" then data = obj end
    end
  end

  -- Some CSP builds can’t parse JSON with io.load at all, so try reading text
  if type(data) ~= "table" then
    if io.loadText then
      local okT, txt = pcall(io.loadText, path)
      if okT and type(txt) == "string" then
        local obj = nil
        if ac and ac.decodeJson then
          local okJ, o = pcall(ac.decodeJson, txt)
          if okJ and type(o) == "table" then obj = o end
        elseif JSON and JSON.parse then
          local okJ, o = pcall(JSON.parse, txt)
          if okJ and type(o) == "table" then obj = o end
        elseif json and json.decode then
          local okJ, o = pcall(json.decode, txt)
          if okJ and type(o) == "table" then obj = o end
        end
        if obj then data = obj end
      end
    end
  end

  if type(data) ~= "table" then
    return nil, "Failed to read/parse ui_car.json: " .. path .. " (type=" .. tostring(type(data)) .. ")"
  end

  -- ---------- Extract metrics (mods are inconsistent) ----------
  local pRaw =
    (data.specs and (data.specs.bhp or data.specs.power or data.specs.maxPower))
    or data.bhp
    or data.power
    or data.maxPower
    or data.enginePower
    or data.powerHP
    or data.hp

  local power = normalizePowerToHP(extractNumber(pRaw))

  -- fallback: some cars provide a powerCurve array
  if not power and type(data.powerCurve) == "table" then
    local maxP = nil
    for _, pt in ipairs(data.powerCurve) do
      local v = (type(pt) == "table") and pt[2] or nil
      v = extractNumber(v)
      if v and (not maxP or v > maxP) then maxP = v end
    end
    power = normalizePowerToHP(maxP)
  end

  local wRaw =
    (data.specs and (data.specs.weight or data.specs.mass))
    or data.weight
    or data.mass
    or data.totalMass
    or data.carMass

  local weight = extractNumber(wRaw)

  -- optional: if power missing but pwratio exists (kg/hp), derive power from weight
  if (not power) and weight and data.specs and data.specs.pwratio then
    local kgPerHp = extractNumber(data.specs.pwratio)
    if kgPerHp and kgPerHp > 0 then
      power = weight / kgPerHp
    end
  end


  local tsRaw =
    (data.specs and (data.specs.topspeed or data.specs.topSpeed or data.specs.top_speed))
    or data.topspeed
    or data.topSpeed
    or data.top_speed

  local topSpeedKmh = extractNumber(tsRaw)

-- ✅ FIX: unit-aware top speed parsing
-- If the field includes units (e.g., "350Km/h" like in many ui_car.json files), respect them.
-- Only use a fallback heuristic when it's unitless.
do
  local s = (type(tsRaw) == "string") and tsRaw:lower() or ""

  if s:find("mph", 1, true) then
    -- mph -> km/h
    if topSpeedKmh then topSpeedKmh = topSpeedKmh * 1.60934 end

  elseif s:find("km", 1, true) or s:find("kph", 1, true) then
    -- already km/h (do nothing)

  else
    -- Unitless fallback:
    -- Assetto mods are usually km/h, so default to km/h unless configured otherwise.
    local assumeMphBelow = tonumber(carScanConfig.topSpeedAssumeMphBelow or 0) or 0
    if assumeMphBelow > 0 and topSpeedKmh and topSpeedKmh > 0 and topSpeedKmh <= assumeMphBelow then
      topSpeedKmh = topSpeedKmh * 1.60934
    end
  end
end

  return {
    carId = carId,
    name = data.name,
    brand = data.brand,
    powerHP = power,
    weightKG = weight,
    p2w = (power and weight) and (power / weight) or nil,
    topSpeedKmh = topSpeedKmh
  }, nil
end

local function readMaybeFunction(carObj, v)
  if type(v) == "function" then
    -- Many CSP structs expose methods that require self (carObj)
    local ok, out = pcall(v, carObj)
    if ok then return out end

    -- Some versions expose zero-arg functions, so try that too
    ok, out = pcall(v)
    if ok then return out end

    return nil
  end
  return v
end

local function getCarIdForIndex(i)
  local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
  if not car then return nil end

  -- Try the common identifiers
  local id = nil

  -- car.id might be a string OR a function
  local ok1, rawId = pcall(function() return car.id end)
  if ok1 then id = readMaybeFunction(car, rawId) end
  if id and id ~= "" then return tostring(id) end

  -- car.model might be a string OR a function
  local ok2, rawModel = pcall(function() return car.model end)
  if ok2 then id = readMaybeFunction(car, rawModel) end
  if id and id ~= "" then return tostring(id) end

  -- Try car.carId if some builds expose it
  local ok3, rawCarId = pcall(function() return car.carId end)
  if ok3 then id = readMaybeFunction(car, rawCarId) end
  if id and id ~= "" then return tostring(id) end

  return nil
end

local function buildSessionCarDBFromIndices(indices)
  -- Cache across calls so UI doesn't rescan the whole grid every frame.
  sessionCarDB = sessionCarDB or {}

  local loaded = 0
  local missing = 0
  local errors = {}

  -- DEBUG: capture the first attempted load failure to show path / carId issues
  local firstTried = nil

  for _, i in ipairs(indices) do
    local carId = getCarIdForIndex(i)
    
    if carId and type(carId) ~= "string" then
      if type(carId) == "number" then
        carId = tostring(carId)
      else
        -- reject function/table/etc so it doesn’t become "function: 0xff"
        carId = nil
      end
    end

    if carId then
      if not sessionCarDB[carId] then
        local entry, err = loadCarUIData(carId)

        if not entry and not firstTried then
          firstTried = { carId = carId, error = err }
        end

        if entry then
          sessionCarDB[carId] = entry
          loaded = loaded + 1
        else
          missing = missing + 1
          errors[#errors+1] = { carId = carId, error = err }
        end
      end
    else
      missing = missing + 1
      local err = "No carId available for index"
      errors[#errors+1] = { carId = tostring(i), error = err }

      if not firstTried then
        firstTried = { carId = tostring(i), error = err }
      end
    end
  end

  return sessionCarDB, loaded, missing, errors, firstTried
end

-- =======================================================
-- Manual Multi-Class UI Support
-- Returns per-car stats for the current SESSION AI field
-- (Name, Top speed, P/W) so UI can display + allow manual class assignment
-- =======================================================
function M.getSessionCarStats(sim, cfg)
  cfg = cfg or {}
  sim = sim or ac.getSim()

  loadCarScanConfig()

  -- Cache results per session to avoid repeated disk scans when UI calls this frequently.
  cfg._sessionScan = cfg._sessionScan or {}
  local sessKey = tostring(sim.currentSessionIndex or 0) .. "|" .. tostring(sim.carsCount or 0)
  -- New session: clear per-session caches that may otherwise grow/stale.
  if cfg._sessionScan.key ~= sessKey then
    sessionCarDB = nil
  end
  if cfg._sessionScan.key == sessKey and cfg._sessionScan.stats then
    return cfg._sessionScan.stats, cfg._sessionScan.msg
  end

  if not sim or not sim.carsCount or sim.carsCount <= 0 then
    return {}, "No cars in session."
  end

  -- collect AI indices
  local indices = {}
  for i = 0, (sim.carsCount - 1) do
    local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
    if car and car.isAIControlled then
      indices[#indices + 1] = i
    end
  end

  if #indices == 0 then
    return {}, "No AI cars found."
  end

  -- build / refresh session DB (only cars in this session)
  local _, loaded, missing, errors, firstTried = buildSessionCarDBFromIndices(indices)

  -- Build output list for UI
  local out = {}
  for _, i in ipairs(indices) do
    local carId = getCarIdForIndex(i)
    local entry = (carId and sessionCarDB and sessionCarDB[carId]) or nil
    local driverName = ac.getDriverName(i) or ("AI " .. tostring(i))

    if entry then
      out[#out + 1] = {
        index = i,
        carId = carId,
        name = entry.name or driverName,
        topSpeedKmh = entry.topSpeedKmh,
        p2w = entry.p2w,
        powerHP = entry.powerHP,
        weightKG = entry.weightKG
      }
    else
      -- fallback row (still include it so UI can show “missing data”)
      out[#out + 1] = {
        index = i,
        carId = carId,
        name = driverName,
        topSpeedKmh = nil,
        p2w = nil,
        powerHP = nil,
        weightKG = nil,
        _missing = true
      }
    end
  end

  -- Sort best-first by p2w (if available), otherwise by topSpeed
  table.sort(out, function(a, b)
    local ap = a.p2w or -1
    local bp = b.p2w or -1
    if ap ~= bp then return ap > bp end
    local as = a.topSpeedKmh or -1
    local bs = b.topSpeedKmh or -1
    return as > bs
  end)

  local report = string.format(
    "Session car stats: %d AI cars (ui_car loaded=%d, missing=%d)",
    #indices, loaded or 0, missing or 0
  )

  if firstTried and firstTried.error then
    report = report .. "\nFirst tried: " .. tostring(firstTried.carId) .. " (" .. tostring(firstTried.error) .. ")"
  end

  -- Cache for this session key (avoid re-reading ui_car.json repeatedly)
  cfg._sessionScan.key = sessKey
  cfg._sessionScan.stats = out
  cfg._sessionScan.msg = report

  -- Optional: return errors table for debug printing in UI if you want
  return out, report, errors
end

-- ===== Multiclass (power-based) classification =====
local function kmeans1d(values, k, iters)
  -- values: array of numbers
  if #values == 0 then return {}, {} end
  k = math.max(1, math.min(k, #values))
  iters = iters or 12
  -- init centers using evenly spaced quantiles
  table.sort(values)
  local centers = {}
  for i = 1, k do
    local idx = math.floor((i - 0.5) * (#values / k))
    idx = math.max(1, math.min(#values, idx))
    centers[i] = values[idx]
  end
  local assigns = {}
  for _ = 1, iters do
    -- assign
    local sums = {}
    local counts = {}
    for i = 1, k do sums[i] = 0; counts[i] = 0 end
    for i = 1, #values do
      local v = values[i]
      local bestJ = 1
      local bestD = math.abs(v - centers[1])
      for j = 2, k do
        local d = math.abs(v - centers[j])
        if d < bestD then bestD = d; bestJ = j end
      end
      assigns[i] = bestJ
      sums[bestJ] = sums[bestJ] + v
      counts[bestJ] = counts[bestJ] + 1
    end
    -- update
    local changed = false
    for j = 1, k do
      if counts[j] > 0 then
        local newC = sums[j] / counts[j]
        if math.abs(newC - centers[j]) > 0.01 then changed = true end
        centers[j] = newC
      end
    end
    if not changed then break end
  end
  return centers, assigns
end

local function estimateHPFromCar(car)
  if not car then return nil end

  -- IMPORTANT:
  -- On your CSP build, accessing car.power directly can throw:
  -- 'struct_state_car' has no member named 'power'
  -- So EVERYTHING must be read through pcall.

  local function safeGet(fn)
    local ok, v = pcall(fn)
    if ok and type(v) == "number" then return v end
    return nil
  end

  local p =
      safeGet(function() return car.power end)
      or safeGet(function() return car.enginePower end)
      or safeGet(function() return car.maxPower end)
      or safeGet(function() return car.powerKW end)
      or safeGet(function() return car.powerW end)
      or safeGet(function() return car.specs and car.specs.power end)
      or safeGet(function() return car.specs and car.specs.maxPower end)
      or safeGet(function() return car.performance and car.performance.power end)

  if not p then return nil end

   -- watts -> hp
  if p > 2000 then
    return p / 745.7
  end

  -- kW -> hp (if it’s a small value like 250, it’s likely kW)
  if p > 50 and p < 2000 then
    return p * 1.34102209
  end

  -- already hp-ish
  return p
end

local function classifyDriversByHP(drivers, k)

  -- returns: classForIndex[carIndex] = classId (1..k), report string
  local values = {}
  local carRefs = {}
  for i = 1, #drivers do
    local d = drivers[i]
    local car = ac.getCar(d.index)
    local hp = estimateHPFromCar(car)
    if hp then
      values[#values+1] = hp
      carRefs[#carRefs+1] = d.index
    end
  end

  if #values < 4 then
    return nil, "Not enough HP data to classify (" .. tostring(#values) .. " cars reported HP)."
  end

  local centers, assigns = kmeans1d({table.unpack(values)}, k, 14)
  -- sort centers ascending and remap
  local order = {}
  for j = 1, #centers do order[j] = j end
  table.sort(order, function(a,b) return centers[a] < centers[b] end)
  local remap = {}
  for rank = 1, #order do remap[order[rank]] = rank end

  local classForIndex = {}
  local classCounts = {}
  local mins = {}
  local maxs = {}
  for c = 1, k do classCounts[c]=0; mins[c]=1e9; maxs[c]=-1e9 end

  for n = 1, #values do
    local rawC = assigns[n]
    local c = remap[rawC]
    local idx = carRefs[n]
    classForIndex[idx] = c
    classCounts[c] = classCounts[c] + 1
    mins[c] = math.min(mins[c], values[n])
    maxs[c] = math.max(maxs[c], values[n])
  end

  local reportLines = {}
  reportLines[#reportLines+1] = "Multiclass: " .. tostring(k) .. " classes (power-based)"
  for c = 1, k do
    local lo = mins[c] < 1e8 and mins[c] or 0
    local hi = maxs[c] > -1e8 and maxs[c] or 0
    reportLines[#reportLines+1] = string.format("Class %d: %d cars (%.0f–%.0f hp)", c, classCounts[c], lo, hi)
  end
  return classForIndex, table.concat(reportLines, "\n")
end

local function classifyDriversByUICar(tmpDrivers, k)
  k = tonumber(k or carScanConfig.defaultClassCount or 2) or 2
  k = clamp(k, 2, 5)

  local metricName = carScanConfig.metric or "p2w"

  -- Gather metric values per car index
  local usable = {}
  for _, d in ipairs(tmpDrivers or {}) do
    local carId = getCarIdForIndex(d.index)
    local entry = carId and sessionCarDB and sessionCarDB[carId] or nil
    local metric = nil

   if entry then
  local m = tostring(metricName or "p2w"):lower()

  if m == "power" or m == "hp" then
    metric = entry.powerHP
  elseif m == "weight" then
    metric = entry.weightKG
  elseif m == "topspeed" or m == "top_speed" or m == "speed" then
    metric = entry.topSpeedKmh or entry.powerHP -- fallback to HP if top speed missing
  else
    metric = entry.p2w
  end
end

    if metric and metric > 0 then
      usable[#usable+1] = { index = d.index, carId = carId, metric = metric }
    end
  end

  if #usable < (carScanConfig.minCarsWithMetric or 4) then
    return nil, "Not enough ui_car metric data to classify (" .. tostring(#usable) .. " cars have metric)."
  end

  table.sort(usable, function(a,b) return a.metric > b.metric end)

  -- Prefer gap split for 2-class series (LMPH/GT3)
  local classForIndex = {}
  local reportLines = {}
  reportLines[#reportLines+1] = "Multiclass: " .. tostring(k) .. " classes (ui_car " .. metricName .. ")"

  if carScanConfig.gapSplit then
    local minPct = carScanConfig.gapSplitMinPercent or 0.06
    local minPer = carScanConfig.minCarsPerClass or 4
    local n = #usable

    -- Precompute relative drops between adjacent sorted cars (descending metric)
    local drops = {}
    for i = 1, (n - 1) do
      local a = usable[i].metric
      local b = usable[i+1].metric
      if a and b and a > 0 and b > 0 then
        drops[i] = (a - b) / a
      else
        drops[i] = 0
      end
    end

    local bestSplits = nil -- array of split indices (end index of each faster chunk)
    local bestScore = 0

    local function scoreForSplits(splits)
      local s = 0
      for _, idx in ipairs(splits) do
        s = s + (drops[idx] or 0)
      end
      return s
    end

    local function splitsAreValid(splits)
      local prev = 0
      for _, idx in ipairs(splits) do
        if (idx - prev) < minPer then return false end
        if (drops[idx] or 0) < minPct then return false end
        prev = idx
      end
      if (n - prev) < minPer then return false end
      return true
    end

    if k == 2 then
      for i = 1, (n - 1) do
        local splits = { i }
        if splitsAreValid(splits) then
          local sc = scoreForSplits(splits)
          if sc > bestScore then bestScore = sc; bestSplits = splits end
        end
      end
    elseif k == 3 then
      for i = 1, (n - 2) do
        for j = (i + 1), (n - 1) do
          local splits = { i, j }
          if splitsAreValid(splits) then
            local sc = scoreForSplits(splits)
            if sc > bestScore then bestScore = sc; bestSplits = splits end
          end
        end
      end
    elseif k == 4 then
      for i = 1, (n - 3) do
        for j = (i + 1), (n - 2) do
          for l = (j + 1), (n - 1) do
            local splits = { i, j, l }
            if splitsAreValid(splits) then
              local sc = scoreForSplits(splits)
              if sc > bestScore then bestScore = sc; bestSplits = splits end
            end
          end
        end
      end
    end

    if bestSplits then
      -- Assign classes by segment; class number increases with speed (fastest = k)
      local seg = 1
      local nextSplit = bestSplits[seg]
      for i, item in ipairs(usable) do
        while nextSplit and i > nextSplit do
          seg = seg + 1
          nextSplit = bestSplits[seg]
        end
        local mapped = seg  -- fastest = 1
        classForIndex[item.index] = mapped
      end

      -- Build per-class stats for report
      local counts = {}
      local mins = {}
      local maxs = {}
      for c = 1, k do
        counts[c] = 0
        mins[c] = 1e9
        maxs[c] = -1e9
      end
      for _, item in ipairs(usable) do
        local c = classForIndex[item.index] or 1
        counts[c] = counts[c] + 1
        mins[c] = math.min(mins[c], item.metric)
        maxs[c] = math.max(maxs[c], item.metric)
      end

      reportLines[#reportLines+1] = string.format("Gap split used (min gap %.1f%%, min/class %d).", minPct * 100, minPer)
      for c = k, 1, -1 do
        local lo = (mins[c] < 1e8) and mins[c] or 0
        local hi = (maxs[c] > -1e8) and maxs[c] or 0
        -- note: show fastest-to-slowest ordering in report
        reportLines[#reportLines+1] = string.format("Class %d: %d cars (%.0f–%.0f %s)", c, counts[c], lo, hi,
          (tostring(metricName):lower() == "topspeed") and "km/h" or "metric")
      end

      return classForIndex, table.concat(reportLines, "\n")
    end
  end
  -- Fallback: even split by sorted metric
  local chunk = math.ceil(#usable / k)
  for i, item in ipairs(usable) do
    local c = math.floor((i - 1) / chunk) + 1
    -- Make larger class = faster to match your existing yield logic:
    local mapped = c  -- fastest = 1
    classForIndex[item.index] = mapped
  end

  reportLines[#reportLines+1] = "Even split used (no suitable gap split found)."
  return classForIndex, table.concat(reportLines, "\n")
end

local function smoothTowards(curr, target, rate, dt)
  local t = clamp(dt * rate, 0, 1)
  return curr + (target - curr) * t
end

local function classifyTierFromHP(hp)
  -- 1 = GT-ish, 2 = proto-ish
  if hp >= 560 then return 2 end
  return 1
end

local function getCornerKeys(car, turn, cfg)
  local turnIndex = safeNumber(function() return turn and turn.index end, nil)
  local turnKey = nil
  if turnIndex ~= nil then
    turnKey = "turn_" .. tostring(turnIndex)
  end

  local spline = safeNumber(function() return car.splinePosition end, 0)

  local bucketCount = 60
  if cfg then
    bucketCount = tonumber(cfg._aiHintsBucketCount or cfg.aiHintsBucketCount) or 60
  end

  local bucket = math.floor(spline * bucketCount + 0.5)
  local splineKey = "spline_" .. tostring(bucket)

  return turnKey, splineKey
end

-- ✅ FIX: corner node can be addressed by either turnKey or splineKey.
-- We read from either and then alias BOTH keys to the same node table.
local function getOrCreateCornerNode(mem, trackId, turnKey, splineKey)
  mem.tracks = mem.tracks or {}
  local track = mem.tracks[trackId]
  if not track then
    track = { turns = {} }
    mem.tracks[trackId] = track
  end

  track.turns = track.turns or {}

  -- Prefer splineKey for stability, but accept either.
  local primaryKey = splineKey or turnKey
  local secondaryKey = (primaryKey == splineKey) and turnKey or splineKey

  local node = primaryKey and track.turns[primaryKey] or nil
  if not node and secondaryKey then
    node = track.turns[secondaryKey]
    -- If found under the other key, alias it to primary for future consistency:
    if node and primaryKey then
      track.turns[primaryKey] = node
    end
  end

  if not node then
    node = {
      danger = 0,
      events = 0,
      improve = 0,
      cleanStreak = 0,
      eventsSinceClean = 0,
      entryCapKmh = 0,
      brakeBias = 0,
      noPass = false,
      noPassUntilLap = -1
    }
    if primaryKey then
      track.turns[primaryKey] = node
    elseif secondaryKey then
      track.turns[secondaryKey] = node
    end
  end

  -- Alias BOTH keys to the same node table (prevents “learned but not applied”)
  if node then
    if turnKey then track.turns[turnKey] = node end
    if splineKey then track.turns[splineKey] = node end
  end

  return node, (primaryKey or secondaryKey)
end

local function hash01(s)
  local h = 0
  for i = 1, #s do
    h = (h * 31 + string.byte(s, i)) % 1000000
  end
  return h / 1000000
end

-- Same class distribution as UI:
--  a = 0   -> 80 / 10 / 10
--  a = 0.5 -> 33 / 33 / 33
--  a = 1   -> 10 / 10 / 80
local function computeClassPercentages(a)
  local pChill, pNormal, pAttack
  if a <= 0.5 then
    local t = a / 0.5
    pChill  = lerp(0.80, 0.33, t)
    pNormal = lerp(0.10, 0.33, t)
    pAttack = lerp(0.10, 0.33, t)
  else
    local t = (a - 0.5) / 0.5
    pChill  = lerp(0.33, 0.10, t)
    pNormal = lerp(0.33, 0.10, t)
    pAttack = lerp(0.33, 0.80, t)
  end
  local sum = pChill + pNormal + pAttack
  return pChill / sum, pNormal / sum, pAttack / sum
end

-- Map slider + class → numeric aggression (0..1)
local function classAggression(class, sliderNorm)
  local baseChill  = 0.15
  local baseNormal = 0.50
  local baseAttack = 0.85
  local scale = lerp(0.8, 1.2, sliderNorm)

  if class == "chill" then
    return clamp(baseChill * (1.0 - 0.3 * sliderNorm), 0.05, 0.3)
  elseif class == "normal" then
    return clamp(baseNormal * scale, 0.3, 0.8)
  else
    return clamp(baseAttack * (0.8 + 0.4 * sliderNorm), 0.6, 1.0)
  end
end

-- -------------------------------------------------------------------
-- Pack context (ahead, side-by-side, blue flags)
-- -------------------------------------------------------------------
-- Spline delta helpers (handle start/finish wrap-around)
-- Returns distance from `fromSpline` to `toSpline` going forward along the track, in [0, 1).
local function splineDeltaForward(toSpline, fromSpline)
  local d = (toSpline or 0) - (fromSpline or 0)
  if d < 0 then d = d + 1 end
  return d
end

-- Returns smallest signed delta between two spline positions, in [-0.5, 0.5].
local function splineDeltaSigned(toSpline, fromSpline)
  local d = (toSpline or 0) - (fromSpline or 0)
  if d > 0.5 then d = d - 1 end
  if d < -0.5 then d = d + 1 end
  return d
end

local function getAheadInfo(myIndex, myCar)
  local mySpline = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap    = safeNumber(function() return myCar.lapCount end, 0)
  local closest  = 1.0
  local bestCar  = nil
  local bestIdx  = nil

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= myIndex then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        if safeNumber(function() return oc.lapCount end, 0) == myLap then
          local diff = splineDeltaForward(safeNumber(function() return oc.splinePosition end, 0), mySpline)
          if diff > 0 and diff < closest then
            closest = diff
            bestCar = oc
            bestIdx = otherIndex
          end
        end
      end
    end
  end

  if bestCar then
    local mySpeed    = myCar.speedKmh or 0
    local aheadSpeed = bestCar.speedKmh or 0
    return closest, mySpeed - aheadSpeed, bestCar, bestIdx
  end

  return 1.0, 0.0, nil, nil
end

local function getBehindInfo(myIndex, myCar)
  local mySpline = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap    = safeNumber(function() return myCar.lapCount end, 0)
  local closest  = 1.0
  local bestCar  = nil
  local bestIdx  = nil

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= myIndex then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        if safeNumber(function() return oc.lapCount end, 0) == myLap then
          local oSpline = safeNumber(function() return oc.splinePosition end, 0)
          -- Distance from the other car to us, going forward: if small, other is just behind.
          local diff = splineDeltaForward(mySpline, oSpline)
          if diff > 0 and diff < closest then
            closest = diff
            bestCar = oc
            bestIdx = otherIndex
          end
        end
      end
    end
  end

  if bestCar then
    local mySpeed     = myCar.speedKmh or 0
    local behindSpeed = bestCar.speedKmh or 0
    return closest, behindSpeed - mySpeed, bestCar, bestIdx
  end

  return 1.0, 0.0, nil, nil
end


local function getSideBySideFactor(myIndex, myCar)
  local mySpline = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap    = safeNumber(function() return myCar.lapCount end, 0)
  local count    = 0
  local minDiff  = 1.0

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= myIndex then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        if safeNumber(function() return oc.lapCount end, 0) == myLap then
          local diff = math.abs(splineDeltaSigned(safeNumber(function() return oc.splinePosition end, 0), mySpline))
          if diff < 0.01 then
            count   = count + 1
            minDiff = math.min(minDiff, diff)
          end
        end
      end
    end
  end

  return count, minDiff
end

local function getBlueFlagState(myIndex, myCar)
  local mySpline = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap    = safeNumber(function() return myCar.lapCount end, 0)
  local bestGap  = 1.0
  local lapping  = nil

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= myIndex then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        local oLap    = safeNumber(function() return oc.lapCount end, 0)
        local oSpline = safeNumber(function() return oc.splinePosition end, 0)
        local lapDiff = oLap - myLap

        if lapDiff >= 1 then
          local relSpline = splineDeltaForward(mySpline, oSpline)
          if relSpline > 0 and relSpline < 0.06 then
            if relSpline < bestGap then
              bestGap = relSpline
              lapping = oc
            end
          end
        end
      end
    end
  end

  if lapping then
    return true, bestGap, lapping
  end
  return false, 1.0, nil
end


-- Find a faster-tier car behind (same lap) within distance (meters-ish along spline)
local function findFasterCarBehind(sim, d, distWindowM)
  if not sim or not sim.carsCount then return nil end
  local myCar = ac.getCar(d.index)
  if not myCar then return nil end
  local myPos = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap = safeNumber(function() return myCar.lapCount end, 0)

  local best, bestGapM = nil, 1e9
  local trackLen = safeNumber(function() return sim.trackLengthM end, 0)
  local fallbackLen = 5000

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= d.index then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        local oLap = safeNumber(function() return oc.lapCount end, 0)
        if oLap == myLap then
          local otherD = drivers[otherIndex]
          local otherTier = otherD and otherD.classTier or 1
          if otherTier < (d.classTier or 1) then
            local gap = myPos - safeNumber(function() return oc.splinePosition end, 0)
            if gap < 0 then gap = gap + 1 end
            local gapM = (trackLen > 0 and gap * trackLen) or (gap * fallbackLen)
            if gapM < distWindowM and gapM < bestGapM then
              bestGapM = gapM
              best = { car = oc, driver = otherD, gapM = gapM }
            end
          end
        end
      end
    end
  end
  return best
end

local function findSlowerCarAhead(sim, d, distWindowM)
  if not sim or not sim.carsCount then return nil end
  local myCar = ac.getCar(d.index)
  if not myCar then return nil end
  local myPos = safeNumber(function() return myCar.splinePosition end, 0)
  local myLap = safeNumber(function() return myCar.lapCount end, 0)

  local best, bestGapM = nil, 1e9
  local trackLen = safeNumber(function() return sim.trackLengthM end, 0)
  local fallbackLen = 5000

  for otherIndex, _ in pairs(drivers) do
    if otherIndex ~= d.index then
      local oc = ac.getCar(otherIndex)
      if oc and oc.isAIControlled then
        local oLap = safeNumber(function() return oc.lapCount end, 0)
        if oLap == myLap then
          local otherD = drivers[otherIndex]
          local otherTier = otherD and otherD.classTier or 1
          if otherTier > (d.classTier or 1) then
            local gap = safeNumber(function() return oc.splinePosition end, 0) - myPos
            if gap < 0 then gap = gap + 1 end
            local gapM = (trackLen > 0 and gap * trackLen) or (gap * fallbackLen)
            if gapM < distWindowM and gapM < bestGapM then
              bestGapM = gapM
              best = { car = oc, driver = otherD, gapM = gapM }
            end
          end
        end
      end
    end
  end
  return best
end


-- -------------------------------------------------------------------
-- Driver build
-- -------------------------------------------------------------------
local function rebuildDrivers(sim, cfg)
  drivers = {}

  if not sim or not sim.carsCount or sim.carsCount <= 0 then
    return
  end

  local carsCount = sim.carsCount
  local a = clamp((cfg.aggression or 50) / 100.0, 0, 1)
  local pChill, pNormal, pAttack = computeClassPercentages(a)

  local aiCars = {}
  for i = 0, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
    if car and car.isAIControlled then
      local name = ac.getDriverName(i) or ("AI" .. i)
      local key  = tostring(i) .. "|" .. name
      table.insert(aiCars, { index = i, r = hash01(key) })
    end
  end

  local N = #aiCars
  if N == 0 then return end

  table.sort(aiCars, function(a_, b_) return a_.r < b_.r end)

  local nChill  = math.floor(pChill  * N + 0.0001)
  local nNormal = math.floor(pNormal * N + 0.0001)
  local nAttack = N - nChill - nNormal
  if nAttack < 0 then nAttack = 0 end
  local used = nChill + nNormal + nAttack
  if used < N then
    nAttack = nAttack + (N - used)
  end

  for idx, info in ipairs(aiCars) do
    local class
    if idx <= nChill then
      class = "chill"
    elseif idx <= nChill + nNormal then
      class = "normal"
    else
      class = "attack"
    end

    local baseBrakeHint = 1.0
    local ok, ini = pcall(ac.INIConfig.carData, info.index, "ai.ini")
    if ok and ini then
      baseBrakeHint = ini:get("PEDALS", "BRAKE_HINT", 1.0)
    end

    local jitterSeed  = "paceJitter|" .. tostring(info.index)
    local jitterScale = (cfg.jitterScale or 0.35)  -- 0.0..1.0 (default less jitter)
    local jitter      = (hash01(jitterSeed) - 0.5) * 0.01 * jitterScale

    -- ✅ Low Downforce mode: optionally converge speeds (remove jitter)
    if cfg.lowDownforceAIEnabled and (cfg.lowDownforceAIConverge or false) then
      jitter = 0.0
    end

    local carRef      = ac.getCar(info.index)
    local hpEstimate = 0
    local classTier = 1

    drivers[info.index] = {
      index            = info.index,
      class            = class,
      hpEstimate       = hpEstimate,
      classTier        = classTier,
      baseBrakeHint    = baseBrakeHint,
      brakeHint        = baseBrakeHint,
      throttleLimit    = 1.0,
      topSpeedLimit    = 1.0,
      stintJitter      = jitter,

      -- ✅ New: Draft / stuck-behind state (intentional straight passes)
      draft = {
        targetIdx   = nil,   -- who we're stuck behind
        behindTime  = 0.0,   -- seconds close to same target
        stuckRamp   = 0.0,   -- 0..1 impatience
        state       = "follow", -- follow | commit | abort
        stateTimer  = 0.0,
        cooldown    = 0.0,
      },

      -- ✅ New: "Eye of the Tiger" hot lap burst state
      hotLapTimer     = 0.0,
      hotLapCooldown  = 10.0 + (hash01("hotCD|" .. tostring(info.index)) * 15.0),
      hotLapLastLap   = -1,

      -- ✅ NEW: tiger streak (N full laps)
      tigerLapsLeft   = 0,
      tigerLapArmed   = -1,

      -- ✅ Off-track tracking (for hard event learning)
      offTrackTime    = 0.0,   -- seconds continuously off-track
      lastHardEventLap= -1,    -- per-corner/per-lap gate uses this as a fallback

      -- ✅ New: "Hunt" state (claw back after being passed)
      gotPassedTimer   = 0.0,   -- counts up after being passed (delay window)
      huntTimer        = 0.0,   -- active hunt burst duration
      huntCooldown     = 15.0 + (hash01("huntCD|" .. tostring(info.index)) * 20.0),
      huntLastPos      = nil,   -- track last known race position

      lastRPM          = 0,
      lastGear         = 0,
      engineSafeTimer  = 0,
      breakawayTimer  = 0,
      lastRacePos     = nil,

      lastSpeed        = 0,
      lastSpline       = 0,
      approachSpeed    = 0,

      -- For "grip budget" heuristics
      lastSlipAngle    = 0,
      gripAlarm        = 0,

      -- For contact detection (damage delta)
      lastDamage       = 0,
    }
  end
end

-- -------------------------------------------------------------------
-- Turn phase shaping (entry/apex/exit) using CSP turn distance
-- turn.x appears to be distance to upcoming turn/zone in meters-like units.
-- -------------------------------------------------------------------
local function computeTurnPhase(turn)
  local dist = safeNumber(function() return turn and turn.x end, 9999)
  -- Values tuned to be robust across tracks:
  --  >120: straight
  --  120..70: approach
  --  70..25: braking/turn-in
  --  <25: apex/exit
  if dist > 120 then
    return 0.0, dist -- straight
  elseif dist > 70 then
    return (120 - dist) / 50.0, dist -- approach 0..1
  elseif dist > 25 then
    return 1.0 + (70 - dist) / 45.0, dist -- braking 1..2
  else
    return 2.0 + (25 - dist) / 25.0, dist -- apex/exit 2..3
  end
end

-- Basic "grip alarm" (best-effort; uses slipAngle if available, otherwise speed drops)
local function updateGripAlarm(d, car, dt)
  -- CSP probe confirmed: only angularVelocity.y and splinePosition available on AI cars.
  local speed = car.speedKmh or 0
  local alarm = d.gripAlarm or 0
  local target = 0.0

  -- Signal 1: yaw rate (angularVelocity.y) - primary spin/slide detector
  do
    local ok, av = pcall(function() return car.angularVelocity end)
    if ok and av ~= nil and speed > 30 then
      local ok2, yv = pcall(function() return av.y end)
      if ok2 and type(yv) == "number" then
        local yaw = math.abs(yv)
        if    yaw > 2.5 then target = math.max(target, 1.0)
        elseif yaw > 1.5 then target = math.max(target, 0.7)
        elseif yaw > 0.8 then target = math.max(target, 0.4) end
      end
    end
  end

  -- Signal 2: spline going backwards = definite spin
  do
    local sp = safeNumber(function() return car.splinePosition end, nil)
    if sp ~= nil then
      local lastSP = d._lastSplinePos
      if lastSP ~= nil and dt and dt > 0 then
        local raw = sp - lastSP
        if raw >  0.5 then raw = raw - 1.0 end
        if raw < -0.5 then raw = raw + 1.0 end
        if raw < -0.0003 and speed > 15 then
          target = math.max(target, 1.0)
        end
      end
      d._lastSplinePos = sp
    end
  end

  alarm = smoothTowards(alarm, target, 4.0, dt)
  d.gripAlarm = clamp(alarm, 0, 1)
  return d.gripAlarm
end

-- -------------------------------------------------------------------
-- Main
-- -------------------------------------------------------------------
function M.update(dt, sim, cfg)
  if not sim or not cfg or not cfg.enabled then return end

if cfg.disableDangerMemory == nil then
  cfg.disableDangerMemory = false
end

  local carsCount = sim.carsCount or 0
  if carsCount <= 0 then return end

  local aggression   = cfg.aggression or 50
  local sessionIndex = sim.currentSessionIndex or 0

if sessionIndex ~= lastSessionIndex
  or carsCount ~= lastCarsCount
  or aggression ~= lastAggression
then
  rebuildDrivers(sim, cfg)

  lastSessionIndex = sessionIndex
  lastCarsCount    = carsCount
  lastAggression   = aggression
end

--- ==========================================================
-- Multiclass: tables must live for the whole M.update() scope
-- ==========================================================
local classRank = nil
local classSize = nil

-- ✅ Manual multiclass: update driver tiers from UI mapping (every frame)
if cfg.multiclassEnabled and cfg._multiclassClassForIndex then
  for idx, d in pairs(drivers) do
    local c = cfg._multiclassClassForIndex[idx]
    if c then
      d.classTier = tonumber(c) or d.classTier or 1
    end
  end

  -- ✅ Build per-class rank info (ahead->behind within each tier)
  classRank = {}
  classSize = {}

  local maxTier = clamp(tonumber(cfg.multiclassClassCount or 3) or 3, 1, 5)
  maxTier = math.floor(maxTier + 0.5)

  local byTier = {}
  for t = 1, maxTier do
    byTier[t] = {}
  end

  -- Gather current lap + spline from real cars (not driver table)
  for idx, d in pairs(drivers) do
    local tier = tonumber(d.classTier or 1) or 1
    tier = clamp(tier, 1, maxTier)

    local c = ac.getCar(idx)
    if c and c.isAIControlled then
      local spline = safeNumber(function() return c.splinePosition end, 0)
      local lap    = safeNumber(function() return c.lapCount end, 0)

      table.insert(byTier[tier], {
        index = idx,
        spline = spline,
        lap = lap
      })
    end
  end

    for tier = 1, maxTier do
    table.sort(byTier[tier], function(a, b)
      if a.lap ~= b.lap then return a.lap > b.lap end
      return a.spline > b.spline
    end)

    classSize[tier] = #byTier[tier]
    for pos, item in ipairs(byTier[tier]) do
      classRank[item.index] = pos - 1 -- 0 = class leader
    end
  end
end

-- ==========================================================
-- Overall race order rank (all AI cars)
-- Used for single-class "back catch-up" boost.
-- ==========================================================
local overallRank = {}
local overallSize = 0
do
  local items = {}
  for idx, _ in pairs(drivers) do
    local c = ac.getCar(idx)
    if c and c.isAIControlled then
      local spline = safeNumber(function() return c.splinePosition end, 0)
      local lap    = safeNumber(function() return c.lapCount end, 0)
      items[#items+1] = { index = idx, spline = spline, lap = lap }
    end
  end

  table.sort(items, function(a, b)
    if a.lap ~= b.lap then return a.lap > b.lap end
    return a.spline > b.spline
  end)

  overallSize = #items
  for pos, item in ipairs(items) do
    overallRank[item.index] = pos - 1 -- 0 = overall leader
  end
end

  if not next(drivers) then return end

  local paceEnabled  = (cfg.paceEnabled ~= false)
  local paceStrength = cfg.paceStrength or 50
  local paceNorm     = paceEnabled and clamp(paceStrength / 100.0, 0, 1) or 0.0
  local aggrNorm     = clamp(aggression / 100.0, 0, 1)

  -- New: physics push tuning
  -- Single "Race Intensity" slider (0..100) maps to multiple internal knobs:
  --  Low  : closer to base AC AI (safer, more lift/coast, fewer sends)
  --  High : spicy (later braking, less coasting, stronger straights/passing)
  -- ⚠️ IMPORTANT:
  -- cfg.physicsPush is tuning/settings, NOT the CSP physics API.
  local physicsCfg = cfg.physicsPush or {}
  local intensity = clamp((physicsCfg.intensity or 50) / 100.0, 0, 1)

  -- CSP physics API (may differ by build; use best available)
  local phys = (ac and ac.physics) or physics  -- fallback if your environment injects a global `physics`

  -- Curves (non-linear) so low end stays very close to stock, high end ramps fast
  local t  = intensity
  local t2 = t * t
  local t3 = t2 * t

  -- Commitment / turn-phase shaping
  local pushNorm       = clamp(0.15 + 0.85 * t2, 0, 1)

  -- Stability/self-preservation: slightly higher at low/mid, backs off a bit at the spicy end
  local gripAssistNorm = clamp(0.70 - 0.25 * t + 0.10 * (1 - t2), 0, 1)

  -- Straight-line / pack shaping: grows with intensity but stays subtle
  local topSpeedNorm   = clamp(0.10 + 0.90 * t2, 0, 1)

  -- Overtake boldness: grows strongly with intensity
  local overtakeNorm   = clamp(0.10 + 0.90 * t3, 0, 1)

  local patch   = ac.getPatchVersionCode and ac.getPatchVersionCode() or 0
  for idx, d in pairs(drivers) do
  local car = ac.getCar(d.index)
  if car and car.isAIControlled then
    -- ✅ PROBE init/reset (per AI car, per frame)
    M._implProbe[d.index] = M._implProbe[d.index] or {}
    local pProbe = M._implProbe[d.index]

    -- ✅ REAL cap state (must not depend on probe)
    d.entryCapKmh  = nil
    d.entryCapU    = 0
    d.entryCapKey  = nil

    -- ✅ FIX: reset brakeHint every frame so it doesn't drift/compound
    d.baseBrakeHint = d.baseBrakeHint or 1.0
    d.brakeHint = d.baseBrakeHint

    local class = d.class or "normal"

    -- ===== Base Pace Pack (per class) =====
    local paceBase = 0.0
  if class == "chill" then
    paceBase = cfg.paceBaseChillOverride or -0.03
  elseif class == "attack" then
    paceBase = cfg.paceBaseAttackOverride or 0.03
  end

      if cfg.multiclassEnabled then
        paceBase = paceBase * 0.65
      end

      local lapCount = 0
      do
        local ok, v = pcall(function() return car.lapCount end)
        if ok then lapCount = tonumber(v) or 0 end
      end

      -- ----------------------------------------------------------
      -- Off-track timer (used for "hard event" learning)
      -- ----------------------------------------------------------
      d.offTrackTime = d.offTrackTime or 0.0
      local inPit = safeBool(function() return car.isInPitlane end, false)
                or safeBool(function() return car.isInPit end, false)
      local off = (not inPit) and isOffTrack(car)
      if off then
        d.offTrackTime = d.offTrackTime + dt
      else
        d.offTrackTime = 0.0
      end

-- ==========================================================
-- ✅ Hot Lap Trigger / Timer
-- Randomly gives a driver a “perfect lap” burst sometimes.
-- ==========================================================
do
  local lapNow = lapCount

  -- Init if missing (safe for older save states)
  d.hotLapTimer    = d.hotLapTimer or 0.0
  d.hotLapCooldown = d.hotLapCooldown or 8.0
  d.hotLapLastLap  = d.hotLapLastLap or -1

  -- ✅ NEW: tiger streak state
  d.tigerLapsLeft  = d.tigerLapsLeft or 0
  d.tigerLapArmed  = d.tigerLapArmed or -1

  -- Cooldown ticks down
  d.hotLapCooldown = math.max(0.0, d.hotLapCooldown - dt)

  -- Detect new lap
  if lapNow ~= d.hotLapLastLap then
    d.hotLapLastLap = lapNow

    -- ✅ If tiger is active, consume 1 lap and keep it “on” for the whole lap
    if (d.tigerLapsLeft or 0) > 0 then
      d.tigerLapsLeft = math.max(0, (d.tigerLapsLeft or 0) - 1)

      -- Keep hotLapTimer alive for the whole lap (avoid lap-time dependency)
      d.hotLapTimer = math.max(d.hotLapTimer or 0.0, 999.0)

      -- When streak ends, start cooldown
      if d.tigerLapsLeft <= 0 then
        d.hotLapTimer = 0.0
        d.hotLapCooldown = cfg.tigerCooldownBase
          or (30.0 + 50.0 * hash01("tigerCD|" .. tostring(d.index) .. "|" .. tostring(lapNow)))
      end
    end

    -- ✅ Chance to START a tiger streak (only if not already active)
    if (d.tigerLapsLeft or 0) <= 0 and d.hotLapCooldown <= 0.0 then
      local chance = cfg.tigerChancePerLap or 0.03  -- 3% chance per lap (tune this)
      local roll = hash01("tiger|" .. tostring(d.index) .. "|" .. tostring(sessionIndex) .. "|" .. tostring(lapNow))

      if roll < chance then
        d.tigerLapsLeft = cfg.tigerStreakLaps or 5   -- ✅ your “5 amazing laps”
        d.hotLapTimer = 999.0                        -- keep boosts on for the lap(s)
      end
    end
  end

  -- Timer runs down (normal hotlap mode only; tiger uses 999 and lap logic)
  if d.hotLapTimer > 0.0 and (d.tigerLapsLeft or 0) <= 0 then
    d.hotLapTimer = math.max(0.0, d.hotLapTimer - dt)
  end
end

      local raceT    = clamp(lapCount / 10.0, 0.0, 1.0)
      local finishDelta
      if class == "chill" then
        finishDelta = 0.0 + 0.01 * raceT
      elseif class == "attack" then
        finishDelta = 0.01 - 0.02 * raceT
      else
        finishDelta = 0.005 * (raceT - 0.5)
      end

            local paceOffset = (paceBase * paceNorm) + d.stintJitter + finishDelta

-- ==========================================================
-- ✅ Hot Lap effect (boost paceOffset only)
-- IMPORTANT: paceOffset exists here. targetThrottle/Level do NOT yet.
-- ==========================================================
if (d.hotLapTimer and d.hotLapTimer > 0.0) or ((d.tigerLapsLeft or 0) > 0) then
  local ampPace = cfg.hotLapPaceBoost or 0.020

  local u = 1.0
  if (d.tigerLapsLeft or 0) <= 0 then
    local dur = cfg.hotLapDuration or 70.0
    u = clamp(d.hotLapTimer / dur, 0.0, 1.0)
    u = u * (2.0 - u)
  end

  paceOffset = paceOffset + ampPace * u
end

-- ==========================================================
-- ✅ Hunt effect (boost paceOffset only)
-- IMPORTANT: paceOffset exists here. targetThrottle/Level do NOT yet.
-- ==========================================================
do
  if d.huntTimer and d.huntTimer > 0.0 then
    local dur = cfg.huntDuration or 35.0
    local u = clamp(d.huntTimer / dur, 0.0, 1.0)

    -- shape: strongest early, fades out smoothly
    u = u * (2.0 - u)

    local amp = cfg.huntPaceBoost or 0.018 -- +1.8% pace
    paceOffset = paceOffset + amp * u
  end
end

-- ==========================================================
-- EARLY RACE SPREAD BOOST (Normal + Attack only)
-- Helps field stretch earlier so you don’t carve through half
-- the pack by lap 3 due to endless fighting.
-- ==========================================================
do
  local earlyFrac = cfg.earlySpreadFrac or 0.28   -- first 25% of race
  local ampNormal = cfg.earlySpreadNormalBoost or 0.035
  local ampAttack = cfg.earlySpreadAttackBoost or 0.055

  if raceT < earlyFrac then
    -- ramp OUT smoothly: 1.0 at start -> 0.0 at earlyFrac
    local x = clamp(1.0 - (raceT / earlyFrac), 0, 1)
    -- curve so it fades gently (prevents snap)
    x = x * x

    if class == "normal" then
      paceOffset = paceOffset + ampNormal * x
    elseif class == "attack" then
      paceOffset = paceOffset + ampAttack * x
    end
  end
end

-- ==========================================================
-- MULTICLASS: BOOST SLOWEST CLASS BASELINE
-- Keeps the slowest tier (e.g. GT3s in LMP/GT) from being
-- artificially slow just because they sit at the back overall.
-- ==========================================================
do
  if cfg.multiclassEnabled and classRank and classSize then
    local tier = tonumber(d.classTier or 1) or 1
    local maxTier = clamp(tonumber(cfg.multiclassClassCount or 3) or 3, 1, 5)
    maxTier = math.floor(maxTier + 0.5)

    tier = clamp(tier, 1, maxTier)

    -- Base boost to *all* cars in slowest class
    if tier == maxTier then
      local base = cfg.slowestClassBaseBoost or 0.020
      paceOffset = paceOffset + base

      -- Optional: extra boost for the back half of the slowest class
      local n = classSize[tier] or 0
      if n > 1 then
        local r = classRank[d.index] or 0
        local p = clamp(r / (n - 1), 0, 1) -- 0 leader, 1 last
        local backHalf = clamp((p - 0.50) / 0.50, 0, 1)  -- 0 in front half, 1 at very back
        local extra = cfg.slowestClassBackBoost or 0.020
        paceOffset = paceOffset + (extra * backHalf)
      end
    end
  end
end

      -- ==========================================================
      -- Multiclass: within-class pace spread (fixes GT3 backmarkers
      -- being too easy just because they’re at the back overall).
      -- ==========================================================
      if cfg.multiclassEnabled and classRank and classSize then
  local tier = tonumber(d.classTier or 1) or 1

  local maxTier = clamp(tonumber(cfg.multiclassClassCount or 3) or 3, 1, 5)
  maxTier = math.floor(maxTier + 0.5)
  tier = clamp(tier, 1, maxTier)

  local n = classSize[tier] or 0
        if n > 1 then
          local r = classRank[d.index] or 0

          -- percentile: 0 = class leader, 1 = class last
          local p = clamp(r / (n - 1), 0, 1)

          -- How much spread inside each class (0.0..0.05 suggested)
          -- This acts like "difficulty spread" but within the class.
          local spread = (cfg.multiclassClassSpread or 0.040)

          -- ✅ Leaders-only boost (keep your current behavior)
          local gamma = cfg.multiclassLeaderCurve or 1.4
          local withinClassDelta = (1.0 - p)
          withinClassDelta = math.pow(withinClassDelta, gamma)
          withinClassDelta = withinClassDelta * spread
          paceOffset = paceOffset + withinClassDelta

          -- ✅ NEW: back-of-class catch-up (closes the gap without flattening the front)
          -- p = 0 leader -> ~0
          -- p = 1 last   -> +backCatchup
          local backCatchup = cfg.multiclassBackCatchup or 0.020     -- try 0.015–0.030
          local backGamma   = cfg.multiclassBackCurve or 1.6         -- higher = mostly “very back”
          local backDelta   = math.pow(p, backGamma) * backCatchup
          paceOffset = paceOffset + backDelta
        end
      end

-- ==========================================================
-- Single-class: back-of-field catch-up (closes skill gap)
-- ==========================================================
do
  if (not cfg.multiclassEnabled) and overallSize and overallSize > 1 then
    local r = overallRank[d.index] or 0
    local p = clamp(r / (overallSize - 1), 0, 1)  -- 0 leader, 1 last

    local backCatchup = cfg.singleClassBackCatchup or 0.010  -- try 0.015–0.035
    local backGamma   = cfg.singleClassBackCurve or 1.7      -- higher = mostly “very back”
    paceOffset = paceOffset + math.pow(p, backGamma) * backCatchup
  end
end

-- ==========================================================
-- LATE RACE CHILL BOOST
-- Chill cars pick it up in the last part of the race so you
-- have to defend and things don’t go stale.
-- ==========================================================
do
  if class == "chill" then
    local startAt = cfg.chillLateBoostStart or 0.60  -- starts at 60% race progress
    local amp     = cfg.chillLateBoostAmp or 0.030   -- max boost at the end

    if raceT > startAt then
      local t = clamp((raceT - startAt) / (1.0 - startAt), 0, 1)
      -- curve IN smoothly (so it doesn't pop suddenly)
      t = t * t
      paceOffset = paceOffset + amp * t
    end
  end
end

-- ✅ Strength boost (UI slider): 100 = neutral, 115 = +15%, etc.
local strengthBoost = clamp((cfg.difficultyBoost or cfg.strengthBoost or 100) / 100.0, 0.70, 2.00)

-- Top speed scales with difficulty but more gently than level/throttle
-- so it feels like pace rather than just raw speed.
-- At 100: 1.022 (unchanged). At 110: ~1.032. At 120: ~1.042.
local topSpeedScale = 1.022 + (strengthBoost - 1.0) * (cfg.difficultyTopSpeedScale or 0.10)

-- ✅ Wider level range so AI can actually be >110%
local target = {
  level = clamp((1.0 + paceOffset) * strengthBoost, 0.80, 1.75),
  throttle = clamp((1.0 + paceOffset * 0.7) * lerp(1.00, strengthBoost, 0.70), 0.98, 1.40),
  topSpeed = topSpeedScale,
  brakeHint = d.baseBrakeHint,
  suppressAdvanced = false,
}

      -- Keep existing code structure (locals), but source from our target table.
      local targetLevel    = target.level
      local targetThrottle = target.throttle
      local targetTopSpeed = target.topSpeed

-- ==========================================================
-- ✅ DANGER ZONE: memory-driven. Reads danger from RaceFlow
-- spline_N buckets for this track. Near any hot bucket the
-- "above-base" improvements are pulled back so learning dominates.
-- Strength is a bell curve peaking at the bucket, fading ~1.5 buckets.
-- cfg.dangerZoneDamp  = 0..1  (default 0.60 = 60% reduction)
-- ==========================================================
local learningModuleEnabled = (cfg.learningEnabled ~= false)
local _dangerZoneStr = learningModuleEnabled and getDangerZoneStrength(car, cfg, sim) or 0
if _dangerZoneStr > 0 then
  local damp = clamp(tonumber(cfg.dangerZoneDamp or 0.60) or 0.60, 0.0, 1.0)
  local reduce = _dangerZoneStr * damp

  -- Base neutral values the AI uses with NO improvements
  local BASE_LEVEL    = 1.0
  local BASE_THROTTLE = 1.0
  local BASE_TOPSPEED = 1.0

  -- Pull each target back toward base by (reduce) fraction of the excess
  targetLevel    = BASE_LEVEL    + (targetLevel    - BASE_LEVEL)    * (1.0 - reduce)
  targetThrottle = BASE_THROTTLE + (targetThrottle - BASE_THROTTLE) * (1.0 - reduce)
  targetTopSpeed = BASE_TOPSPEED + (targetTopSpeed - BASE_TOPSPEED) * (1.0 - reduce)

  -- Also pull brakeHint back toward neutral (1.0 is "normal" braking)
  local BASE_BRAKE = 1.0
  d.brakeHint = BASE_BRAKE + (d.brakeHint - BASE_BRAKE) * (1.0 - reduce)
end

-- ==========================================================
-- ✅ Hardcoded "Aero profile" differences by aggression class
-- Mimics downforce vs low-downforce tradeoffs.
-- Adds per-driver jitter so profiles don't run identical.
-- ==========================================================
do
  -- Per-class straight-line advantage
  local tsBoost = 0.0
  if class == "attack" then
    tsBoost = cfg.profileTSAttack or 0.012   -- +1.2%
  elseif class == "normal" then
    tsBoost = cfg.profileTSNormal or 0.008   -- +0.8%
  else
    tsBoost = cfg.profileTSChill or 0.004    -- +0.4%
  end

  -- Per-class corner disadvantage (brake earlier + slightly less exit throttle)
  local cornerPenalty = 0.0
  if class == "attack" then
    cornerPenalty = cfg.profileCornerPenaltyAttack or 0.010  -- 1.0%
  elseif class == "normal" then
    cornerPenalty = cfg.profileCornerPenaltyNormal or 0.006
  else
    cornerPenalty = cfg.profileCornerPenaltyChill or 0.003
  end

  -- Per-driver jitter inside each class: keeps variety
  local jAmp = cfg.profileTSJitter or 0.004  -- ±0.4%
  local j = (hash01("profj|" .. tostring(d.index)) - 0.5) * 2.0
  local tsJitter = 1.0 + j * jAmp

  -- Apply straight advantage
  targetTopSpeed = targetTopSpeed * (1.0 + tsBoost) * tsJitter

  -- Store corner penalty for turn-phase section
  d._profileCornerPenalty = cornerPenalty
end

-- ==========================================================
-- ✅ Hot Lap extra confidence (SAFE placement)
-- Now that targetThrottle/Level/TopSpeed exist, we can modify them.
-- ==========================================================
if (d.hotLapTimer and d.hotLapTimer > 0.0) or ((d.tigerLapsLeft or 0) > 0) then
  local u = 1.0
  if (d.tigerLapsLeft or 0) <= 0 then
    local dur = cfg.hotLapDuration or 70.0
    u = clamp(d.hotLapTimer / dur, 0.0, 1.0)
    u = u * (2.0 - u)
  end

  local ampThrottle = cfg.hotLapThrottleBoost or 0.015 -- +1.5%
  local ampLevel    = cfg.hotLapLevelBoost or 0.010    -- +1.0%
  local ampTopSpeed = cfg.hotLapTopSpeedBoost or 0.006 -- +0.6%
  local ampBrake    = cfg.hotLapBrakeGain or 0.010     -- 1% later braking

  targetThrottle = clamp(targetThrottle * (1.0 + ampThrottle * u), 0.70, 1.20)
  targetLevel    = clamp(targetLevel    * (1.0 + ampLevel    * u), 0.80, 1.90)
  targetTopSpeed = targetTopSpeed * (1.0 + ampTopSpeed * u)

  d.brakeHint = d.brakeHint * (1.0 - ampBrake * u)
end

-- ==========================================================
-- ✅ Hunt extra confidence (SAFE placement)
-- Now that targets exist, we can add bite to chase.
-- ==========================================================
do
  if d.huntTimer and d.huntTimer > 0.0 then
    local dur = cfg.huntDuration or 35.0
    local u = clamp(d.huntTimer / dur, 0.0, 1.0)
    u = u * (2.0 - u)

    local ampThrottle = cfg.huntThrottleBoost or 0.010 -- +1.0%
    local ampLevel    = cfg.huntLevelBoost or 0.006    -- +0.6%
    local ampTopSpeed = cfg.huntTopSpeedBoost or 0.004 -- +0.4%

    targetThrottle = clamp(targetThrottle * (1.0 + ampThrottle * u), 0.70, 1.20)
    targetLevel    = clamp(targetLevel    * (1.0 + ampLevel    * u), 0.80, 1.90)
    targetTopSpeed = targetTopSpeed * (1.0 + ampTopSpeed * u)
  end
end

-- ✅ Wire up topSpeedNorm (Race Intensity / top-speed bias)
-- Gives a little more top speed at higher intensity.
do
  local tsBoostMax = cfg.topSpeedIntensityBoost or 0.025  -- 2.5% max
  targetTopSpeed = targetTopSpeed * (1.0 + tsBoostMax * topSpeedNorm)
end

-- ==========================================================
-- ✅ Low-Downforce AI (UI toggle)
-- Track-level: extra straight-line top-speed boost for everyone.
-- Corner penalty/jitter are HARD-CODED (not exposed in UI).
-- ==========================================================
do
  if cfg.lowDownforceAIEnabled then
    local strength = clamp((cfg.lowDownforceAIStrength or 35) / 100.0, 0.0, 1.0)

    -- Max extra top speed at 100 strength (tunable)
    local maxTS = 0.060 -- 6.0% at full strength

    -- ✅ Hardcoded jitter inside classes so they don’t run identical
    local jitterAmp = 0.008 -- ±.8% (keep subtle; always active when Low-DF enabled)
    local jitter = (hash01("ldf|" .. tostring(d.index) .. "|" .. tostring(lapCount)) - 0.5) * 2.0 * jitterAmp

    local tsMul = 1.0 + (maxTS * strength) + jitter
    targetTopSpeed = targetTopSpeed * tsMul
  end
end

-- ===== MULTICLASS YIELD / PUSH (manual class tiers) =====
if cfg.multiclassEnabled then
  -- ✅ BONUS SAFETY: skip yield/push if all cars are effectively in one class
  local tierSeen = {}
  local tierCount = 0
  for _, od in pairs(drivers) do
    local t = tonumber(od.classTier or 1) or 1
    if not tierSeen[t] then
      tierSeen[t] = true
      tierCount = tierCount + 1
      if tierCount >= 2 then break end
    end
  end

  if tierCount >= 2 then
    local yieldDist = cfg.multiclassYieldDistM or 55
    local pushDist  = cfg.multiclassPushDistM  or 35

    local yieldStrength = (cfg.multiclassYieldStrength or 60) / 100.0
    local pushStrength  = (cfg.multiclassPushStrength  or 45) / 100.0

    local behind = findFasterCarBehind(sim, d, yieldDist)
    local ahead  = findSlowerCarAhead(sim, d, pushDist)

    -- IMPORTANT: Only apply yield/push across *different* class tiers.
    -- Class 1 = fastest, Class 5 = slowest.
    local myTier = tonumber(d.classTier or 1) or 1

    -- Faster CLASS behind -> yield (only if behindTier < myTier)
    if behind and behind.driver then
      local behindTier = tonumber(behind.driver.classTier or 1) or 1
      if behindTier < myTier then
        local proxFactor = clamp(1.0 - (behind.gapM / yieldDist), 0.2, 1.0)
        local ys = yieldStrength * proxFactor
        targetThrottle = clamp(targetThrottle - 0.20 * ys, 0.60, 1.08)
        d.brakeHint    = clamp(d.brakeHint + 0.28 * ys, 0.0, 1.0)
        targetLevel    = clamp(targetLevel - 0.06 * ys, 0.75, 1.20)
      end
    end

    -- Slower CLASS ahead -> push (only if aheadTier > myTier)
    if ahead and ahead.driver then
      local aheadTier = tonumber(ahead.driver.classTier or 1) or 1
      if aheadTier > myTier then
        local proxFactor = clamp(1.0 - (ahead.gapM / pushDist), 0.2, 1.0)
        local ps = pushStrength * proxFactor
        targetThrottle = clamp(targetThrottle + 0.12 * ps, 0.70, 1.14)
        d.brakeHint    = clamp(d.brakeHint - 0.18 * ps, 0.0, 1.0)
        targetLevel    = clamp(targetLevel + 0.05 * ps, 0.80, 1.25)
      end
    end
  end
end

      -- Pack context (ahead/behind) used by draft/hunt/clean-air
      local aheadGap, relSpeed, aheadCar, aheadIdx = getAheadInfo(d.index, car)
      -- (Optional, only if you later need it)
      -- local behindGap, behindRel, behindCar, behindIdx = getBehindInfo(d.index, car)
      local turn = nil
      if ac.getTrackUpcomingTurn then turn = ac.getTrackUpcomingTurn(d.index) 
     end

-- ===== Grip alarm: always update every frame (not just in corners) =====
-- Must run before hard event detection reads d.gripAlarm
updateGripAlarm(d, car, dt)

-- ===== Physics-forward: turn-phase shaping =====
local turnX = safeNumber(function() return turn and turn.x end, nil)
if turnX and turnX > 5 then
  local phase, dist = computeTurnPhase(turn)

  -- ✅ Profile-based corner penalty (always active)
  do
    local profPen = tonumber(d._profileCornerPenalty or 0.0) or 0.0
    if profPen > 0.0 then
      if phase >= 1.0 and phase < 2.3 then
        d.brakeHint = d.brakeHint * (1.0 + profPen)
        targetThrottle = targetThrottle * (1.0 - profPen * 0.55)
      end
      if phase >= 2.0 then
        targetThrottle = targetThrottle * (1.0 - profPen * 0.25)
      end
    end
  end

        -- class commitment: Attack tolerates more, Chill less
        local classCommit = (class == "attack") and 1.00 or (class == "normal" and 0.85 or 0.70)

        -- Grip alarm already updated above; read it here for corner shaping
        local gripAlarm = d.gripAlarm or 0
        local gripMin = cfg.gripAssistThrottleMin or 0.92
        local gripCut   = lerp(1.0, gripMin, gripAlarm * gripAssistNorm) -- reduce throttle when sliding

        -- ✅ Confidence mode: if stable, allow a bit more pace without losing safety
        -- Gated off at danger corners so it doesn't fight the danger system
        local stable = (gripAlarm < 0.20)
        local atDangerCorner = node
          and (not ((node.dangerFrozen == true) or (node.locked == true)))
          and (tonumber(node.danger or 0) or 0) > (cfg.dangerCap or 12) * 0.5
        if stable and not atDangerCorner then
          local conf = lerp(0.0, 1.0, pushNorm)
          d.brakeHint    = d.brakeHint * lerp(1.0, 0.972, conf)     -- later braking
          targetThrottle = targetThrottle * lerp(1.0, 1.030, conf)  -- earlier throttle
        end

        local p = phase

        -- ✅ Traffic corner safety: if side-by-side in a corner/braking zone, force earlier braking
        -- and reduce throttle to prevent the "refuse to slow down" behavior that causes touches/spins.
        local sideCountP, sideMinP = getSideBySideFactor(d.index, car)
        if (sideCountP or 0) > 0 and p >= 1.0 then
          local denom = (cfg.trafficSideMinDiff or 0.010)
          local closeness = clamp(1.0 - ((sideMinP or denom) / denom), 0, 1)
          local bAdd = cfg.trafficCornerBrakeAdd or 0.22
          local tLoss = cfg.trafficCornerThrottleLoss or 0.12

          -- ✅ IMPORTANT: always use applyBrakeHintMul so "more braking" works with either brakeHint convention
          d.brakeHint = applyBrakeHintMul(d.brakeHint, (1.0 + bAdd * closeness), cfg)

          targetThrottle = targetThrottle * (1.0 - tLoss * closeness)
        end

        -- Approach: delay the "early braking" behavior a bit for committed drivers
        if p > 0.2 and p < 1.2 then
          local tt = clamp((p - 0.2) / 1.0, 0, 1)
          local earlyBrakeBias = lerp(1.02, 0.97, tt)
          local commitMul = lerp(1.03, 0.98, classCommit)
          d.brakeHint = d.brakeHint * lerp(1.0, earlyBrakeBias * commitMul, pushNorm)
        end

        -- Braking/turn-in: more trail brake (higher brake hint) and prevent coasting by keeping some throttle authority
        if p >= 1.0 and p < 2.3 then
          local t = clamp((p - 1.0) / 1.3, 0, 1)
          local trail = lerp(1.00, 1.12, t)  -- later braking, but not too spiky
          local throttleShape = lerp(1.00, 1.01, t) -- avoid coasting; keep throttle authority
          local commitTrail = lerp(1.10, 0.92, classCommit) -- Attack needs less extra brake
          d.brakeHint = d.brakeHint * lerp(1.0, trail * commitTrail, pushNorm)
          targetThrottle = targetThrottle * lerp(1.0, throttleShape, pushNorm)
        end

        -- Apex/exit: anti-coast (raise throttle earlier), but clamp by gripCut
        -- Base antiCoast always applies (not gated by pushNorm) so cars get
        -- on throttle quickly regardless of whether they're in combat.
        if p >= 2.0 then
          local t = clamp((p - 2.0) / 1.0, 0, 1)
          local antiCoast = lerp(1.00, 1.18, t) -- was 1.07; stronger exit throttle
          local classExit = (class == "attack") and 1.06 or (class == "normal" and 1.03 or 1.00)
          -- Apply base antiCoast always, pushNorm only adds the extra classExit component
          targetThrottle = targetThrottle * (antiCoast * lerp(1.0, classExit, pushNorm))
        end

        targetThrottle = targetThrottle * gripCut
        end

-- ==========================================================
-- ✅ Low-Downforce corner penalty (hardcoded)
-- Scales lightly with the SAME UI slider (strength),
-- so users get “more straight speed” with a small corner tradeoff.
-- ==========================================================
do
  if cfg.lowDownforceAIEnabled and node then
    local strength = clamp((cfg.lowDownforceAIStrength or 35) / 100.0, 0.0, 1.0)

    -- Hardcoded max penalties (keep small)
    local maxBrake = 0.012   -- up to +1.2% brake hint
    local maxThrot = 0.010   -- up to -1.0% throttle

    -- Only apply in actual corner zones
    local phase = 1.5
    if phase >= 1.0 then
      d.brakeHint    = d.brakeHint * (1.0 + maxBrake * strength)
      targetThrottle = targetThrottle * (1.0 - maxThrot * strength)
    end
  end
end

-- ==========================================================
-- LAP-PERCENTAGE NODE FETCH — no ac.getTrackUpcomingTurn needed
-- ==========================================================
local node = nil
local mem = getMemory()
local trackId = getTrackId(sim)
local bucketCount = tonumber((cfg._aiHintsBucketCount or cfg.aiHintsBucketCount) or 60) or 60
local carSP = safeNumber(function() return car.splinePosition end, 0)
local currentBucket = math.floor(carSP * bucketCount) % bucketCount
local currentKey = "spline_" .. tostring(currentBucket)

if mem then
  node, d._cornerKey = getOrCreateCornerNode(mem, trackId, nil, currentKey)
end

-- ==========================================================
-- Apply learned danger + brake bias from node to AI targets
-- ==========================================================
if learningModuleEnabled and node and not cfg.disableDangerMemory then
  -- dangerFrozen = corner is rehabilitated; don't penalise it
  local frozen = (node.dangerFrozen == true) or (node.locked == true)
  local danger = (not frozen) and (tonumber(node.danger or 0) or 0) or 0.0

  if danger > 0 then
    local cap = tonumber(cfg.dangerCap or 12)
    local v   = (cap > 0) and clamp(danger / cap, 0.0, 1.0) or 0.0

    -- Over-cap slope (diminishing returns beyond dangerCap)
    if danger > cap then
      local slope = tonumber(cfg.dangerOvercapSlope or 0.30) or 0.30
      local ocMax = tonumber(cfg.dangerOvercapMax   or 1.60) or 1.60
      v = 1.0 + clamp((danger - cap) / cap * slope, 0.0, ocMax - 1.0)
    end

    local vSq = v * v  -- non-linear shape

    d.brakeHint    = applyBrakeHintMul(d.brakeHint,
                       1.0 + (cfg.dangerBrakeGain    or 0.18) * vSq, cfg)
    targetTopSpeed = targetTopSpeed
                       * (1.0 - (cfg.dangerTopSpeedLoss  or 0.18) * vSq)
    targetThrottle = clamp(
                       targetThrottle * (1.0 - (cfg.dangerThrottleLoss or 0.14) * vSq),
                       0.70, 1.20)
  end

  -- Brake bias: only apply when corner has active danger.
  -- Prevents permanent earlier braking on corners that have recovered to danger=0.
  local bb = tonumber(node.brakeBias or 0) or 0
  local bbDanger = (not frozen) and (tonumber(node.danger or 0) or 0) or 0.0
  if bb > 0 and bbDanger > 0 then
    d.brakeHint    = applyBrakeHintMul(d.brakeHint,
                       1.0 + bb * (cfg.brakeBiasThrottleLoss or 0.06), cfg)
    targetThrottle = clamp(
                       targetThrottle * (1.0 - bb * (cfg.brakeBiasThrottleLoss or 0.06)),
                       0.70, 1.20)
  end
end

-- ===== Corner learning =====
do
  local memC = getMemory()
  local rollingNow = (cfg._rollingStartActive == true)
  local learningAllowed = (cfg.learningEnabled ~= false)
    and (not rollingNow)

  if cfg.dangerHardCap == nil then
    cfg.dangerHardCap = 60
  end

  if learningAllowed and memC and node then
    local nodeC = node
    local cornerKeyC = currentKey
    local lapNow = safeNumber(function() return car.lapCount end, 0)
    local speedNow = car.speedKmh or 0
    local gripAlarmNow = d.gripAlarm or 0

    local sideCountC = 0
    do
      local sc, _ = getSideBySideFactor(d.index, car)
      sideCountC = tonumber(sc) or 0
    end

    -- Hard event recorder: runs EVERY frame (not lap-gated)
    local function recordHardEvent(reason)
      local now = os.clock()
      if (now - (nodeC._lastEventTime or 0)) < (cfg.hardEventCooldownSec or 4.0) then return end
      nodeC._lastEventTime = now
      nodeC.lastEventReason = reason
      -- === Danger increment ===
      local dangerAdd = cfg.hardEventDangerAdd or 3.5
      local eventCount = (nodeC.eventCount or 0) + 1
      nodeC.eventCount = eventCount
      if eventCount >= (cfg.dangerRampStartEvent or 4) then
        local extra = cfg.dangerRampGain or 0.18
        local pow   = cfg.dangerRampPow  or 1.35
        dangerAdd = dangerAdd + extra * math.pow(eventCount - (cfg.dangerRampStartEvent or 4) + 1, pow)
      end
      local overcapBonus = (nodeC._eventsSinceClean or 0) * (cfg.dangerOvercapBonusPerEvent or 0.10)
      local overcapMax   = math.min(1.0 + overcapBonus, cfg.dangerOvercapMaxCeiling or 2.80)
      nodeC.danger = math.min((nodeC.danger or 0) + dangerAdd, cfg.dangerHardCap or 60)
      nodeC._eventsSinceClean = (nodeC._eventsSinceClean or 0) + 1

      -- === Entry cap drop ===
      -- Seed entryCapKmh from best available reference if not yet set.
      -- Guard: skip near SF line only (sp>0.985 or <0.015) where cars cross
      -- at full speed but formation/grid may have seeded a low value.
      -- lapNow guard removed — lapCount=0 covers the entire first racing lap
      -- in AC, so it was blocking seeding and causing every corner to clamp to min.
      local currentCap = tonumber(nodeC.entryCapKmh or 0) or 0
      local nearSFLine = (carSP > 0.985 or carSP < 0.015)
      if currentCap <= 0 and not nearSFLine then
        local avgSeed = tonumber(nodeC.speedAvg or 0) or 0
        local nSamples = tonumber(nodeC.speedSamples or 0) or 0
        local seed
        if avgSeed > 0 and nSamples >= 3 then
          seed = avgSeed + (cfg.entryCapHeadroomKmh or 8)
        else
          seed = (d.approachSpeed or speedNow or 0)
          if seed < 80 then seed = speedNow end
          seed = seed + (cfg.entryCapHeadroomKmh or 8)
        end
        -- Only seed if we have a meaningful speed reading (not standing start)
        if seed > (cfg.entryCapMinKmh or 60) + 10 then
          currentCap = seed
          nodeC.entryCapKmh = math.max(cfg.entryCapMinKmh or 60, currentCap)
        end
      end

      local dropKmh = 0
      if reason == "overshoot" then
        dropKmh = cfg.entryCapDropKmhOnOvershoot or 12
      elseif reason == "contact" then
        dropKmh = cfg.entryCapDropKmhOnContact   or 18
      elseif reason == "slide" then
        dropKmh = cfg.entryCapDropKmhOnSlide     or 22
      elseif reason == "offtrack" or reason == "impact" then
        dropKmh = cfg.entryCapDropKmhOnOfftrack  or 28
      end
      if dropKmh > 0 then
        nodeC.entryCapKmh = math.max(cfg.entryCapMinKmh or 60, (nodeC.entryCapKmh or currentCap) - dropKmh)
      end

      -- === Brake bias ===
      nodeC.brakeBias = math.min(
        (nodeC.brakeBias or 0) + (cfg.brakeBiasAddOnHardEvent or 0.06),
        cfg.brakeBiasMax or 0.15
      )

      -- === Clean streak + improve penalty reset ===
      nodeC.cleanStreak    = 0
      nodeC.improvePenalty = (nodeC.improvePenalty or 0) + (cfg.hardEventImprovePenalty or 4.0)

      -- === Event log + probe ===
      local entry = {
        index           = d.index,
        lap             = lapNow,
        reason          = reason,
        cornerKey       = cornerKeyC,
        splinePos       = carSP,
        speedKmh        = speedNow,
        entryCapKmh     = nodeC.entryCapKmh or 0,
        brakeBias       = nodeC.brakeBias or 0,
        danger          = nodeC.danger or 0,
        learningAllowed = true,
      }
      table.insert(M._eventLog, entry)
      if #M._eventLog > 60 then table.remove(M._eventLog, 1) end
      M._eventProbe[d.index] = entry

      markMemoryDirty()

      if ac and ac.log then
        ac.log(string.format(
          "[RaceFlow][HARD_EVENT] car=%d reason=%s corner=%s sp=%.3f spd=%.1f danger=%.1f cap=%.1f bias=%.2f",
          tonumber(d.index) or -1, reason, tostring(cornerKeyC),
          tonumber(carSP) or 0, tonumber(speedNow) or 0,
          tonumber(nodeC.danger or 0) or 0,
          tonumber(nodeC.entryCapKmh or 0) or 0,
          tonumber(nodeC.brakeBias or 0) or 0
        ))
      end
    end

    -- ===== Hard event detection (every frame) =====
    -- CSP probe: only speedKmh, splinePosition, angularVelocity available on AI cars.
    -- controls/damage/slipAngle/isOnTrack all ERR. Detectors rebuilt around what exists.

    -- SLIDE / SPIN: gripAlarm driven by yaw rate + backwards spline
    local dangerThresh = cfg.dangerAlarmThreshold or 0.75
    if gripAlarmNow >= dangerThresh then
      recordHardEvent("slide")
    end

    -- OVERSHOOT: zone-gated + SF-line guard + requires learned data.
    -- turnX gate: only fires within cfg.overshootMaxTurnX meters of a turn.
    -- SF guard: skip sp>0.985 / sp<0.015 — crossing at 240+ km/h every lap
    --   while the node avg may still be anchored to early cautious laps.
    do
      local minSpeed = cfg.overshootMinSpeedKmh or 95
      local nearSFLine = (carSP > 0.985 or carSP < 0.015)
      if speedNow >= minSpeed and not nearSFLine then
        local maxTurnX = cfg.overshootMaxTurnX or 80
        local turnXNow = safeNumber(function() return turn and turn.x end, 9999)
        if turnXNow <= maxTurnX then
          local margin = cfg.overshootMarginKmh or 25
          local avg = tonumber(nodeC.speedAvg or 0) or 0
          local samples = tonumber(nodeC.speedSamples or 0) or 0
          if avg > 0 and samples >= (cfg.overshootMinSamples or 8) then
            if speedNow > (avg + margin) then
              recordHardEvent("overshoot")
            end
          end
        end
      end
    end

    -- OFFTRACK method 1: offTrackTime (if isOffTrack signal ever becomes available)
    do
      local sec = cfg.offTrackConfirmSec or 0.4
      if (d.offTrackTime or 0) >= sec and speedNow > 40 then
        recordHardEvent("offtrack")
      end
    end

    -- OFFTRACK method 2: spline stall — car has speed but spline not advancing
    -- (stuck in gravel/grass, or beached against a wall)
    do
      local sp = safeNumber(function() return car.splinePosition end, nil)
      if sp ~= nil and speedNow > 35 and speedNow < 120 then
        local lastSP2 = d._offtrackLastSP
        if lastSP2 ~= nil and dt and dt > 0 then
          local raw2 = sp - lastSP2
          if raw2 >  0.5 then raw2 = raw2 - 1.0 end
          if raw2 < -0.5 then raw2 = raw2 + 1.0 end
          local advance = raw2 / dt
          d._offtrackSplineSpeed = smoothTowards(d._offtrackSplineSpeed or advance, advance, 3.0, dt)
          if (d._offtrackSplineSpeed or 0) < 0.0008 and (d.offTrackTime or 0) == 0 then
            d._splineStallTime = (d._splineStallTime or 0) + dt
            if d._splineStallTime > (cfg.offTrackConfirmSec or 0.4) then
              recordHardEvent("offtrack")
              d._splineStallTime = 0
            end
          else
            d._splineStallTime = 0
          end
        end
        d._offtrackLastSP = sp
      else
        d._splineStallTime = 0
      end
    end

    -- IMPACT: sharp speed drop + low yaw = wall hit (not a spin)
    -- Spin decel caught by slide detector; this targets straight-line wall impacts
    do
      local speedDrop = (d.lastSpeed or speedNow) - speedNow
      local yawNow = 0.0
      do
        local ok, av = pcall(function() return car.angularVelocity end)
        if ok and av ~= nil then
          local ok2, yv = pcall(function() return av.y end)
          if ok2 and type(yv) == "number" then yawNow = math.abs(yv) end
        end
      end
      if speedDrop > (cfg.crashSpeedDropKmh or 40)
        and speedNow > 20
        and yawNow < 1.0 then
        recordHardEvent("impact")
      end
      d.lastSpeed = speedNow
    end

    -- ===== Clean pass reinforcement =====
    -- perCarLapKey: per-car per-corner gate for speed sampling (once per car per lap)
    -- nodeC.decayLap: node-level gate for danger/bias decay (once per real lap total)
    -- Without these separate gates, 20 cars each trigger decay every lap,
    -- wiping danger instantly and inflating sample counts ~20x.
    local perCarLapKey = "lastLap_" .. tostring(cornerKeyC)
    if (d[perCarLapKey] or -1) ~= lapNow then
      d[perCarLapKey] = lapNow

      local currentSpeed = speedNow
      do
        local prevAvg = tonumber(nodeC.speedAvg or 0) or 0
        local prevN   = tonumber(nodeC.speedSamples or 0) or 0
        local newN    = prevN + 1
        local minAlpha = cfg.speedAvgMinAlpha or 0.02
        local alpha    = math.max(minAlpha, 1.0 / newN)
        if prevAvg <= 0 then
          nodeC.speedAvg = currentSpeed
        else
          nodeC.speedAvg = prevAvg + alpha * (currentSpeed - prevAvg)
        end
        nodeC.speedSamples = newN
      end

      local isClean = (gripAlarmNow < 0.3) and ((d.offTrackTime or 0) == 0)
      if isClean and (nodeC.decayLap or -1) ~= lapNow then
        nodeC.decayLap = lapNow
        nodeC._eventsSinceClean = 0

        if (nodeC.danger or 0) > 0 then
          nodeC.danger = math.max(0, (nodeC.danger or 0) - (cfg.dangerDecayPerClean or 0.35))
          markMemoryDirty()
        end

        if (nodeC.brakeBias or 0) > 0 then
          nodeC.brakeBias = math.max(0, (nodeC.brakeBias or 0) - (cfg.brakeBiasDecayPerClean or 0.015))
          markMemoryDirty()
        end

        if (nodeC.improvePenalty or 0) > 0 then
          nodeC.improvePenalty = math.max(0, (nodeC.improvePenalty or 0) - 1.0)
        end

        if (nodeC.entryCapKmh or 0) > 0 then
          local target = math.min(
            (nodeC.speedAvg or currentSpeed) + (cfg.entryCapHeadroomKmh or 8),
            cfg.entryCapMaxKmh or 9999
          )
          nodeC.entryCapKmh = math.min(target, (nodeC.entryCapKmh or 0) + (cfg.entryCapLearnUpKmhPerClean or 2.0))
          markMemoryDirty()
        end

        local approxCars = math.max(1, tonumber(sim and sim.carsCount or 1) - 1)
        local approxRealLaps = math.floor((nodeC.speedSamples or 0) / approxCars)
        if (cfg.cornerLockEnabled ~= false)
          and approxRealLaps >= (cfg.cornerLockCleanStreak or 80)
          and (nodeC.speedSamples or 0) >= (cfg.cornerLockMinSamples or 60)
          and (nodeC.danger or 0) == 0 then
          nodeC.locked = true
        end
      end
    end
  end
end

-- ✅ NEW: time-based danger decay (uses cfg.dangerDecayPerSecond)
-- Keeps danger from lasting forever when clean passes aren't being awarded.
do
  if nodeC and (nodeC.danger or 0) > 0 and (not nodeC.dangerFrozen) then
    local decaySec = tonumber(cfg.dangerDecayPerSecond or 0) or 0
    if decaySec > 0 then
      local before = nodeC.danger or 0
      nodeC.danger = math.max(0, before - decaySec * (dt or 0.016))

      -- Only mark dirty if something actually changed meaningfully
      if nodeC.danger ~= before then
        markMemoryDirty()
      end
    end
  end
end

-- ==========================================================
-- ✅ STUCK BEHIND → IMPATIENCE + STRAIGHT DRAFT PASS INTENT
-- Hardcoded: if stuck behind a car, driver behind ramps aggression/push.
-- Straights: drafting attempts feel intentional (commit/abort).
-- ==========================================================
do
  d.draft = d.draft or { targetIdx=nil, behindTime=0.0, stuckRamp=0.0, state="follow", stateTimer=0.0, cooldown=0.0 }

  local speed = car.speedKmh or 0
  local steerAbs = 0.0
  do
    local okS, s = pcall(function() return car.controls and car.controls.steer end)
    if okS and type(s) == "number" then steerAbs = math.abs(s) end
  end

  local isStraight = (steerAbs < 0.06) and (speed > 120)

  -- Drafting window (spline gap). Your clean-air threshold uses 0.06,
  -- so drafting should be well below that.
  local gap = aheadGap or 1.0
  local hasTarget = (aheadCar ~= nil and aheadIdx ~= nil and gap > 0.001)

  -- Convert relSpeed meaning:
  -- getAheadInfo returns mySpeed - aheadSpeed. If positive, I'm faster.
  local rel = relSpeed or 0.0

  -- Follow distance that counts as "stuck behind"
  local stuckGapMax = cfg.stuckBehindGapMax or 0.030  -- ~3% of lap
  local stuckGapMin = cfg.stuckBehindGapMin or 0.004  -- too close = bump risk, ignore
  local draftGapMax = cfg.draftGapMax or 0.020        -- "in the tow" window
  local draftGapMin = cfg.draftGapMin or 0.003

  local dtLocal = dt or 0.016

  -- Tick cooldown
  d.draft.cooldown = math.max(0.0, (d.draft.cooldown or 0.0) - dtLocal)

  -- Track time behind SAME target
  if hasTarget and aheadIdx == d.draft.targetIdx and gap < stuckGapMax then
    d.draft.behindTime = (d.draft.behindTime or 0.0) + dtLocal
  else
    -- New target or not close: reset
    d.draft.targetIdx  = hasTarget and aheadIdx or nil
    d.draft.behindTime = 0.0
    d.draft.stuckRamp  = (d.draft.stuckRamp or 0.0) * 0.85 -- decay instead of hard reset
    d.draft.state      = "follow"
    d.draft.stateTimer = 0.0
  end

  -- Build stuck ramp if close but not easily passing
  if hasTarget and gap < stuckGapMax and gap > stuckGapMin then
    -- If we're not much faster than the car ahead, it feels "stuck"
    local notClosing = (rel < (cfg.stuckBehindRelSpeedGate or 2.0))
    if notClosing then
      local t = math.max(0.0, (d.draft.behindTime or 0.0) - (cfg.stuckBehindDelay or 2.0))
      local ramp = clamp(t / (cfg.stuckBehindRampTime or 10.0), 0.0, 1.0)
      -- Smooth it in
      d.draft.stuckRamp = smoothTowards(d.draft.stuckRamp or 0.0, ramp, 2.5, dtLocal)
    else
      -- If we’re clearly faster, impatience decays (they’ll pass naturally)
      d.draft.stuckRamp = (d.draft.stuckRamp or 0.0) * 0.97
    end
  else
    d.draft.stuckRamp = (d.draft.stuckRamp or 0.0) * 0.96
  end

  -- Draft conditions
  local inDraftWindow = hasTarget and gap > draftGapMin and gap < draftGapMax and isStraight

  -- State machine: follow → commit → abort → follow (with cooldown)
  local st = d.draft.state or "follow"

-- ✅ Option A: NO PASS segment check (blocks commit passes)
local noPassActive = false
do
  local memNP = getMemory()
  if memNP then
    local tdata = memNP.tracks and memNP.tracks[trackId]
    local turns = tdata and tdata.turns
    local n = turns and turns[currentKey] or nil
    if n and n.noPass then
      local untilLap = tonumber(n.noPassUntilLap or -1) or -1
      if untilLap >= lapCount then
        noPassActive = true
      else
        -- expire it automatically
        n.noPass = false
        n.noPassReason = ""
        n.noPassUntilLap = -1
        markMemoryDirty()
      end
    end
  end
end

  if st == "follow" then
  if d.draft.cooldown <= 0.0
    and inDraftWindow
    and (not noPassActive)
    and (d.draft.stuckRamp or 0.0) > (cfg.draftCommitRampGate or 0.35)
    and rel > (cfg.draftCommitRelSpeedMin or -1.0)
  then
    d.draft.state = "commit"
    d.draft.stateTimer = 0.0
  end

  elseif st == "commit" then
    d.draft.stateTimer = (d.draft.stateTimer or 0.0) + dtLocal

    local commitTime = cfg.draftCommitTime or 2.6

    -- Abort if we leave the straight, fall out of draft, or time expires
    if (not inDraftWindow) or rel < (cfg.draftAbortRelSpeed or -3.0) or d.draft.stateTimer > commitTime then
      d.draft.state = "abort"
      d.draft.stateTimer = 0.0
    end

  elseif st == "abort" then
    d.draft.stateTimer = (d.draft.stateTimer or 0.0) + dtLocal
    local abortTime = cfg.draftAbortTime or 0.9
    if d.draft.stateTimer > abortTime then
      d.draft.state = "follow"
      d.draft.stateTimer = 0.0
      d.draft.cooldown = cfg.draftCooldown or (1.4 + 0.8 * hash01("draftCD|" .. tostring(d.index) .. "|" .. tostring(lapCount)))
    end
  end

  -- ===== Apply modifiers =====
  -- Base "stuck behind" bump (works everywhere, but should be subtle)
  local stuck = clamp(d.draft.stuckRamp or 0.0, 0.0, 1.0)

  -- Scale by driver class (Attack benefits most, Chill least)
  local classMul = (class == "attack") and 1.00 or (class == "normal" and 0.75 or 0.55)

  -- Lap 1: suppress fighting + boost pace, both taper off over first 30% of lap 2
  local lap1FightMul  = 1.0
  local lap1PaceBoost = 0.0
  do
    local suppressBase = cfg.lap1SuppressBase or 0.08
    local rampFrac     = cfg.lap1RampFrac     or 0.30
    local paceBoost    = cfg.lap1PaceBoost    or 0.05
    if lapCount <= 0 then
      lap1FightMul  = suppressBase
      lap1PaceBoost = paceBoost
    elseif lapCount == 1 then
      local sp = safeNumber(function() return car.splinePosition end, 0)
      local ramp = clamp(sp / rampFrac, 0.0, 1.0)
      lap1FightMul  = lerp(suppressBase, 1.0, ramp)
      lap1PaceBoost = lerp(paceBoost, 0.0, ramp)
    end
  end

  local stuckAgg  = (cfg.stuckBehindAggressionBoost or 0.18) * stuck * classMul * lap1FightMul
  local stuckPush = (cfg.stuckBehindPushBoost or 0.020) * stuck * classMul * lap1FightMul

  -- Commit pass: stronger but ONLY on straights in draft window
  local commitAgg = 0.0
  local commitPush = 0.0
  local commitTS = 0.0

  if d.draft.state == "commit" then
    commitAgg  = (cfg.draftCommitAggBoost or 0.22)  * classMul * lap1FightMul
    commitPush = (cfg.draftCommitPushBoost or 0.050) * classMul * lap1FightMul
    commitTS   = (cfg.draftCommitTopSpeedBoost or 0.010) * classMul * lap1FightMul
  end

  -- Abort: slight re-tuck (prevents oscillation / constant sending)
  local abortPush = 0.0
  if d.draft.state == "abort" then
    abortPush = (cfg.draftAbortPushPenalty or 0.020) * classMul
  end

  -- Apply to your target knobs
  -- Aggression → mostly throttle/level + slightly later braking (careful!)
  -- NOTE: you do not have a per-driver aggression hint variable in this file (that’s in UI),
  -- so we approximate "more aggressive" via throttle/level/topSpeed + a tiny brakeHint reduction.
  targetThrottle = clamp(targetThrottle + (stuckPush + commitPush - abortPush), 0.70, 1.20)
  targetLevel    = clamp(targetLevel    + (stuckPush * 0.6 + commitPush * 0.5) + lap1PaceBoost, 0.80, 1.90)
  targetTopSpeed = targetTopSpeed * (1.0 + commitTS)

  -- Make them slightly "braver" on commit and when highly stuck, but keep it safe:
  local brakeBravery = (cfg.stuckBehindBrakeGain or 0.004) * stuck * classMul * lap1FightMul
  local commitBrake  = (cfg.draftCommitBrakeGain or 0.006) * (d.draft.state == "commit" and 1.0 or 0.0) * lap1FightMul
  d.brakeHint = d.brakeHint * (1.0 - brakeBravery - commitBrake)
end

-- ==========================================================
-- ✅ Blue Flag (lap-based)
-- If a lapping car is close behind, yield safely (lift + earlier braking)
-- Works in single-class AND multiclass (not gated)
--
-- NOTE:
--   In multiclass races, we already have tier-based YIELD/PUSH for same-lap traffic.
--   To avoid double-lifting, we skip lap-blueflag effects if a faster-tier car is
--   currently behind (same-lap) and would already trigger yield behavior.
-- ==========================================================
do
  local isBlue, gap, _lappingCar = getBlueFlagState(d.index, car)
  if isBlue then
    local apply = true

    if cfg.multiclassEnabled then
      local myTier = tonumber(d.classTier or 1) or 1
      local fasterBehind = findFasterCarBehind(sim, d, cfg.multiclassYieldDistM or 55)
      if fasterBehind and fasterBehind.driver then
        local behindTier = tonumber(fasterBehind.driver.classTier or 1) or 1
        if behindTier < myTier then
          apply = false
        end
      end
    end

    if apply then
      local closeness = clamp(1.0 - (gap / 0.06), 0.0, 1.0)
      targetThrottle = clamp(targetThrottle * (1.0 - 0.18 * closeness), 0.65, 1.15)
      d.brakeHint    = d.brakeHint * (1.0 + 0.12 * closeness)
      targetLevel    = clamp(targetLevel * (1.0 - 0.03 * closeness), 0.80, 1.75)
    end
  end
end

-- ===== Breakaway timer: give a short push after completing a pass =====
do
  local rp = safeNumber(function() return car.racePosition end)
  if rp then
    if d.lastRacePos and rp < d.lastRacePos then
      -- Gained position since last frame = likely completed an overtake
      d.breakawayTimer = 4.0
    end
    d.lastRacePos = rp
  end
  d.breakawayTimer = math.max(0.0, (d.breakawayTimer or 0.0) - dt)
end

-- ==========================================================
-- ✅ Hunt trigger: if driver gets passed, they may hunt later
-- Not instant revenge — delayed claw-back if target still visible.
-- ==========================================================
do
  local rp = safeNumber(function() return car.racePosition end)

  -- init safety
  d.huntLastPos    = d.huntLastPos or rp
  d.gotPassedTimer = d.gotPassedTimer or 0.0
  d.huntTimer      = d.huntTimer or 0.0
  d.huntCooldown   = d.huntCooldown or 0.0

  -- tick timers
  d.huntCooldown   = math.max(0.0, d.huntCooldown - dt)
  d.gotPassedTimer = math.max(0.0, d.gotPassedTimer - dt)
  d.huntTimer      = math.max(0.0, d.huntTimer - dt)

  if rp ~= nil and d.huntLastPos ~= nil then
    -- If race position number increased, they LOST a place (got passed)
    if rp > d.huntLastPos then
      -- Start a delayed "anger building" window
      d.gotPassedTimer = cfg.huntDelay or 45.0   -- 45s default
    end
    d.huntLastPos = rp
  end

  -- If we’re in the delay window and cooldown is clear, check if target is still close ahead.
  -- (this block fires ONCE when delay expires)
  if d.gotPassedTimer > 0.0 and d.huntCooldown <= 0.0 and d.huntTimer <= 0.0 then
    -- When gotPassedTimer is about to finish, we decide whether to hunt
    if d.gotPassedTimer < dt + 0.02 then

      local minGap = cfg.huntMinGap or 0.015
      local maxGap = cfg.huntMaxGap or 0.045

      -- Condition: someone is ahead and still within range
      if aheadCar and aheadGap and aheadGap > minGap and aheadGap < maxGap then

        -- EXTRA POLISH: don’t trigger hunt if they’re currently side-by-side / actively fighting.
        local sideCount, _ = getSideBySideFactor(d.index, car)
        if not sideCount or sideCount <= 0 then

          local chance = cfg.huntChance or 0.65
          local roll = hash01("hunt|" .. tostring(d.index) .. "|" .. tostring(lapCount) .. "|" .. tostring(sessionIndex))

          if roll < chance then
            d.huntTimer = cfg.huntDuration or 35.0

            local cdMin = cfg.huntCooldownMin or 120.0
            local cdMax = cfg.huntCooldownMax or 260.0
            local cdRoll = hash01("huntCD2|" .. tostring(d.index) .. "|" .. tostring(lapCount))
            d.huntCooldown = cdMin + (cdMax - cdMin) * cdRoll
          end

        end -- side-by-side gate
      end -- ahead gap window
    end -- delay expiring
  end -- delay window active
end -- hunt trigger block

-- ✅ Apply breakaway boost (short push after an overtake)
do
 local t = d.breakawayTimer or 0.0
  -- Don't apply breakaway boost if currently at a danger corner
  local breakawayAtDanger = node
    and (not ((node.dangerFrozen == true) or (node.locked == true)))
    and (tonumber(node.danger or 0) or 0) > (cfg.dangerCap or 12) * 0.5
  if t > 0.0 and not breakawayAtDanger then

    local dur = cfg.breakawayDuration or 4.0         -- seconds

    local baseAmpThrottle = cfg.breakawayThrottleBoost or 0.06
    local baseAmpLevel    = cfg.breakawayLevelBoost or 0.03
    local baseAmpTopSpeed = cfg.breakawayTopSpeedBoost or 0.012 -- ✅ NEW (1.2%)

    -- ✅ Wire up overtakeNorm (intensity scales it)
    local overtakeMul =
      (cfg.overtakeBoostMultiplier or 0.60) +
      (cfg.overtakeBoostMultiplierRange or 0.80) * overtakeNorm
    -- Example: 0.60..1.40 by default

    local ampThrottle = baseAmpThrottle * overtakeMul
    local ampLevel    = baseAmpLevel    * overtakeMul
    local ampTopSpeed = baseAmpTopSpeed * overtakeMul

    local k = clamp(t / dur, 0.0, 1.0) -- 1 right after pass, fades to 0
    k = k * k                          -- smooth falloff (front-loaded)

    targetThrottle = clamp(targetThrottle + ampThrottle * k, 0.70, 1.15)
    targetLevel    = clamp(targetLevel    + ampLevel    * k, 0.80, 1.90)

    -- ✅ NEW: breakaway top-speed confidence
    targetTopSpeed = targetTopSpeed * (1.0 + ampTopSpeed * k)
  end
end

-- Approx clean-air heuristic:
-- clean air only if no car close ahead AND not side-by-side.
-- (Ignore cars behind: clean-air boost can still apply even if someone is drafting.)
local sideCount, sideMinDiff = getSideBySideFactor(d.index, car)

local cleanAhead = (not aheadCar) or (aheadGap > (cfg.cleanAirAheadGap or 0.08))
local inCleanAir = cleanAhead and ((sideCount or 0) == 0)

-- ✅ Clean-air confidence: slightly more top speed + slightly more stability.
-- (Does NOT modify traffic behavior.)
if inCleanAir then
  local cleanAirTS = cfg.cleanAirTopSpeedBoost or 0.010  -- 1.0% default
  local cleanAirMul = 1.0 + cleanAirTS * topSpeedNorm
  targetTopSpeed = targetTopSpeed * cleanAirMul

  -- Tiny consistency bump: reduce throttle wobble + increase confidence.
  local cleanPush = cfg.cleanAirPushBoost or 0.010
  targetThrottle = clamp(targetThrottle + cleanPush * (0.6 + 0.4 * topSpeedNorm), 0.70, 1.20)

  -- Keep them smooth: slightly earlier braking (opposite of aggression) to reduce mistakes when alone
  local cleanBrakeSafety = cfg.cleanAirBrakeSafety or 0.004
  d.brakeHint = applyBrakeHintMul(d.brakeHint, (1.0 + cleanBrakeSafety * (1.0 - pushNorm)), cfg)
end

-- Safety governor: if this corner is highly dangerous, don’t allow “racecraft bravery” to push through it.
if node and (not cfg.disableDangerMemory) then
  local frozen = (node.dangerFrozen == true) or (node.locked == true)
  local danger = (not frozen) and (tonumber(node.danger or 0) or 0) or 0.0
  local cap = (cfg.dangerCap or 12)
  local v = (cap > 0) and (danger / cap) or 0

  if v >= (cfg.safetyGovernorDangerGate or 0.75) then
    -- Clamp the most dangerous outcomes: touching/spinning from fighting mid-corner
    targetThrottle = math.min(targetThrottle, cfg.safetyGovernorMaxThrottle or 1.02)
    targetTopSpeed = math.min(targetTopSpeed, cfg.safetyGovernorMaxTopSpeed or 1.01)

    -- Encourage earlier braking a bit more
    d.brakeHint = applyBrakeHintMul(d.brakeHint, (1.0 + (cfg.safetyGovernorBrakeGain or 0.10)), cfg)
  end
end

-- ✅ PROBE: what we're about to APPLY into CSP this frame
do
  local pr = M._implProbe[d.index]
  if pr then
    pr.brakeHint      = d.brakeHint
    pr.targetThrottle = targetThrottle
    pr.targetTopSpeed = targetTopSpeed
    pr.targetLevel    = targetLevel
    pr.learningEnabled = (cfg and cfg.learningEnabled ~= false)
    pr.approachSpeed  = d.approachSpeed or 0
    pr.capKmh         = (d.approachSpeed or 0) > 60 and (d.approachSpeed * targetTopSpeed) or 300
    pr.cornerKey      = d._cornerKey
    pr.danger         = node and (node.danger or 0) or 0
    pr.frozen         = node and ((node.dangerFrozen == true) or (node.locked == true)) or false

    -- Learning status diagnostic (written once per bucket change, not every frame)
    local nodeOK = (node ~= nil)
    local status
    if pr.learningEnabled == false then
      status = "DISABLED"
    elseif not nodeOK then
      status = "NO_NODE"
    elseif pr.frozen then
      status = "STANDBY_FROZEN"
    elseif (pr.danger or 0) > 0 then
      status = "ACTIVE"
    else
      status = "STANDBY_CLEAN"
    end

  end
end

-- Track approach speed using spline position.
-- High-water mark between buckets, resets once per bucket crossing.
do
  local speedNow = tonumber(car.speedKmh) or 0
  if d._lastApproachBucket ~= currentBucket then
    d._lastApproachBucket = currentBucket
    d.approachSpeed = speedNow
  else
    d.approachSpeed = math.max(d.approachSpeed or 0, speedNow)
  end
end
local refKmh = (d.approachSpeed or 0) > 60 and d.approachSpeed or 300

  -- ==========================================================
  -- ✅ FINAL SANITY CLAMPS (no learning enforcement here)
  -- ==========================================================
  -- Keep values in safe bounds, but do NOT override behaviour based on learned data.
  targetThrottle = math.clamp(targetThrottle, 0.0, 1.0)
  targetLevel    = math.clamp(targetLevel,    0.0, 1.0)
  d.brakeHint    = math.clamp(d.brakeHint or 0.0, 0.0, 1.0)

-- ✅ APPLY TARGETS TO CSP / PHYSICS
-- ==========================================================

-- Compute learned cap safely
local learnedCap = 0
local dangerForForce = 0
if (cfg.learningEnabled ~= false) and node then
  local isFrozen = (node.dangerFrozen == true) or (node.locked == true)
  if not isFrozen then
    learnedCap     = tonumber(node.entryCapKmh or 0) or 0
    dangerForForce = tonumber(node.danger or 0) or 0
  end
end

-- ==========================================================
-- EARLY APPROACH CAP
-- For high-danger corners, extend the cap window well upstream
-- so the AI starts shedding speed before the braking zone,
-- not after arriving already 50+ km/h too fast.
--
-- dangerNorm 0..1 scales how far back the window opens:
--   low danger  → 220m (original)
--   full danger → cfg.earlyCapWindowM (default 450m)
-- ==========================================================
local dangerNorm = 0.0
if dangerForForce > 0 then
  dangerNorm = math.min(dangerForForce / math.max(tonumber(cfg.dangerCap or 12), 1), 1.0)
end

local earlyCapWindowM = tonumber(cfg.earlyCapWindowM or 450) or 450
local capWindowM = 220 + (earlyCapWindowM - 220) * dangerNorm

-- Scan forward up to earlyCapWindowM for the nearest hot bucket.
local aheadDistM = earlyCapWindowM + 1  -- sentinel
local aheadLearnedCap = learnedCap
local aheadDangerNorm = dangerNorm
do
  if (cfg.learningEnabled ~= false) and mem and trackId then
    local tdata = mem.tracks and mem.tracks[trackId]
    local turns = tdata and tdata.turns
    local trackLenM = safeNumber(function() return sim.trackLengthM end, 5000)
    if turns then
      for key, n in pairs(turns) do
        local frozen = (n.dangerFrozen == true) or (n.locked == true)
        local d2 = (not frozen) and (tonumber(n.danger or 0) or 0) or 0
        local cap2 = tonumber(n.entryCapKmh or 0) or 0
        if d2 >= (cfg.dangerZoneThreshold or 3.0) and cap2 > 0 then
          local nb = tonumber(key:match("spline_(%d+)"))
          if nb then
            local bsp = nb / bucketCount
            local fwd = bsp - carSP
            if fwd < 0 then fwd = fwd + 1.0 end
            local distM = fwd * trackLenM
            if distM < aheadDistM then
              aheadDistM = distM
              aheadLearnedCap = cap2
              aheadDangerNorm = math.min(d2 / math.max(tonumber(cfg.dangerCap or 12), 1), 1.0)
            end
          end
        end
      end
    end
  end
end

local capKmh
-- Only enforce entryCapKmh when the corner has active danger.
-- A corner with danger=0 is considered recovered — cap is ignored so cars
-- aren't permanently restricted by old incidents that have since cleared.
if aheadLearnedCap > 0 and aheadDangerNorm > 0 and aheadDistM <= earlyCapWindowM then
  local multiplierCap = refKmh * targetTopSpeed
  local approachT = clamp(1.0 - (aheadDistM / earlyCapWindowM), 0.0, 1.0)
  approachT = approachT * approachT  -- ease-in
  local blendedCap = multiplierCap + (aheadLearnedCap - multiplierCap) * approachT * aheadDangerNorm
  capKmh = math.max(blendedCap, aheadLearnedCap * approachT * aheadDangerNorm)
else
  capKmh = refKmh * targetTopSpeed
end

if physics then
  local rollingActive = (cfg and cfg._rollingStartActive == true)

  if not rollingActive then
    pcall(physics.setAIThrottleLimit, idx, targetThrottle)
    pcall(physics.setAILevel, idx, targetLevel)
    pcall(physics.setAIBrakeHint, idx, d.brakeHint or 0)
    pcall(physics.setAITopSpeed, idx, capKmh)

    local speedNow = tonumber(car.speedKmh) or 0

    -- ==========================================================
    -- EARLY ADDFORCE BRAKING
    -- Original: only fires inside 80m. Problem: at 157 km/h the
    -- car needs 150-200m to lose 50+ km/h. Extended to start at
    -- cfg.earlyForceWindowM (default 200m) for dangerous corners,
    -- with force ramping up as the car gets closer and stays over cap.
    -- ==========================================================
    local earlyForceWindowM = tonumber(cfg.earlyForceWindowM or 200) or 200
    -- Scale window by danger: low danger keeps 80m, full danger reaches earlyForceWindowM
    local forceWindowM = 80 + (earlyForceWindowM - 80) * dangerNorm
    if type(physics.addForce) == "function" then
      if dangerForForce > 0 and aheadDangerNorm > 0 and aheadDistM <= forceWindowM and learnedCap > 0 and speedNow > learnedCap then
        local excess = speedNow - learnedCap

        local distRamp = clamp(1.0 - (aheadDistM / forceWindowM), 0.0, 1.0)
        distRamp = 0.30 + 0.70 * distRamp

        local forceScale = math.min(excess / 40.0, 1.0) * dangerNorm * distRamp
        if forceScale > 0.05 then
          pcall(physics.addForce, idx, vec3(0, 0, 0), true,
                vec3(0, 0, -12000 * forceScale), true)
        else
          pcall(physics.addForce, idx, vec3(0, 0, 0), true, vec3(0, 0, 0), true)
        end
      else
        pcall(physics.addForce, idx, vec3(0, 0, 0), true, vec3(0, 0, 0), true)
      end
    end
  end
end
end
end
end

return M