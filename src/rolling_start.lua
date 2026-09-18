-- src/rolling_start.lua
-- Rolling Start (integrated + hardened) based on RollingStart.lua v0.81
--
-- PATCH (Dec 2025):
-- 1) Fix leader/FCI detection when sim.sessionTimeLeft is negative (common in lap-based races).
--    Previously, leader/FCI/positions were only computed when sessionTimeLeft >= 1, which can be false
--    for an entire lap-based race, causing state.leader to stay at 0 and the start to never release.
-- 2) Keep throttle-limit gating safe when sessionTimeLeft is negative.

local M = {}

-- APEXFLOW_API guard
_G.APEXFLOW_API = _G.APEXFLOW_API or {}
local APEXFLOW_API = _G.APEXFLOW_API


-- =========================================================
-- Audio (CSP reliable): ui.MediaPlayer one-shot from absolute file path
-- File location: assettocorsa/apps/lua/ApexFlow/sfx/rs_beep.wav
-- =========================================================

local RS_BEEP_REL = "apps/lua/ApexFlow/sfx/rs_beep.wav"
local RS_BEEP_ABS = nil
local RS_BEEP_PLAYER = nil

local function _resolveBeepPath()
  if RS_BEEP_ABS then return RS_BEEP_ABS end

  if ac and ac.getFolder and ac.FolderID then
    local ok, root = pcall(ac.getFolder, ac.FolderID.Root)
    if ok and type(root) == "string" then
      if not root:match("[/\\\\]$") then root = root .. "/" end
      RS_BEEP_ABS = root .. RS_BEEP_REL
      if ac and ac.log then ac.log("[ApexFlow RollingStart] Resolved beep path: " .. tostring(RS_BEEP_ABS)) end
      return RS_BEEP_ABS
    end
  end

  -- fallback: use relative path
  RS_BEEP_ABS = RS_BEEP_REL
  if ac and ac.log then ac.log("[ApexFlow RollingStart] Using RELATIVE beep path (fallback): " .. tostring(RS_BEEP_ABS)) end
  return RS_BEEP_ABS
end

local function _getBeepPlayer()
  if RS_BEEP_PLAYER then return RS_BEEP_PLAYER end
  if not ui or not ui.MediaPlayer then
    if ac and ac.log then ac.log("[ApexFlow RollingStart] ui.MediaPlayer not available") end
    return nil
  end

  local srcPath = _resolveBeepPath()

  local ok, mp = pcall(ui.MediaPlayer, srcPath)
  if ok and mp then
    RS_BEEP_PLAYER = mp
    return RS_BEEP_PLAYER
  end

  return nil
end

local function playBeep()
  local mp = _getBeepPlayer()
  if not mp then return end

  pcall(function()
    if mp.setCurrentTime then mp:setCurrentTime(0) end
    if mp.setVolume then mp:setVolume(10.0) end

    if mp.play then
      mp:play()
    elseif mp.trigger then
      mp:trigger()
    elseif mp.start then
      mp:start()
    end
  end)
end

-- Persistent state (per session)
local state = {
  lastSessionIndex = -1,
  lastCarsCount    = -1,
  warnedMissing    = false,
  activeLastFrame  = false,
  rollingAnnounced = false,
  greenAnnounced   = false,
 
  -- Post-green safety reset window (prevents AI staying capped/slow)
  releaseResetTimer = 0,

  -- Log every frame while rolling; keep logging for a short window after release
  logPostReleaseTimer = 0,

 -- message/side stabilization
  stringSide   = nil,   -- latched side while rolling
  playerStartSide = nil,
  msgSide      = nil,   -- last shown Keep Left/Right
  msgCooldown  = 0,     -- seconds

  PP = 0,
  FR = 0,
  leader = 0,

  Formation = 0,
  TimerF2   = 0,

  OffsetL   = 0,
  OffsetR   = 0,

  -- arrays by car index
  FCI = {},
  Side = {},
  Tgap = {},
  Sgap = {},
  start = {},
  Offset = {},
  LimitSpeed2 = {},
  gridposition = {},
  position = {},
  desiredLane = {},
  
  -- snapshot (lane + order lock during rolling start)
  snapTaken = false,
  snapLane = {},
  snapOrder = {},
  snapRank = {},
  snapFCI = {},

  -- Session-lifetime kill switch: once lap 2 starts, rolling start will never run again
  -- unless the race/session is restarted (sessionIndex changes and state is rebuilt).
  finished = false,
}

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function safeCar(i)
  local ok, car = pcall(ac.getCar, i)
  if ok then return car end
  return nil
