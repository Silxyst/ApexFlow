-- src/webui.lua
-- Remote Web UI for RaceFlow
-- Uses shared file polling (no HTTP server in CSP)
-- External tool polls / reads status file, writes commands file

local M = {}

-- RARE2_API guard
_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API


local state = {
  enabled = false,
  port = 8080,
  authToken = "",
  lastCommandId = 0,
  lastStatusWrite = 0,
  statusWriteInterval = 0.5, -- write status every 0.5s
  commandFile = "RaceFlow_webui_cmd.json",
  statusFile = "RaceFlow_webui_status.json",
}

local function getAppDataPath()
  local ok, docs = pcall(ac.getFolder, ac.FolderID.Documents)
  if not ok or not docs or docs=="" then return nil end
  return docs .. "/Assetto Corsa/"
end

local function readJsonFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return nil end
  local ok, data = pcall(function() 
    if ac.decodeJson then
      return ac.decodeJson(content)
    else
      -- Simple fallback: only handles basic JSON
      return nil
    end
  end)
  if ok then return data end
  return nil
end

local function writeJsonFile(path, data)
  local f = io.open(path, "w")
  if not f then return false end
  local ok, content = pcall(function() 
    if ac.encodeJson then
      return ac.encodeJson(data)
    else
      -- Fallback: simple JSON encoding for basic types
      local function encode(v)
        local t = type(v)
        if t == "string" then return '"' .. v:gsub('"', '\\"') .. '"'
        elseif t == "number" or t == "boolean" then return tostring(v)
        elseif t == "table" then
          local isArray = #v > 0
          local parts = {}
          if isArray then
            for i, val in ipairs(v) do parts[i] = encode(val) end
            return "[" .. table.concat(parts, ",") .. "]"
          else
            for k, val in pairs(v) do table.insert(parts, '"' .. k .. '":' .. encode(val)) end
            return "{" .. table.concat(parts, ",") .. "}"
          end
        else
          return "null"
        end
      end
      return encode(data)
    end
  end)
  if ok then f:write(content) end
  f:close()
  return ok
end

local function authCheck(token)
  if not state.authToken or state.authToken == "" then return true end
  return token == state.authToken
end

-- Build status payload
local function buildStatus(sim, cfg)
  local mem = _G.RARE2_API and RARE2_API.getMemory and RARE2_API.getMemory() or {}
  -- NOTE v0.5.0: VSC removed; field kept as explicit marker for old clients.
  local githubState = RARE2_API.githubGetState and RARE2_API.githubGetState() or {}

  local cars = {}
  if sim and sim.carsCount then
    for i = 0, sim.carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car then
        local okD, driver = pcall(ac.getDriverName, i)
        driver = (okD and driver and driver~="" and driver) or ("Car " .. i)
        cars[#cars + 1] = {
          index = i,
          driver = driver,
          isPlayer = (i == 0),
          isAI = car.isAIControlled,
          speedKmh = car.speedKmh or 0,
          position = car.splinePosition or 0,
          lap = car.lapCount or 0,
          racePos = car.racePosition or 0,
          fuel = car.fuel or 0,
          maxFuel = car.maxFuel or 0,
          tyreWear = car.wheels and car.wheels[0] and car.wheels[0].tyreWear or 0,
          isInPit = car.isInPitlane or car.isInPit,
          isRetired = car.isRetired,
          isFinished = car.isRaceFinished,
        }
      end
    end
  end

  local session = ac.getSession and ac.getSession(sim.currentSessionIndex) or nil
  local leaderboard = {}
  if session and session.leaderboard then
    for pos = 0, #session.leaderboard - 1 do
      local le = session.leaderboard[pos]
      if le and le.car then
        local idx = le.car.index
        local okN, name = pcall(ac.getDriverName, idx)
        name = (okN and name and name~="" and name) or ("Car " .. idx)
        leaderboard[#leaderboard + 1] = {
          pos = pos + 1,
          driver = name,
          carIndex = idx,
          laps = le.laps or 0,
          totalTime = le.totalTimeMs or le.timeMs or 0,
          bestLap = le.bestLapTimeMs or le.bestLapTime or 0,
        }
      end
    end
  end

  return {
    timestamp = os.time(),
    version = SCRIPT_VERSION,
    appEnabled = cfg.enabled,
    session = {
      name = ac.getSessionName and ac.getSessionName(sim.currentSessionIndex) or "",
      track = ac.getTrackName and ac.getTrackName() or "",
      timeLeft = sim.sessionTimeLeft or 0,
      isStarted = sim.isSessionStarted,
      isFinished = sim.isSessionFinished,
      flagType = sim.raceFlagType or 0,
    },
    vsc = { removed = true },
    github = githubState,
    cars = cars,
    leaderboard = leaderboard,
    learning = {
      tracksCount = 0,
      totalCorners = 0,
    },
    -- v0.29.0 limpo extremo: snapshots só gaps/sector/penaltySeverity (caution/track/voice/box/safety removidos 3,4,6)
    -- caution/tracklimits/voice/boxPenalty/safetyCar removidos — AC nativo assume
    gapBehind = (function()
      local ok, s = pcall(function() return _G.RARE2_API and RARE2_API.getGapBehindState and RARE2_API.getGapBehindState() or {} end)
      if not ok or type(s) ~= "table" then return { gapBehindM = 0 } end
      return { gapBehindM = s.gapBehindM or 0, gapBehindKm = s.gapBehindKm or 0, carBehindPos = s.carBehindPos or 0, deltaBehind = s.deltaBehind or 0, isLappedBehind = s.isLappedBehind == true }
    end)(),
    sectorGaps = (function()
      local ok, s = pcall(function() return _G.RARE2_API and RARE2_API.getSectorGapsState and RARE2_API.getSectorGapsState() or {} end)
      if not ok or type(s) ~= "table" then return { gapSectorS = 0 } end
      return { currentSector = s.currentSector or 0, gapSectorM = s.gapSectorM or 0, gapSectorS = s.gapSectorS or 0 }
    end)(),
    penaltySeverity = (function()
      local ok, s = pcall(function() return _G.RARE2_API and RARE2_API.getPenaltySeverityState and RARE2_API.getPenaltySeverityState() or {} end)
      if not ok or type(s) ~= "table" then return { totalPP = 0 } end
      return { totalPP = s.totalPP or 0, level = s.level or 0, lastReason = s.lastReason or "" }
    end)(),
    preset = (cfg.categoryPreset or "custom"),
    config = {
      aggression = cfg.aggression,
      paceStrength = cfg.paceStrength,
      difficultyBoost = cfg.difficultyBoost,
      rollingStartEnabled = cfg.rollingStart and cfg.rollingStart.enabled,
      strategyEnabled = cfg.strategy and cfg.strategy.enabled,
    },
  }
