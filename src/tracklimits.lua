-- src/tracklimits.lua
-- RaceFlow Track Limits (warnings -> time penalty -> pit-box serving)
-- Port of the CORE from Mavil Track Limit Manager v1.1 by Mavil.
-- NOT ported on purpose: TXT/CSV reports + race-end monitor, random-penalty
-- button, separate AI HUD window, INI system (we use RaceFlow config).
--
-- Anti-regression rules:
--  * 100% local scope, returns M (zero globals; fixes Mavil's
--    player/AI sector mix-up by always using the car's own sector).
--  * physics + ac.addPenaltyTime calls guarded (no-ops where unavailable).
--  * Disabled by default (cfg.tracklimits.enabled).
--  * Runs from script.update via M.update (never from a window).

local M = {}

-- Per-car state (index 0 = player, rest = AI)
local cars = {}
local lastSessionIndex = -1

local function ensureConfig(cfg)
  cfg.tracklimits = cfg.tracklimits or {}
  local t = cfg.tracklimits
  t.enabled = (t.enabled == true)                    -- default OFF (safe)
  t.trackLimitsEnabled = (t.trackLimitsEnabled ~= false)
  t.penaltiesEnabled = (t.penaltiesEnabled ~= false)
  t.maxWarnings = tonumber(t.maxWarnings or 4) or 4
  t.penaltyTime = tonumber(t.penaltyTime or 5) or 5
  t.cooldown = tonumber(t.cooldown or 7) or 7
  t.extraTime = tonumber(t.extraTime or 10) or 10
  t.strictPit = (t.strictPit == true)
  t.waitTime = tonumber(t.waitTime or 1.9) or 1.9
  t.wheels = tonumber(t.wheels or 4) or 4
  if t.wheels < 2 then t.wheels = 2 end
  if t.wheels > 4 then t.wheels = 4 end
  t.aiEnabled = (t.aiEnabled ~= false)
  t.aiServe = (t.aiServe == true)
  t.qualiReset = (t.qualiReset ~= false)             -- teleport reset in quali
  t.finishAdd = (t.finishAdd ~= false)               -- add unserved at finish
end

local function getState(i)
  local s = cars[i]
  if s then return s end
  s = {
    warn = 0, offPrev = false, mustReset = false, lastWarn = -100,
    penaltyActive = false, timeLeft = 0, serving = false,
    waitDone = false, waiting = false, waitTimer = 0,
    exitPending = false, origTime = 0,
    awaitingReset = false, resetAt = 0,
    appliedToResult = false, finishGrace = -1,
    lastPos = nil, wasTeleported = false, wasInPit = false,
    warnsTotal = 0, pensTotal = 0, pensTime = 0,
    lastEvent = "", lastEventLap = -1, lastEventSector = 0,
  }
  cars[i] = s
  return s
end

local function sessionName(sim)
  local ok, n = pcall(ac.getSessionName, sim.currentSessionIndex)
  if ok and n then return tostring(n) end
  return ""
end

local function isQuali(sim)
  return sessionName(sim) == "Qualifying"
end

local function isRace(sim)
  local n = sessionName(sim)
  return n == "Race" or n == "Quick Race"
end

local function isPracticeLike(sim)
  local n = sessionName(sim)
  return n:find("Practice") or n:find("Hotlap") or n:find("Track Day")
      or n:find("Time Attack") or n:find("Drift") or n:find("Drag")
end

local function isPostRace(car, sim)
  if not car then return true end
  if sim.isSessionFinished or sim.raceFlagType == ac.FlagType.Finished then return true end
  local ok, s = pcall(ac.getSession, sim.currentSessionIndex)
  if ok and s and s.isOver then return true end
  if car.isRaceFinished or car.isRetired or car.isConnected == false then return true end
  return false
end

local function canTeleport()
  return physics and physics.allowed and physics.allowed()
      and physics.teleportCarTo and ac.SpawnSet ~= nil
end

local function say(title, text)
  if ac and ac.setMessage then pcall(ac.setMessage, title, text) end
end

local function trackTeleport(i)
  if canTeleport() then
    pcall(physics.teleportCarTo, i, ac.SpawnSet.Pits)
    return true
  end
  return false
end

local function issuePenalty(i, car, cfg, reason)
  local t = cfg.tracklimits
  local s = getState(i)
  s.warn = 0
  if s.penaltyActive then
    s.timeLeft = s.timeLeft + t.penaltyTime
  else
    s.penaltyActive = true
    s.timeLeft = t.penaltyTime
  end
  s.origTime = s.timeLeft
  s.waitDone = false
  s.waiting = false
  s.serving = false
  s.exitPending = false
  s.pensTotal = s.pensTotal + 1
  s.pensTime = s.pensTime + t.penaltyTime
  s.lastEvent = reason or "Too many track limits"
  s.lastEventLap = car.lapCount or 0
  s.lastEventSector = (car.currentSector or 0) + 1
  if i == 0 then
    say("PENALIDADE", string.format("+%ds por track limits (cumpra no box)", t.penaltyTime))
  end
  ac.log(string.format("[RaceFlow TrackLimits] penalty car=%d +%ds (%s)", i, t.penaltyTime, s.lastEvent))
end

local function serveStep(i, car, dt, sim, cfg, needBrake)
  local t = cfg.tracklimits
  local s = getState(i)
  local pen = s.penaltyActive and s.timeLeft > 0
  if not pen then return end

  local inPitlane = car.isInPitlane
  local canServe = (t.strictPit and inPitlane and car.isInPit) or inPitlane
  local stopped = (car.speedKmh or 99) <= 1.0
  local brakeHeld = (car.brake or 0) > 0.7

  -- Track pit exit with unserved penalty -> extra time (Mavil rule)
  if s.wasInPit and not inPitlane and s.timeLeft > 0 then
    s.timeLeft = s.timeLeft + (t.extraTime or 10)
    s.origTime = s.timeLeft
    if i == 0 then say("PENALIDADE", "Não cumprida! +" .. tostring(t.extraTime or 10) .. "s") end
  end
  s.wasInPit = inPitlane

  if isPostRace(car, sim) or s.wasTeleported then
    s.serving = false
    s.waiting = false
    s.waitDone = false
    if car.isAIControlled then
      pcall(physics.setAIThrottleLimit, i, 1.0)
      pcall(physics.setAITopSpeed, i, 1e9)
    end
    return
  end

  if canServe and not s.serving and stopped and (not needBrake or brakeHeld) then
    if not s.waitDone and not s.waiting and (t.waitTime or 0) > 0 then
      s.waiting = true
      s.waitTimer = t.waitTime
      if i == 0 then say("PENALIDADE", "Aguardando pit crew...") end
    elseif s.waitDone or (t.waitTime or 0) == 0 then
      s.serving = true
      if i == 0 then say("PENALIDADE", "Cumprindo: NÃO solte o freio!") end
    end
  end

  if s.waiting then
    s.waitTimer = s.waitTimer - dt
    if s.waitTimer <= 0 then
      s.waiting = false
      s.waitDone = true
      s.serving = true
    end
  end

  if s.serving then
    local holdOk = stopped and (not needBrake or brakeHeld)
    if canServe and holdOk then
      s.timeLeft = math.max(0, s.timeLeft - dt)
      if car.isAIControlled then
        pcall(physics.setAIThrottleLimit, i, 0.0)
        pcall(physics.setAITopSpeed, i, 0.0)
      end
      if s.timeLeft <= 0 then
        s.serving = false
        s.penaltyActive = false
        s.waitDone = false
        s.exitPending = false
        if car.isAIControlled then
          pcall(physics.setAIThrottleLimit, i, 1.0)
          pcall(physics.setAITopSpeed, i, 1e9)
        end
        if i == 0 then say("PENALIDADE", "Cumprida! Boa corrida.") end
        ac.log(string.format("[RaceFlow TrackLimits] penalty served car=%d", i))
      end
    else
      s.serving = false
      if s.penaltyActive and s.timeLeft > 0 then s.exitPending = true end
      if car.isAIControlled then
        pcall(physics.setAIThrottleLimit, i, 1.0)
        pcall(physics.setAITopSpeed, i, 1e9)
      end
    end
  end

  if s.exitPending and canServe and stopped and (not needBrake or brakeHeld) then
    s.exitPending = false
  end
end

local function updateCar(i, car, dt, sim, cfg, isPlayer)
  local t = cfg.tracklimits
  local s = getState(i)
  local now = os.clock()

  -- Teleport guard (anti pit-reset exploit, Mavil technique)
  if s.lastPos then
    local d = (car.position - s.lastPos):length()
    local maxD = (car.speedMs or 0) * dt * 1.5 + 5
    if d > maxD and d > 20 then s.wasTeleported = true end
  end
  if car.position then s.lastPos = car.position end
  if s.wasTeleported and s.wasInPit and not car.isInPitlane then
    s.wasTeleported = false
  end

  -- Practice auto-reset window
  if s.awaitingReset and (now - s.resetAt) > 4.0 then
    s.warn = 0
    s.awaitingReset = false
  end

  if car.isInPitlane or car.isInPit or (car.speedKmh or 0) < 20 then
    -- In pits / too slow: no new detections, and re-arm the edge trigger
    -- (otherwise an off-track exit from pits would never warn again).
    s.offPrev = false
  else
    local wheelsOut = car.wheelsOutside or 0
    local off = wheelsOut >= (t.wheels or 4)
    if t.trackLimitsEnabled and off and not s.offPrev and not s.mustReset
        and (now - s.lastWarn) > (t.cooldown or 7) and not s.awaitingReset then
      s.lastWarn = now
      s.warn = s.warn + 1
      s.warnsTotal = s.warnsTotal + 1
      s.mustReset = true
      s.lastEvent = string.format("Warning %d/%d", s.warn, t.maxWarnings)
      s.lastEventLap = car.lapCount or 0
      s.lastEventSector = (car.currentSector or 0) + 1
      if isPlayer then say("TRACK LIMITS", s.lastEvent) end

      if s.warn >= (t.maxWarnings or 4) then
        if isQuali(sim) then
          s.warn = 0
          if t.qualiReset and trackTeleport(i) then
            s.lastEvent = "Quali reset: sent to pits"
            if isPlayer then say("TRACK LIMITS", "Volta invalidada: boxes!") end
          else
            s.lastEvent = "Quali limit (no teleport rights)"
            if isPlayer then say("TRACK LIMITS", "Limite excedido (sem teleport)") end
          end
        elseif isPracticeLike(sim) then
          s.warn = 0
          s.awaitingReset = true
          s.resetAt = now
          s.lastEvent = "Practice limits: warnings only"
        else
          if t.penaltiesEnabled then
            issuePenalty(i, car, cfg, "Track limits excedido")
          else
            s.warn = 0
            s.awaitingReset = true
            s.resetAt = now
            s.lastEvent = "Penalties disabled in settings"
          end
        end
      end
    end
    if (car.wheelsOutside or 0) == 0 then s.mustReset = false end
    s.offPrev = off
  end

  -- Serving (player needs brake held, AI does not)
  if t.penaltiesEnabled and (isPlayer or (t.aiServe and car.isAIControlled)) then
    serveStep(i, car, dt, sim, cfg, isPlayer)
  end

  -- Unserved penalty at race finish -> race result (guarded API)
  if t.finishAdd and isRace(sim) and s.penaltyActive and s.timeLeft > 0 and not s.appliedToResult then
    if car.isRaceFinished or car.isRetired then
      if s.finishGrace < 0 then s.finishGrace = 2.0 end
    end
    if s.finishGrace >= 0 then
      s.finishGrace = s.finishGrace - dt
      if s.finishGrace < 0 and (car.isRaceFinished or car.isRetired) then
        if ac.addPenaltyTime then
          pcall(ac.addPenaltyTime, i, math.ceil(s.timeLeft))
        end
        if isPlayer then say("UNSERVIDO", string.format("+%ds no resultado final", math.ceil(s.timeLeft))) end
        s.appliedToResult = true
      end
    end
  end
end

function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted or sim.isOnlineRace then return end
  ensureConfig(cfg)
  if not cfg.tracklimits.enabled then return end

  local sessIdx = sim.currentSessionIndex or 0
  if sessIdx ~= lastSessionIndex then
    lastSessionIndex = sessIdx
    cars = {}
  end

  local carsCount = sim.carsCount or 0
  for i = 0, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car then
      local isPlayer = (i == 0)
      if isPlayer or (car.isAIControlled and cfg.tracklimits.aiEnabled) then
        local okU, err = pcall(updateCar, i, car, dt, sim, cfg, isPlayer)
        if not okU then
          ac.log("[RaceFlow TrackLimits] car " .. tostring(i) .. ": " .. tostring(err))
        end
      end
    end
  end
end

-- Public API: other modules (e.g. caution overtake) can issue a time
-- penalty through the standard serving flow. Returns true if queued.
function M.issuePenalty(i, seconds, reason)
  local ok, car = pcall(ac.getCar, i or 0)
  if not ok or not car then return false end
  local secs = tonumber(seconds) or 0
  if secs <= 0 then return false end
  local s = getState(i)
  if s.penaltyActive then
    s.timeLeft = s.timeLeft + secs
  else
    s.penaltyActive = true
    s.timeLeft = secs
  end
  s.origTime = s.timeLeft
  s.waitDone = false
  s.waiting = false
  s.serving = false
  s.exitPending = false
  s.pensTotal = s.pensTotal + 1
  s.pensTime = s.pensTime + secs
  s.lastEvent = reason or "Penalty"
  s.lastEventLap = car.lapCount or 0
  s.lastEventSector = (car.currentSector or 0) + 1
  ac.log(string.format("[RaceFlow TrackLimits] external penalty car=%d +%ds (%s)", i, secs, s.lastEvent))
  return true
end

function M.getState()
  local p = cars[0] or { warn = 0, penaltyActive = false, timeLeft = 0, serving = false, lastEvent = "" }
  local aiWarn, aiPen = 0, 0
  for i, s in pairs(cars) do
    if i ~= 0 then
      if (s.warn or 0) > 0 then aiWarn = aiWarn + 1 end
      if s.penaltyActive then aiPen = aiPen + 1 end
    end
  end
  local t = (_G.RARE2_CFG and _G.RARE2_CFG.tracklimits) or {}
  return {
    warn = p.warn or 0,
    maxWarn = t.maxWarnings or 4,
    penaltyActive = p.penaltyActive or false,
    timeLeft = p.timeLeft or 0,
    serving = p.serving or false,
    lastEvent = p.lastEvent or "",
    aiWithWarnings = aiWarn,
    aiWithPenalties = aiPen,
  }
end

function M.forceReset()
  cars = {}
  lastSessionIndex = -1
end

return M
