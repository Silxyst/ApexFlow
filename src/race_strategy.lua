-- src/race_strategy.lua
-- OPTION 2: Fuel-forcing strategy (no pit request APIs)
-- Forces exactly N stops by capping fuel (virtual tank/stint).
-- AI pits naturally when fuel is low. Stable and CSP-version-agnostic.

local M = {}

-- RARE2_API guard
_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API


-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function ensureState(cfg)
  cfg.strategy = cfg.strategy or {}
  cfg.strategy.enabled = (cfg.strategy.enabled == true)

  cfg.strategy.manualRaceLaps = tonumber(cfg.strategy.manualRaceLaps or 20) or 20
  cfg.strategy.forcedStops = tonumber(cfg.strategy.forcedStops or 1) or 1
  cfg.strategy.forcedStops = clamp(math.floor(cfg.strategy.forcedStops + 0.5), 0, 50)

  -- baked-in stability/safety
  cfg.strategy.reserveLaps = tonumber(cfg.strategy.reserveLaps or 1.2) or 1.2
  cfg.strategy.minRefuelLaps = tonumber(cfg.strategy.minRefuelLaps or 4.0) or 4.0
  cfg.strategy.emergencyFuelLaps = tonumber(cfg.strategy.emergencyFuelLaps or 0.6) or 0.6

  -- How early we begin enforcing the cap before the target pit lap
  cfg.strategy.enforceWindowLaps = tonumber(cfg.strategy.enforceWindowLaps or 1.0) or 1.0

  -- v0.28.2: pneus e combustível ultra-precisos
  cfg.strategy.tireChangeEnabled = (cfg.strategy.tireChangeEnabled ~= false)
  cfg.strategy.tireWearThreshold = tonumber(cfg.strategy.tireWearThreshold or 0.50) or 0.50
  cfg.strategy.adaptiveFuel = (cfg.strategy.adaptiveFuel ~= false) -- aprende consumo real por volta
  cfg.strategy.safetyCarAware = (cfg.strategy.safetyCarAware ~= false) -- ajusta se SC

  cfg._strategy = cfg._strategy or {}
  cfg._strategy.car = cfg._strategy.car or {}
  cfg._strategy.tankMax = cfg._strategy.tankMax or {}
  cfg._strategy.fuelPerLapHist = cfg._strategy.fuelPerLapHist or {} -- histórico por carro
end

local function getCarState(cfg, i)
  local s = cfg._strategy.car[i]
  if s then return s end

  s = {
    lastLap = nil,
    lastFuel = nil,
    fuelPerLap = nil,
    fuelPerLapSamples = 0,

    pitLaps = nil,
    nextPitIdx = 1,

    lastPitLap = -9999,
    refuelDoneThisPit = false,
  }

  cfg._strategy.car[i] = s
  return s
end

local function getMaxTyreWear(car)
  if not car or not car.wheels then return nil end
  local w = car.wheels

  local ok0, v0 = pcall(function() return w[0].tyreWear end)
  local ok1, v1 = pcall(function() return w[1].tyreWear end)
  local ok2, v2 = pcall(function() return w[2].tyreWear end)
  local ok3, v3 = pcall(function() return w[3].tyreWear end)

  if not (ok0 and ok1 and ok2 and ok3) then return nil end
  if v0 == nil or v1 == nil or v2 == nil or v3 == nil then return nil end

  return math.max(v0, v1, v2, v3)
end

