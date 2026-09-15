-- src/caution.lua
-- RaceFlow Caution System (FCY + Sector Yellow) - v0.6.0
-- Port of the caution CORE from fcy_yellow_rollingstart by Nary
-- (formation lap + track-file physics hack were NOT ported on purpose).
--
-- Design rules (anti-regression):
--  * 100% local scope, returns M (zero globals).
--  * All physics calls via pcall; requires physics scripting, but NEVER
--    writes to track files (unlike the original EnablePhysics).
--  * Runs from script.update via M.update (never from a window callback).
--  * Only touches AI cars that need capping; releases on deactivate.
--  * Player gets HUD messages only (no speed enforcement).
--  * Disabled by default (cfg.caution.enabled).

local M = {}

local state = {
  mode = nil,            -- nil | "FCY" | "YELLOW"
  timer = 0,
  duration = 0,
  sector = 0,            -- incident sector while YELLOW
  reason = "",
  cooldown = 0,
  stoppedCars = {},      -- [carIndex] = seconds stopped
  capped = {},           -- [carIndex] = true while WE hold its cap
  readyWarned = false,
  physMissingLogged = false,
}

local function ensureConfig(cfg)
  cfg.caution = cfg.caution or {}
  local c = cfg.caution
  c.enabled = (c.enabled == true)                 -- default OFF (safe)
  c.fcySpeedKmh = tonumber(c.fcySpeedKmh or 80) or 80
  c.yellowSpeedKmh = tonumber(c.yellowSpeedKmh or 80) or 80
  c.minDuration = tonumber(c.minDuration or 60) or 60
  c.maxDuration = tonumber(c.maxDuration or 180) or 180
  if c.maxDuration < c.minDuration then c.maxDuration = c.minDuration end
  c.fcyChance = tonumber(c.fcyChance or 0.5) or 0.5
  if c.fcyChance < 0 then c.fcyChance = 0 end
  if c.fcyChance > 1 then c.fcyChance = 1 end
  c.autoTrigger = (c.autoTrigger ~= false)        -- auto on stopped AI
  c.minDrivenKm = tonumber(c.minDrivenKm or 0.5) or 0.5
  c.cooldown = tonumber(c.cooldown or 10) or 10
end

local function physicsOk(sim, cfg)
  if physics and type(physics.setAITopSpeed) == "function" then return true end
  if not state.physMissingLogged then
    state.physMissingLogged = true
    ac.log("[RaceFlow Caution] physics scripting unavailable; caution system idle (enable per-track physics scripting)")
  end
  return false
end

local function say(title, text)
  if ac and ac.setMessage then pcall(ac.setMessage, title, text) end
end

local function capCar(i, kmh)
  if pcall(physics.setAITopSpeed, i, kmh) then
    state.capped[i] = true
  end
end

local function releaseCar(i)
  if state.capped[i] then
    state.capped[i] = nil
    pcall(physics.setAITopSpeed, i, 1e9)
  end
end

local function releaseAll()
  for i, _ in pairs(state.capped) do
    pcall(physics.setAITopSpeed, i, 1e9)
  end
  state.capped = {}
end

local function rollDuration(cfg)
  local lo, hi = cfg.caution.minDuration, cfg.caution.maxDuration
  if hi <= lo then return lo end
  return lo + math.random() * (hi - lo)
end

local function activateFCY(cfg, reason)
  state.mode = "FCY"
  state.timer = 0
  state.duration = rollDuration(cfg)
  state.reason = reason or ""
  state.readyWarned = false
  ac.log("[RaceFlow Caution] FCY activated: " .. tostring(reason))
  say("CAUTION: FULL COURSE YELLOW", "No overtaking - max " .. tostring(cfg.caution.fcySpeedKmh) .. " km/h")
end

local function activateYellow(cfg, sector, reason)
  state.mode = "YELLOW"
  state.timer = 0
  state.duration = rollDuration(cfg)
  state.sector = sector or 0
  state.reason = reason or ""
  state.readyWarned = false
  ac.log("[RaceFlow Caution] YELLOW sector " .. tostring(state.sector) .. ": " .. tostring(reason))
  say("YELLOW FLAG - SECTOR " .. tostring(state.sector), "No overtaking in this sector")
end

local function deactivate(sim, greenText)
  releaseAll()
  state.mode = nil
  state.timer = 0
  state.duration = 0
  state.sector = 0
  state.reason = ""
  state.readyWarned = false
  ac.log("[RaceFlow Caution] Green flag")
  say("GREEN FLAG", greenText or "Go go go!")
end

local function inRaceSession(sim)
  -- Gate to race sessions when the API exposes the type; otherwise allow
  -- any started offline session (permissive fallback).
  if sim.raceSessionType ~= nil then
    return sim.raceSessionType == 3
  end
  return true
