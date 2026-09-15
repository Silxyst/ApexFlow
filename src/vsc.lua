-- src/vsc.lua
-- Pure Virtual Safety Car (Delta Time Only)
-- No 3D model, no pit spline, no physics.setCarVelocity
-- Lightweight: only setAITopSpeed + setAIThrottleLimit + HUD

local M = {}

-- State
local state = {
  active = false,
  timer = 0,
  reason = "",
  cooldown = 0,
  stoppedCars = {},
  prevYellow = false,
  playerWarned = false,
}

-- Config defaults
local function ensureConfig(cfg)
  cfg.vsc = cfg.vsc or {}
  cfg.vsc.enabled = (cfg.vsc.enabled == true)
  cfg.vsc.deltaKmh = tonumber(cfg.vsc.deltaKmh or 80) or 80
  cfg.vsc.throttleLimit = tonumber(cfg.vsc.throttleLimit or 0.55) or 0.55
  cfg.vsc.minDuration = tonumber(cfg.vsc.minDuration or 10) or 10
  cfg.vsc.triggerThreshold = tonumber(cfg.vsc.triggerThreshold or 2.5) or 2.5
  cfg.vsc.cooldown = tonumber(cfg.vsc.cooldown or 30) or 30
  cfg.vsc.requireYellowClear = (cfg.vsc.requireYellowClear ~= false)
  cfg.vsc.showPlayerDelta = (cfg.vsc.showPlayerDelta ~= false)
end

-- Activate VSC
local function activate(sim, cfg, reason)
  state.active = true
  state.timer = 0
  state.reason = reason
  state.cooldown = cfg.vsc.cooldown or 30
  state.playerWarned = false
  ac.log("[RaceFlow VSC] Activated: " .. reason)
  if ac.setMessage then
    pcall(ac.setMessage, "VSC DEPLOYED", "Virtual Safety Car - Max " .. (cfg.vsc.deltaKmh or 80) .. " km/h")
  end
end

-- Deactivate VSC
local function deactivate(sim, cfg)
  state.active = false
  state.timer = 0
  state.reason = ""
  state.playerWarned = false
  -- Release AI
  for i = 0, (sim.carsCount or 0) - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and car.isAIControlled then
      pcall(physics.setAITopSpeed, i, 1e9)
      pcall(physics.setAIThrottleLimit, i, 1.0)
    end
  end
  ac.log("[RaceFlow VSC] Deactivated")
  if ac.setMessage then
    pcall(ac.setMessage, "VSC ENDED", "Green Flag - Resume Racing!")
  end
end

-- Main update
function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted or sim.isOnlineRace then return end
  ensureConfig(cfg)
  if not cfg.vsc.enabled then
    if state.active then deactivate(sim, cfg) end
    return
  end

  state.cooldown = math.max(0, state.cooldown - dt)
  local carsCount = sim.carsCount or 0
  local yellowNow = (sim.raceFlagType == ac.FlagType.Caution)

  -- Incident detection: stopped cars
  local incidentDetected = false
  local incidentCar = ""
  for i = 0, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and not car.isInPitlane and not car.isInPit then
      local spd = car.speedKmh or 0
      if spd < 8 then
        state.stoppedCars[i] = (state.stoppedCars[i] or 0) + dt
        if state.stoppedCars[i] >= (cfg.vsc.triggerThreshold or 2.5) then
          incidentDetected = true
          incidentCar = ac.getDriverName(i) or ("Car #" .. i)
        end
      else
        state.stoppedCars[i] = math.max(0, (state.stoppedCars[i] or 0) - dt * 2)
      end
    else
      state.stoppedCars[i] = 0
    end
  end

  -- Auto-activate
  if not state.active and incidentDetected and state.cooldown <= 0 then
    activate(sim, cfg, incidentCar)
  end

  if state.active then
    state.timer = state.timer + dt

    -- Apply AI speed cap
    local capKmh = cfg.vsc.deltaKmh or 80
    local throttleLim = cfg.vsc.throttleLimit or 0.55
    for i = 0, carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car and car.isAIControlled then
        pcall(physics.setAITopSpeed, i, capKmh)
        pcall(physics.setAIThrottleLimit, i, throttleLim)
      end
    end

    -- Player delta enforcement (HUD message)
    if cfg.vsc.showPlayerDelta then
      local pcar = ac.getCar(0)
      if pcar and not pcar.isInPitlane then
        local targetMs = (cfg.vsc.deltaKmh or 80) / 3.6
        local currentMs = pcar.speedMs or 0
        local deltaKmh = (currentMs - targetMs) * 3.6
        if deltaKmh > 2.0 and not state.playerWarned then
          state.playerWarned = true
          if ac.setMessage then
            pcall(ac.setMessage, "VSC DELTA", string.format("+%.1f km/h - LIFT!", deltaKmh))
          end
        elseif deltaKmh <= 0.5 then
          state.playerWarned = false
        end
      end
    end

    -- Deactivate conditions
    local minDur = cfg.vsc.minDuration or 10
    local yellowGone = (sim.raceFlagType ~= ac.FlagType.Caution)
    if state.timer >= minDur and (yellowGone or not cfg.vsc.requireYellowClear) and not incidentDetected then
      deactivate(sim, cfg)
    end
  end

  state.prevYellow = yellowNow
end

-- Manual trigger (for UI button)
function M.manualTrigger(sim, cfg)
  ensureConfig(cfg)
  if not state.active then
    activate(sim, cfg, "Manual Trigger")
  else
    deactivate(sim, cfg)
  end
end

-- Get state for UI (cfg passed by caller; falls back to _G config or defaults)
function M.getState(cfg)
  cfg = cfg or (_G.RARE2_CFG or {})
  return {
    active = state.active,
    timer = state.timer,
    reason = state.reason,
    deltaKmh = (cfg.vsc and cfg.vsc.deltaKmh) or 80,
    cooldown = state.cooldown,
  }
end

-- Force reset (session change)
function M.forceReset(sim, cfg)
  if state.active then deactivate(sim, cfg) end
  state.stoppedCars = {}
  state.prevYellow = false
end

return M