local function maybeChangeTyresInPit(cfg, carIndex)
  if not cfg.strategy.tireChangeEnabled then return end
  if not physics or not physics.setAITyres then return end

  local patch = (ac.getPatchVersionCode and ac.getPatchVersionCode()) or 0
  if patch < 2278 then return end

  local ok, car = pcall(ac.getCar, carIndex) if not ok then car = nil end
  if not car then return end

  local wearMax = getMaxTyreWear(car)
  if not wearMax then return end

  -- tyreWear: 0.0 = new, 1.0 = dead
  if wearMax < cfg.strategy.tireWearThreshold then
    return -- not worn enough
  end

  -- If compoundIndex exists, keep same compound but change tyres (most stable).
  -- Some CSP builds interpret setAITyres as selecting a compound, but it still forces a fresh set.
  local okC, comp = pcall(function() return car.compoundIndex end)
  if okC and comp ~= nil then
    pcall(physics.setAITyres, carIndex, comp)
  else
    -- fallback: just request compound 0
    pcall(physics.setAITyres, carIndex, 0)
  end
end

local function setTankEstimate(cfg, carIndex, fuel)
  local old = cfg._strategy.tankMax[carIndex]
  if not old or fuel > old then
    cfg._strategy.tankMax[carIndex] = fuel
  end
end

local function getTankEstimate(cfg, carIndex)
  return cfg._strategy.tankMax[carIndex]
end

local function learnFuelPerLap(st, lap, fuel)
  if st.lastLap == nil then
    st.lastLap = lap
    st.lastFuel = fuel
    return
  end

  local dLap = lap - st.lastLap
  local dFuel = st.lastFuel - fuel

  -- only learn on lap increments
  if dLap >= 1 and dFuel > 0 and dFuel < 25 then
    local est = dFuel / dLap

    if st.fuelPerLap == nil then
      st.fuelPerLap = est
    else
      local alpha = clamp(0.25 / math.max(1, st.fuelPerLapSamples), 0.05, 0.15)
      st.fuelPerLap = lerp(st.fuelPerLap, est, alpha)
    end

    st.fuelPerLapSamples = st.fuelPerLapSamples + 1
  end

  st.lastLap = lap
  st.lastFuel = fuel
end

-- Profile bias: earlier/later pit windows
local function getProfileBias(cfg, carIndex)
  local profile = "normal"

  if cfg._profileForIndex and cfg._profileForIndex[carIndex] then
    profile = tostring(cfg._profileForIndex[carIndex])
  elseif cfg._driverProfileForIndex and cfg._driverProfileForIndex[carIndex] then
    profile = tostring(cfg._driverProfileForIndex[carIndex])
  elseif cfg.driverProfileForIndex and cfg.driverProfileForIndex[carIndex] then
    profile = tostring(cfg.driverProfileForIndex[carIndex])
  end

  profile = string.lower(profile)

  if profile == "chill" then return 0.92 end     -- pits a bit earlier (smaller stint)
  if profile == "attack" or profile == "aggressive" then return 1.08 end -- later
  return 1.00
end

-- v0.10.0: prefer real session laps (auto-detected) over the manual value.
local function raceLaps(cfg)
  local sess = cfg._strategy and cfg._strategy.sessionLaps
  local manual = math.max(3, math.floor((cfg.strategy.manualRaceLaps or 20) + 0.5))
  if sess and sess >= 3 then return sess end
  return manual
end

local function detectSessionLaps(cfg, sim)
  if not sim then return end
  local ok, s = pcall(ac.getSession, sim.currentSessionIndex)
  if not ok or not s then return end
  for _, k in ipairs({"laps", "raceLaps", "totalLaps", "lapCount"}) do
    local okV, v = pcall(function() return s[k] end)
    v = tonumber(v)
    if okV and v and v >= 3 and v <= 5000 then
      if cfg._strategy.sessionLaps ~= v then
        cfg._strategy.sessionLaps = v
        -- invalidate plans built on a different lap count
        for _, st in pairs(cfg._strategy.car) do
          st.pitLaps = nil
          st.nextPitIdx = 1
        end
      end
      return
    end
  end
end