end

function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted or sim.isOnlineRace then return end
  ensureConfig(cfg)
  if not cfg.caution.enabled then
    if state.mode then deactivate(sim, "Caution system disabled") end
    return
  end
  if not inRaceSession(sim) then
    if state.mode then deactivate(sim, "Not in race session") end
    return
  end
  if not physicsOk(sim, cfg) then
    if state.mode then
      state.mode = nil
      state.capped = {}
    end
    return
  end

  state.cooldown = math.max(0, state.cooldown - dt)
  local carsCount = sim.carsCount or 0

  -- Player must have driven a bit before incidents count (avoids grid false positives)
  local drivenOk = true
  do
    local ok, pcar = pcall(ac.getCar, 0)
    if ok and pcar and pcar.distanceDrivenSessionKm ~= nil then
      drivenOk = (tonumber(pcar.distanceDrivenSessionKm) or 0) > (cfg.caution.minDrivenKm or 0.5)
    end
  end

  -- Incident scan: stopped AI cars outside the pits
  local incidentIdx, incidentSector = nil, nil
  if drivenOk and cfg.caution.autoTrigger then
    for i = 1, carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car and not car.isInPitlane and not car.isInPit then
        local spd = tonumber(car.speedKmh) or 99
        if spd < 1 then
          state.stoppedCars[i] = (state.stoppedCars[i] or 0) + dt
          if state.stoppedCars[i] >= 1.0 and incidentIdx == nil then
            incidentIdx = i
            local okS, sec = pcall(function() return car.currentSector end)
            incidentSector = (okS and tonumber(sec)) or 0
          end
        else
          state.stoppedCars[i] = 0
        end
      else
        state.stoppedCars[i] = 0
      end
    end
  end

  -- Trigger new caution
  if not state.mode and incidentIdx ~= nil and state.cooldown <= 0 then
    local name = ac.getDriverName(incidentIdx) or ("Car #" .. incidentIdx)
    if math.random() <= (cfg.caution.fcyChance or 0.5) then
      activateFCY(cfg, name)
    else
      activateYellow(cfg, incidentSector, name)
    end
  end

  -- Escalation: second incident in ANOTHER sector while YELLOW -> FCY
  if state.mode == "YELLOW" and incidentIdx ~= nil and incidentSector ~= state.sector then
    local name = ac.getDriverName(incidentIdx) or ("Car #" .. incidentIdx)
    releaseAll()
    activateFCY(cfg, name .. " (escalated)")
  end

  -- Apply caps
  if state.mode == "FCY" then
    state.timer = state.timer + dt
    for i = 1, carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car and car.isAIControlled then
        capCar(i, cfg.caution.fcySpeedKmh or 80)
      end
    end
  elseif state.mode == "YELLOW" then
    state.timer = state.timer + dt
    for i = 1, carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car and car.isAIControlled then
        local okS, sec = pcall(function() return car.currentSector end)
        if okS and tonumber(sec) == state.sector then
          capCar(i, cfg.caution.yellowSpeedKmh or 80)
        else
          releaseCar(i) -- outside the sector: leave to AI/strategy caps
        end
      end
    end
  end

  -- Timing / transitions
  if state.mode then
    local left = state.duration - state.timer
    if not state.readyWarned and left <= 10 and left > 0 then
      state.readyWarned = true
      say("GET READY", "Race resumes shortly")
    end
    if state.timer >= state.duration then
      if state.mode == "FCY" then
        state.cooldown = cfg.caution.cooldown or 10
        deactivate(sim, "Green flag - go go go!")
      else -- YELLOW ends: roll FCY encore or resume
        if math.random() <= (cfg.caution.fcyChance or 0.5) then
          releaseAll()
          activateFCY(cfg, "Caution: full course yellow")
        else
          state.cooldown = cfg.caution.cooldown or 10
          deactivate(sim, "Green flag on sector " .. tostring(state.sector))
        end
      end
    end
  end
end

function M.manualTrigger(sim, cfg)
  ensureConfig(cfg)
  if state.mode then
    state.cooldown = cfg.caution.cooldown or 10
    deactivate(sim, "Manually cleared")
  else
    activateFCY(cfg, "Manual trigger")
  end
end

function M.getState()
  return {
    active = state.mode ~= nil,
    mode = state.mode or "-",
    timer = state.timer,
    duration = state.duration,
    sector = state.sector,
    reason = state.reason,
    cooldown = state.cooldown,
  }
end

function M.forceReset(sim)
  releaseAll()
  state.mode = nil
  state.timer = 0
  state.duration = 0
  state.sector = 0
  state.reason = ""
  state.cooldown = 0
  state.stoppedCars = {}
  state.readyWarned = false
end

return M