end

local function getCarSpeedKmh(i)
  local c = safeCar(i)
  if not c then return 0 end
  return tonumber(c.speedKmh) or 0
end

local function requiredPhysicsOk()
  local phys = (ac and ac.physics) or rawget(_G, "physics")
  return phys
    and type(phys.setAIThrottleLimit) == "function"
    and type(phys.setAITopSpeed) == "function"
    and type(phys.setAISplineOffset) == "function"
    and type(phys.addForce) == "function"
    and type(phys.setAILevel) == "function"
    and type(phys.setAIAggression) == "function"
    and type(phys.setAIBrakeHint) == "function"
end

-- Snapshot lane (left/right) and stable "car ahead" order at the start of rolling phase.
-- Keeps cars from swapping sides or changing pairing due to racePosition jitter.
local function takeSnapshot(carcount)
  state.snapTaken = true
  state.snapLane = {}
  state.snapOrder = {}
  state.snapRank = {}
  state.snapFCI = {}

  -- lane from track x (left/right of racing line)
  for i = 0, carcount do
    local c = safeCar(i)
    if c then
      local okT, tp = pcall(ac.worldCoordinateToTrack, c.position)
      local x = (okT and tp and tp.x) or 0
      if math.abs(x) < 0.20 then
        state.snapLane[i] = "Center"
      elseif x < 0 then
        state.snapLane[i] = "Left"
      else
        state.snapLane[i] = "Right"
      end
      state.snapOrder[#state.snapOrder + 1] = i
    end
  end

  -- stable front/back order (relative to leader splinePosition, handles wrap)
  local leaderCar = safeCar(state.leader)
  local leaderSP = (leaderCar and leaderCar.splinePosition) or 0

  table.sort(state.snapOrder, function(a, b)
    local ca, cb = safeCar(a), safeCar(b)
    if not ca or not cb then return false end
    local da = leaderSP - (ca.splinePosition or 0); if da < 0 then da = da + 1 end
    local db = leaderSP - (cb.splinePosition or 0); if db < 0 then db = db + 1 end
    return da < db -- smaller distance to leader = more forward
  end)

  for rank = 1, #state.snapOrder do
    local idx2 = state.snapOrder[rank]
    state.snapRank[idx2] = rank
    if rank > 1 then
      state.snapFCI[idx2] = state.snapOrder[rank - 1]
    else
      state.snapFCI[idx2] = idx2 -- leader points to self
    end
  end

  -- Keep existing downstream API in sync (UI + other logic still reads desiredLane)
  state.desiredLane = state.desiredLane or {}
  for _, idx2 in ipairs(state.snapOrder) do
    state.desiredLane[idx2] = state.snapLane[idx2] or "Center"
  end
end

local function resetCarControl(i)
  if not physics then return end
  -- Best-effort reset:
  pcall(physics.setAIThrottleLimit, i, 1)
  pcall(physics.setAITopSpeed, i, math.huge)
  pcall(physics.setAISplineOffset, i, 0, false)
  pcall(physics.addForce, i, vec3(0,0,0), true, vec3(0,0,0), true)

  -- ✅ IMPORTANT: rolling start sets AILevel to 0.80, but we must reset it
  if physics.setAILevel then
    pcall(physics.setAILevel, i, 1.0)
  end

  -- Optional resets (good hygiene)
  if physics.setAIAggression then
    pcall(physics.setAIAggression, i, 1.0)
  end
  if physics.setAIBrakeHint then
    pcall(physics.setAIBrakeHint, i, 1.0)
  end
end

local function resetAll(sim)
  if not sim or not sim.carsCount then return end
  for i = 0, sim.carsCount - 1 do
    resetCarControl(i)
  end
end

local function rebuildSessionState(sim)
  state.PP = 0
  state.FR = 0
  state.leader = 0
  state.Formation = 0
  state.TimerF2 = 0
  state.OffsetL = 0
  state.OffsetR = 0
  state.FCI = {}
  state.Side = {}
  state.Tgap = {}
  state.Sgap = {}
  state.start = {}
  state.Offset = {}
  state.LimitSpeed2 = {}
  state.gridposition = {}
  state.position = {}
  state.desiredLane = {}
  state.playerStartSide = nil
  state.stringSide = nil
  state.msgSide = nil
  state.msgCooldown = 0
  state.rollingAnnounced = false
  state.greenAnnounced   = false
  state.greenTimer       = 0
  state.activeLastFrame  = false   -- must reset so justReleased fires correctly on restart
  state.releaseResetTimer = 0
  state.finished = false
  state._msgWarmup = 0
  state._gapSmooth = nil
end

-- Returns: (isControllingThisFrame: boolean)
function M.update(dt, sim, cfg)
  if not sim or not cfg then return false end

  -- Default: rolling start not active unless we decide otherwise this frame
  cfg._rollingStartActive = false

  local rs = cfg.rollingStart
  if type(rs) ~= "table" or rs.enabled ~= true then
    if state.activeLastFrame then
      resetAll(sim)
      state.activeLastFrame = false
    end
    return false
  end

  if sim.isOnlineRace then return false end

  -- Race only
  if sim.raceSessionType ~= 3 then
    if state.activeLastFrame then
      resetAll(sim)
      state.activeLastFrame = false
    end
    return false
  end

  if sim.isPaused then
    if state.activeLastFrame then
      resetAll(sim)
      state.activeLastFrame = false
    end
    return false
  end

  local trackLenM = tonumber(sim.trackLengthM) or 0
  if trackLenM < 1500 then
    if not state.warnedMissing and ac and ac.log then
      ac.log("[ApexFlow RollingStart] Disabled: trackLengthM < 1500m (rolling start unreliable on short tracks).")
      state.warnedMissing = true
    end
    return false
  end
  local meter = 1.0 / trackLenM

  if not requiredPhysicsOk() then
    if not state.warnedMissing and ac and ac.log then
      ac.log("[ApexFlow RollingStart] Missing required physics functions (setAIThrottleLimit/setAITopSpeed/setAISplineOffset/addForce).")
      state.warnedMissing = true
    end
    return false
  end

  -- Session index check MUST happen before the finished guard so that
  -- on race restart, rebuildSessionState() clears finished = false.
  local carsCount = tonumber(sim.carsCount) or 0
  local sessionIndex = tonumber(sim.currentSessionIndex) or 0
  if sessionIndex ~= state.lastSessionIndex or carsCount ~= state.lastCarsCount then
    rebuildSessionState(sim)
    state.lastSessionIndex = sessionIndex
    state.lastCarsCount = carsCount
  end
  if carsCount <= 0 then return false end

  -- If rolling start has been marked finished for THIS session, do nothing.
  -- (checked after session rebuild so restart properly resets this flag)
  if state.finished then
    return false
  end

  -- Clamp config
  local LimitSpeed = clamp(tonumber(rs.limitSpeed) or 80, 60, 100)
  local Fgap       = clamp(tonumber(rs.formationGap) or 4.5, 3.5, 10)
  local MaxOffset  = clamp(tonumber(rs.maxOffset) or 0.4, 0.2, 0.8)
  local releaseAt  = clamp((tonumber(rs.releaseAtPct) or 92) / 100, 0.15, 0.98)
  local singleFileMeters = clamp(tonumber(rs.singleFileMeters) or 600, 100, 1500)
  local singleFileAt = clamp(releaseAt - meter * singleFileMeters, 0.05, releaseAt)

  local carcount = carsCount - 1

  -- sessionTimeLeft can be negative for lap-based races; keep a safe version for any math.
  local stlRaw = tonumber(sim.sessionTimeLeft)
  local stl = (stlRaw ~= nil) and stlRaw or 0
  local stlSafe = math.max(stl, 0)

-- Determine leader + PP/FR and per-car positions (do NOT gate on stl)
state.leader = 0
state.PP = 0
state.FR = 0

for i = 0, carcount do
  local car = safeCar(i)
  if car then
    state.position[i] = car.racePosition

    if car.racePosition == 1 then
      state.PP = car.index
      state.leader = car.index
    elseif car.racePosition == 2 then
      state.FR = car.index
    end
  end
end

-- Build FCI (car in front by racePosition-1)
for i = 0, carcount do
  local car = safeCar(i)
  if car then
    for j = 0, carcount do
      local carJ = safeCar(j)
      if carJ and (carJ.racePosition == (car.racePosition - 1)) then
        state.FCI[i] = carJ.index
        break
      end
    end
  end
end

  local leaderCar = safeCar(state.leader)
  if not leaderCar then return false end

  local leaderSP = leaderCar.splinePosition or 0
local leaderLap = leaderCar.lapCount or 0
local isRolling = (leaderSP < releaseAt) and (leaderLap < 1)

-- SAFETY: never allow rolling start beyond lap 1
if leaderLap >= 1 then
  isRolling = false
end

-- ✅ Expose rolling start status AFTER final isRolling decision
cfg._rollingStartActive = isRolling

local justReleased = (state.activeLastFrame == true and isRolling == false)

if justReleased then
  for j = 0, carcount do
    resetCarControl(j)
  end

  -- ✅ Notify AI controller to immediately re-apply UI settings after release
  cfg._rollingJustReleased = true

  cfg._rollingStartActive = false
  
  state.releaseResetTimer = 3.0

  -- keep logging briefly after release, then go quiet
  state.logPostReleaseTimer = 3.0
end

-- Logging gate: log every frame while rolling OR for a short window after release
if state.logPostReleaseTimer and state.logPostReleaseTimer > 0 then
  state.logPostReleaseTimer = state.logPostReleaseTimer - dt
  if state.logPostReleaseTimer < 0 then state.logPostReleaseTimer = 0 end
end

local shouldLog = isRolling or ((state.logPostReleaseTimer or 0) > 0)

  -- =========================================================
  -- ✅ Stop all rolling-start ticking after lap 2 begins.
  -- After lap 1 is complete (leaderLap >= 1), rolling start is never needed again
  -- in this session, and it should not keep scanning gaps/FCI every frame.
  -- =========================================================
  if (leaderLap or 0) >= 1 and (not isRolling) then
    -- One last hygiene reset if something external left caps behind.
    if state.activeLastFrame then
      resetAll(sim)
      state.activeLastFrame = false
    end

    -- If we've already completed the post-release reset window, stop permanently.
    if (state.releaseResetTimer or 0) <= 0 then
      state.finished = true
      cfg._rollingStartActive = false
      return false
    end
  end

-- v0.31.0: log 1x/s (era 60x/s = 3k linhas/min no custom_shaders_patch.log)
state.logTimer = (state.logTimer or 0) + dt
if shouldLog and ac and ac.log and state.logTimer >= 1.0 then
  state.logTimer = 0
  ac.log(string.format(
    "[ApexFlow RollingStart] leader=%d lap=%d sp=%.3f releaseAt=%.3f isRolling=%s",
    state.leader, leaderLap, leaderSP, releaseAt, tostring(isRolling)
  ))
end

  -- string side selector (LATCHED while rolling to prevent flip-flop)
  if state.stringSide == nil or not isRolling then
    local ss = 0
    local ppCar = safeCar(state.PP)
    local frCar = safeCar(state.FR)
    if ppCar and frCar then
      local okA, a = pcall(ac.worldCoordinateToTrack, ppCar.position)
      local okB, b = pcall(ac.worldCoordinateToTrack, frCar.position)
      if okA and okB and a and b then
        if (a.x or 0) <= (b.x or 0) then ss = 1 else ss = 0 end
      end
    end
    state.stringSide = ss
  end

    local stringSide = state.stringSide or 0

  -- ✅ Latch PLAYER starting side ONCE (prevents flipping if player drifts across center)
  if isRolling and state.playerStartSide == nil then
    local player = safeCar(0)
    if player then
      local okP, tp = pcall(ac.worldCoordinateToTrack, player.position)
      if okP and tp and tp.x then
        state.playerStartSide = (tp.x < 0) and 0 or 1
      end
    end
  end

  -- ✅ Use the player's latched start side for BOTH player + AI lane assignment
  if state.playerStartSide ~= nil then
    stringSide = state.playerStartSide
  end

  -- ✅ Keep state in sync
  state.stringSide = stringSide

-- Latch each car’s desired lane ONCE at rolling start (prevents darting later)
-- NOTE: must happen AFTER stringSide is calculated
if isRolling and not state.snapTaken then
  -- Snapshot once per rolling start: locks each car's lane and car-ahead relationship
  takeSnapshot(carcount)
elseif isRolling and next(state.desiredLane) == nil then
  -- Fallback (should rarely happen): keep old parity-based assignment if no snapshot
  for k = 0, carcount do
    local c = safeCar(k)
    if c then
      if state.gridposition[k] == nil then
        state.gridposition[k] = math.fmod(c.racePosition or 0, 2)
      end
      if state.gridposition[k] == 0 then
        state.desiredLane[k] = (stringSide == 0) and "Left" or "Right"
      else
        state.desiredLane[k] = (stringSide == 0) and "Right" or "Left"
      end
    end
  end
end

-- reset latch after release
if not isRolling then
  state.stringSide = nil
  state.playerStartSide = nil
  state.gridposition = {}
  state.desiredLane = {}
  state.snapTaken = false
  state.snapLane = {}
  state.snapOrder = {}
  state.snapRank = {}
  state.snapFCI = {}
end

  -- v0.29.2: fila dupla ultra-alinhada — paridade + snapshot + gap 3.5m + pelotão colado
  for i = 0, carcount do
    local car = safeCar(i)
    if car then
    if state.gridposition[i] == nil then
      state.gridposition[i] = math.fmod(car.racePosition or 0, 2)
    end

      local fci = state.FCI[i]
      if isRolling and state.snapTaken and state.snapFCI[i] ~= nil then
        fci = state.snapFCI[i]
      end
      if fci == nil then fci = i end

      local okGap, gap = pcall(ac.getGapBetweenCars, fci, i)
      state.Tgap[i] = (okGap and gap) or 0
      local carSP = car.splinePosition or 0
      local d = leaderSP - carSP
      if d < 0 then d = d + 1 end -- wrap so distance is always forward distance to leader
      state.Sgap[i] = d

      local frontSpeed = getCarSpeedKmh(fci)
      local mySpeed    = getCarSpeedKmh(i)
      local closing    = mySpeed - frontSpeed  -- + = I'm approaching the car in front

      -- Two-by-two early, single-file before release (fixed 2026-09: was inverted)
       if leaderSP <= singleFileAt then
         state.Formation = 2
         state.LimitSpeed2[i] = math.min(
           LimitSpeed + (state.Sgap[i] / meter - (Fgap * (state.position[i] or 0))) * 2,
           LimitSpeed + 40
         )
       else
         state.Formation = 1
         state.LimitSpeed2[i] = math.max(
           LimitSpeed - 50,
           math.min(LimitSpeed - ((state.Tgap[i] + 1) * 10), LimitSpeed + 40)
         )
       end

      if not isRolling then
        state.Formation = 2
      end

      -- lane offsets ramp (faster: was dt/28 ~13s to reach, now dt/12 ~5s)
       if state.Formation == 2 then
         state.OffsetL = math.max(MaxOffset * -1, state.OffsetL - dt / 12)
         state.OffsetR = math.min(MaxOffset,       state.OffsetR + dt / 12)
       else
         state.OffsetL = math.min(0, state.OffsetL + dt / 12)
         state.OffsetR = math.max(0, state.OffsetR - dt / 12)
       end

      if isRolling then
        -- Keep original intent but use stlSafe so lap-based races don't get odd negatives.
       local allowThrottle = 1

local allowThrottle = 1

-- Timed sessions only: early race staging to keep the pack calm for a moment
if stlSafe > 0 then
  if stlSafe > (sim.sessionDuration * 0.95) then
    allowThrottle = 0.35
  end
end

if physics and physics.setAIAggression then
  pcall(physics.setAIAggression, i, 0.10)
end
if physics and physics.setAILevel then
  pcall(physics.setAILevel, i, 0.95)
end
if physics and physics.setAIBrakeHint then
  pcall(physics.setAIBrakeHint, i, 1.25)
end

   if car.index == state.leader then
  local lim2 = LimitSpeed
  pcall(physics.setAITopSpeed, i, lim2)

  -- Throttle governor: never exceed speed cap before green
  local throttle = allowThrottle
  if (car.speedKmh or 0) > (lim2 + 0.5) then throttle = 0.15 end
  pcall(physics.setAIThrottleLimit, i, throttle)
else
  local lim2 = tonumber(state.LimitSpeed2[i]) or LimitSpeed
  lim2 = math.min(lim2, LimitSpeed)
  lim2 = math.max(lim2, 15) -- never cap below crawl speed
-- Catch-up help for deep pack: farther back = more speed to close the 2x2 gap
local pos = car.racePosition or 0
if pos > 12 then
  lim2 = math.min(LimitSpeed + 8, lim2 + 4 + (pos - 12) * 0.4)
elseif pos > 6 then
  lim2 = math.min(LimitSpeed, lim2 + 2.5)
end

  pcall(physics.setAITopSpeed, i, lim2)

   -- Throttle governor: never exceed speed cap before green
  local throttle = allowThrottle

  -- Hard speed cap enforcement
  if mySpeed > (lim2 + 0.5) then
    throttle = math.min(throttle, 0.15)
  end

  -- Collision-prevention layer:
  -- If I'm close AND still closing, aggressively lift + (optionally) light brake assist
  local g = state.Tgap[i] or 99
  if g < (Fgap * 0.75) and closing > 1.5 then
    throttle = math.min(throttle, 0.05)

    -- If I'm REALLY about to bump, apply a small braking force (much lighter than original)
    if g < (Fgap * 0.55) and closing > 3.0 then
      pcall(physics.addForce, i, vec3(0,0.15,-1), true, vec3(0,0,-12000), true)
    else
      -- clear brake force if not needed
      pcall(physics.addForce, i, vec3(0,0,0), true, vec3(0,0,0), true)
    end
  else
    -- clear brake force if not needed
    pcall(physics.addForce, i, vec3(0,0,0), true, vec3(0,0,0), true)
  end

  pcall(physics.setAIThrottleLimit, i, throttle)
end

        -- Apply formation offsets (STRICT + NO CROSSOVER)
if state.Formation == 1 then
  -- Single file: centerline BUT pre-sort toward future lane (prevents darting at 2×2)
  local lane = (state.snapLane[i] or state.desiredLane[i]) or "Center"

  -- Progress through the single-file phase: 0 → 1
  local t = clamp(leaderSP / singleFileAt, 0, 1)

  -- Ramp bias smoothly so it doesn't snap early
  local biasMax = 0.22   -- increase to 0.28 if cars still end up wrong-side
  local bias = 0

  if lane == "Right" then bias =  biasMax * t end
  if lane == "Left"  then bias = -biasMax * t end

  state.Side[i] = "Center"
  pcall(physics.setAISplineOffset, i, bias, false)

else
  -- 2×2: use latched lane, no racePosition parity flips
  local lane = (state.snapLane[i] or state.desiredLane[i]) or "Center"

  if lane == "Center" then
    state.Side[i] = "Center"
    pcall(physics.setAISplineOffset, i, 0, false)
  elseif lane == "Right" then
    state.Side[i] = "Right"
    pcall(physics.setAISplineOffset, i, state.OffsetR, false)
  else
    state.Side[i] = "Left"
    pcall(physics.setAISplineOffset, i, state.OffsetL, false)
  end

  state.TimerF2 = state.TimerF2 + dt
end
      else
        resetCarControl(i)
      end
    end
  end

    -- Race control messaging (fixed if/elseif structure)
  if isRolling then
    -- if timed, stl might cross around 0; if lap-based, stl is negative, so skip this timed-only cue
    if stl <= 0 and stl >= -100 and state.Formation <= 1 then
      ac.setMessage("Race Control", "Rolling Start Active")

   elseif state.Formation == 2 and state.TimerF2 <= 5 then
  ac.setMessage("Race Control", "Rolling Start Active")

  elseif (leaderCar.lapCount or 0) == 0 then
      -- Player gap: try ac.getGapBetweenCars(carAhead, player) first.
      -- If it returns 0/nil (player car not supported), fall back to
      -- direct spline distance to FCI car as a reliable alternative.
      local gapMsg = "Hold Position"
      local fci0 = state.FCI[0]
      local fciCar = fci0 and safeCar(fci0)
      state._msgWarmup = (state._msgWarmup or 0) + dt

      if fciCar and fci0 ~= 0 and state._msgWarmup > 2.0 then
        -- Try the API first
        local distM = nil
        local okG, gapVal = pcall(ac.getGapBetweenCars, fci0, 0)
        if okG and type(gapVal) == "number" and gapVal > 0.5 then
          distM = gapVal
        end

        -- Fallback: spline distance between player and car directly ahead only
        if not distM then
          local playerCar = safeCar(0)
          if playerCar then
            local pSP = playerCar.splinePosition or 0
            local fSP = fciCar.splinePosition or 0
            local diff = fSP - pSP
            if diff < -0.5 then diff = diff + 1 end
            if diff < 0 then diff = 0 end
            distM = diff * trackLenM
          end
        end

        if distM then
          -- Smooth the distance reading to prevent jitter/drift
          local prev = state._gapSmooth or distM
          state._gapSmooth = prev + (distM - prev) * 0.15  -- EMA, slow to respond
          local delta = state._gapSmooth - Fgap
          if delta > 8.0 then
            gapMsg = "Keep Up"
          elseif delta > 2.0 then
            gapMsg = "Close the Gap"
          elseif delta < -4.0 then
            gapMsg = "Back Off"
          elseif delta < -1.5 then
            gapMsg = "Ease Off"
          else
            gapMsg = "Hold Position"
          end
        end
      end

      -- Lane: use the same snapshot lane assignment as AI cars
      -- snapLane[0] is set during takeSnapshot() using the same stringSide logic
      -- so it's consistent with what the AI cars are told to do
      local playerLane = state.snapLane and state.snapLane[0]
      if not playerLane or playerLane == "Center" then
        -- fallback to desiredLane if snapshot hasn't fired yet
        playerLane = state.desiredLane and state.desiredLane[0]
      end

      -- Only show Left/Right during 2x2 phase, not single-file
      if state.Formation == 2 and playerLane and playerLane ~= "Center" and playerLane ~= "" then
        ac.setMessage("Keep " .. playerLane, gapMsg)
      else
        ac.setMessage("Formation", gapMsg)
      end
    end

  else
    -- isRolling is false: either just released or already done.
    -- justReleased is only true for ONE frame so we latch it into greenTimer.
    -- On restart rebuildSessionState resets greenAnnounced and greenTimer
    -- so this fires cleanly every time.
    if justReleased and not state.greenAnnounced then
      state.greenAnnounced = true
      state.greenTimer = 4.0
      state.msgSide = nil
      state.msgCooldown = 0
      if playBeep then playBeep() end
    end

    if (state.greenTimer or 0) > 0 then
      state.greenTimer = (state.greenTimer or 0) - dt
      ac.setMessage("Race Control", "Green Flag")
    end
  end

  -- ✅ Post-green hard reset window (prevents AI from staying slow/capped)
  if state.releaseResetTimer and state.releaseResetTimer > 0 then
    state.releaseResetTimer = state.releaseResetTimer - dt
    for j = 0, carcount do
      resetCarControl(j)
    end
  end

  state.activeLastFrame = isRolling
  return isRolling
end

return M