-- Build scheduled pit laps (exactly forcedStops)
local function computePitPlan(cfg, st, carIndex)
  if st.pitLaps ~= nil then return end

  local totalLaps = raceLaps(cfg)
  local stops = cfg.strategy.forcedStops

  st.pitLaps = {}
  st.nextPitIdx = 1

  if stops <= 0 then return end

  -- evenly spaced stops
  local biasMul = getProfileBias(cfg, carIndex) -- affects stint lengths slightly
  for s = 1, stops do
    local baseFrac = s / (stops + 1)
    local lap = math.floor(totalLaps * baseFrac + 0.5)

    -- Apply bias by shifting toward earlier/later around midpoint
    local mid = totalLaps * baseFrac
    local shifted = mid * biasMul
    lap = math.floor(shifted + 0.5)

    lap = clamp(lap, 2, totalLaps - 1)
    local jitter = ((carIndex * 37) % 3) - 1
    lap = clamp(lap + jitter, 2, totalLaps - 1)
    st.pitLaps[#st.pitLaps + 1] = lap
  end

  table.sort(st.pitLaps)

  -- unique increasing
  local uniq, last = {}, -999
  for _, v in ipairs(st.pitLaps) do
    if v ~= last then
      uniq[#uniq + 1] = v
      last = v
    end
  end
  st.pitLaps = uniq
end

-- Set fuel (works for AI if available)
local function setCarFuel(carIndex, liters)
  if physics and physics.setCarFuel then
    pcall(physics.setCarFuel, carIndex, liters)
    return true
  end
  return false
end

-- How many laps of fuel do we currently have?
local function fuelLaps(st, fuel)
  if not st.fuelPerLap or st.fuelPerLap <= 0 then return nil end
  return fuel / st.fuelPerLap
end

-- Enforce fuel so the car MUST pit near its scheduled lap
local function enforceFuelCap(cfg, st, carIndex, lap, fuelNow)
  if not st.pitLaps or st.nextPitIdx > #st.pitLaps then return end
  if not st.fuelPerLap or st.fuelPerLap <= 0 then return end

  local targetLap = st.pitLaps[st.nextPitIdx]
  if not targetLap then return end

  -- Start enforcing a bit before target lap
  local window = cfg.strategy.enforceWindowLaps
  if lap < (targetLap - window) then return end

  -- We want the car to NOT be able to go much past targetLap.
  -- Make max allowed fuel only enough to reach targetLap + small reserve.
  local lapsToTarget = clamp((targetLap - lap) + cfg.strategy.reserveLaps, 0.0, 50.0)
  local maxFuelAllowed = lapsToTarget * st.fuelPerLap

  -- Don’t cap below a small minimum (avoid weird stalls)
  maxFuelAllowed = math.max(maxFuelAllowed, st.fuelPerLap * 0.25)

  -- If it has more fuel than allowed, reduce it
  if fuelNow > maxFuelAllowed + 0.05 then
    setCarFuel(carIndex, maxFuelAllowed)
  end
end

-- Refuel on pit to reach next stop or finish
local function computeRefuelTarget(cfg, st, carIndex, lap, fuelNow)
  local totalLaps = raceLaps(cfg)

  local reachLap = totalLaps
  if st.pitLaps and st.nextPitIdx and (st.nextPitIdx + 1) <= #st.pitLaps then
    reachLap = st.pitLaps[st.nextPitIdx + 1]
  end

  local lapsToGo = clamp(reachLap - lap, 0, totalLaps)
  local needLaps = math.max(lapsToGo + cfg.strategy.reserveLaps, cfg.strategy.minRefuelLaps)

  local tankMax = getTankEstimate(cfg, carIndex) or (fuelNow + 20)

  if not st.fuelPerLap or st.fuelPerLap <= 0 then
    -- no estimate: just add a healthy amount (but not above tankMax)
    return clamp(tankMax, 5, tankMax)
  end

  local targetFuel = needLaps * st.fuelPerLap
  return clamp(targetFuel, 2, tankMax)
end

-- Emergency protection: if it’s about to run out, do NOT cap low
local function shouldDisableCap(cfg, st, fuelNow)
  local lp = fuelLaps(st, fuelNow)
  if not lp then return true end
  return lp < cfg.strategy.emergencyFuelLaps
end

-- ------------------------------------------------------------
-- Public update
-- ------------------------------------------------------------

function M.update(dt, sim, cfg)
  ensureState(cfg)
  if not cfg.strategy.enabled then return end
  if not ac or not ac.getSim or not ac.getCar then return end

  local sim2 = ac.getSim()
  local carsCount = (sim2 and sim2.carsCount) or 0
  if carsCount <= 1 then return end

  detectSessionLaps(cfg, sim2)

  -- v0.10.0: wipe per-car state on session change (avoids ghost rows).
  local sessIdx = sim2.currentSessionIndex or 0
  if cfg._strategy.lastSessionIdx ~= sessIdx then
    cfg._strategy.lastSessionIdx = sessIdx
    cfg._strategy.car = {}
    cfg._strategy.tankMax = {}
  end

  local totalLaps = raceLaps(cfg)

  for i = 1, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i) if not ok then car = nil end
    if car then
      local st = getCarState(cfg, i)

      local lap = tonumber(car.lapCount) or 0
      local fuel = tonumber(car.fuel) or 0

      -- tank estimate from observed max fuel
      setTankEstimate(cfg, i, fuel)

      -- fuel/lap learning
      learnFuelPerLap(st, lap, fuel)

      -- always compute pit plan as soon as possible (works even at lap 0)
      if st.pitLaps == nil then
        computePitPlan(cfg, st, i)
      end

      local inPitlane = (car.isInPitlane == true)
      local inPit = (car.isInPit == true)

      -- Detect pit entry and refuel once per visit
      if inPitlane or inPit then
        if not st.refuelDoneThisPit and lap > st.lastPitLap then
          local targetFuel = computeRefuelTarget(cfg, st, i, lap, fuel)
          setCarFuel(i, targetFuel)

          -- Tires: change if wear exceeds threshold
          maybeChangeTyresInPit(cfg, i)

          st.refuelDoneThisPit = true
          st.lastPitLap = lap

          -- advance stop index if we were due for a stop
          if st.pitLaps and st.nextPitIdx and st.nextPitIdx <= #st.pitLaps then
            st.nextPitIdx = st.nextPitIdx + 1
          end
        end
      else
        st.refuelDoneThisPit = false

        -- Enforce fuel cap to force scheduled stops (unless we're in emergency low-fuel)
        if lap < totalLaps then
          if not shouldDisableCap(cfg, st, fuel) then
            enforceFuelCap(cfg, st, i, lap, fuel)
          end
        end
      end

      -- stop after race ends
      if lap >= totalLaps then
        st.pitLaps = nil
        st.nextPitIdx = 1
      end
    end
  end
end

-- v0.10.0: live monitor for UI (per-AI fuel + next pit).
function M.getState(cfg)
  cfg = cfg or {}
  local out = {
    totalLaps = raceLaps(cfg),
    autoLaps = (cfg._strategy and cfg._strategy.sessionLaps) or nil,
    cars = {},
  }
  if not cfg._strategy or not cfg._strategy.car then return out end
  for i, st in pairs(cfg._strategy.car) do
    local ok, car = pcall(ac.getCar, i)
    local fuel = (ok and car and tonumber(car.fuel)) or 0
    local lap = (ok and car and tonumber(car.lapCount)) or 0
    local nextPit = nil
    if st.pitLaps and st.nextPitIdx and st.nextPitIdx <= #st.pitLaps then
      nextPit = st.pitLaps[st.nextPitIdx]
    end
    out.cars[#out.cars + 1] = {
      index = i,
      lap = lap,
      fuel = fuel,
      fuelPerLap = st.fuelPerLap or 0,
      nextPit = nextPit,
      stopsLeft = (st.pitLaps and (#st.pitLaps - (st.nextPitIdx or 1) + 1)) or 0,
    }
  end
  table.sort(out.cars, function(a, b) return (a.nextPit or 9999) < (b.nextPit or 9999) end)
  return out
end

return M