end

-- Process commands from external tool
local function processCommands(sim, cfg)
  local cmdPath = getAppDataPath() .. state.commandFile
  local data = readJsonFile(cmdPath)
  if not data or not data.commands then return end

  for _, cmd in ipairs(data.commands) do
    if cmd.id and cmd.id > state.lastCommandId then
      state.lastCommandId = cmd.id
      local token = cmd.token or ""
      if not authCheck(token) then
        ac.log("[RaceFlow WebUI] Auth failed for command: " .. (cmd.action or "unknown"))
      else
        local action = cmd.action
        local params = cmd.params or {}

        -- NOTE v0.5.0: vsc_* commands removed with the VSC system.
        -- Old clients sending them get a log line instead of a crash.
        if action == "vsc_toggle" or action == "vsc_enable" or action == "vsc_disable" then
          ac.log("[RaceFlow WebUI] command '" .. tostring(action) .. "' ignored: VSC removed in v0.5.0")
        elseif action == "rolling_toggle" then
          cfg.rollingStart.enabled = not cfg.rollingStart.enabled
          RARE2_API.markConfigDirty()
        elseif action == "strategy_toggle" then
          cfg.strategy.enabled = not cfg.strategy.enabled
          RARE2_API.markConfigDirty()
        elseif action == "set_aggression" then
          cfg.aggression = tonumber(params.value) or cfg.aggression
          RARE2_API.markConfigDirty()
        elseif action == "set_pace" then
          cfg.paceStrength = tonumber(params.value) or cfg.paceStrength
          RARE2_API.markConfigDirty()
        elseif action == "set_difficulty" then
          cfg.difficultyBoost = tonumber(params.value) or cfg.difficultyBoost
          RARE2_API.markConfigDirty()
        elseif action == "apply_preset" then
          -- v0.18.0: aplica preset de categoria (gt3/gt4/tcr/f1/lmp/endurance)
          if RARE2_API.applyCategoryPreset and params.key then
            RARE2_API.applyCategoryPreset(tostring(params.key))
            RARE2_API.markConfigDirty()
          end
        -- v0.29.0 limpo: caution_trigger/voice_test removidos (3,4,6 peso morto)
        elseif action == "github_check" then
          if RARE2_API.githubCheckUpdates then
            RARE2_API.githubCheckUpdates(cfg, true)
          end
        elseif action == "save_config" then
          if RARE2_API.saveConfig then
            RARE2_API.saveConfig()
          end
        elseif action == "reset_defaults" then
          if RARE2_API.resetToDefaults then
            RARE2_API.resetToDefaults()
          end
        elseif action == "clear_memory_track" then
          local mem = RARE2_API.getMemory and RARE2_API.getMemory()
          if mem and mem.tracks and params.trackId then
            mem.tracks[params.trackId] = nil
            RARE2_API._memoryDirty = true
          end
        elseif action == "clear_memory_all" then
          local mem = RARE2_API.getMemory and RARE2_API.getMemory()
          if mem then
            mem.tracks = {}
            RARE2_API._memoryDirty = true
          end
        end
      end
    end
  end

  -- Clear commands file after processing
  writeJsonFile(cmdPath, { commands = {}, processed = state.lastCommandId })
end

-- Write status file for external polling
local function writeStatus(sim, cfg)
  local statusPath = getAppDataPath() .. state.statusFile
  local status = buildStatus(sim, cfg)
  writeJsonFile(statusPath, status)
end

function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted then return end
  if not cfg.webui or not cfg.webui.enabled then return end

  state.enabled = true
  state.authToken = cfg.webui.authToken or ""

  -- Process incoming commands
  processCommands(sim, cfg)

  -- Write status file periodically
  state.lastStatusWrite = state.lastStatusWrite + dt
  if state.lastStatusWrite >= state.statusWriteInterval then
    state.lastStatusWrite = 0
    writeStatus(sim, cfg)
  end
end

function M.getState()
  return {
    enabled = state.enabled,
    statusFile = getAppDataPath() .. state.statusFile,
    commandFile = getAppDataPath() .. state.commandFile,
    authToken = state.authToken ~= "" and "***" or "(none)",
    pollInterval = state.statusWriteInterval,
  }
end

-- Example external client (Python/Node/JS) would:
-- 1. Poll statusFile every 500ms
-- 2. Write to commandFile with { commands: [{ id: 1, action: "rolling_toggle", token: "secret" }] }
-- 3. Wait for commandFile to show processed ID

return M