-- src/webui.lua
-- Remote Web UI for RaceFlow
-- Uses shared file polling (no HTTP server in CSP)
-- External tool polls / reads status file, writes commands file

local M = {}

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
  local docs = ac.getFolder(ac.FolderID.Documents)
  return docs .. "/Assetto Corsa/"
end

local function readJsonFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return nil end
  local ok, data = pcall(function() return ac.decodeJson(content) end)
  if ok then return data end
  return nil
end

local function writeJsonFile(path, data)
  local f = io.open(path, "w")
  if not f then return false end
  local ok, content = pcall(function() return ac.encodeJson(data) end)
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
  local mem = _G.RARE2_API and _G.RARE2_API.getMemory and _G.RARE2_API.getMemory() or {}
  local vscState = _G.RARE2_API.getVSCState and _G.RARE2_API.getVSCState() or {}
  local githubState = _G.RARE2_API.githubGetState and _G.RARE2_API.githubGetState() or {}

  local cars = {}
  if sim and sim.carsCount then
    for i = 0, sim.carsCount - 1 do
      local ok, car = pcall(ac.getCar, i)
      if ok and car then
        local driver = ac.getDriverName(i) or ("Car " .. i)
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
        local name = ac.getDriverName(idx) or ("Car " .. idx)
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
    vsc = vscState,
    github = githubState,
    cars = cars,
    leaderboard = leaderboard,
    learning = {
      tracksCount = 0,
      totalCorners = 0,
    },
    config = {
      aggression = cfg.aggression,
      paceStrength = cfg.paceStrength,
      difficultyBoost = cfg.difficultyBoost,
      vscEnabled = cfg.vsc and cfg.vsc.enabled,
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

        if action == "vsc_toggle" then
          if _G.RARE2_API.vscManualTrigger then
            _G.RARE2_API.vscManualTrigger(sim, cfg)
          end
        elseif action == "vsc_enable" then
          cfg.vsc.enabled = true
          _G.RARE2_API.markConfigDirty()
        elseif action == "vsc_disable" then
          cfg.vsc.enabled = false
          _G.RARE2_API.markConfigDirty()
        elseif action == "rolling_toggle" then
          cfg.rollingStart.enabled = not cfg.rollingStart.enabled
          _G.RARE2_API.markConfigDirty()
        elseif action == "strategy_toggle" then
          cfg.strategy.enabled = not cfg.strategy.enabled
          _G.RARE2_API.markConfigDirty()
        elseif action == "set_aggression" then
          cfg.aggression = tonumber(params.value) or cfg.aggression
          _G.RARE2_API.markConfigDirty()
        elseif action == "set_pace" then
          cfg.paceStrength = tonumber(params.value) or cfg.paceStrength
          _G.RARE2_API.markConfigDirty()
        elseif action == "set_difficulty" then
          cfg.difficultyBoost = tonumber(params.value) or cfg.difficultyBoost
          _G.RARE2_API.markConfigDirty()
        elseif action == "github_check" then
          if _G.RARE2_API.githubCheckUpdates then
            _G.RARE2_API.githubCheckUpdates(cfg, true)
          end
        elseif action == "save_config" then
          if _G.RARE2_API.saveConfig then
            _G.RARE2_API.saveConfig()
          end
        elseif action == "reset_defaults" then
          if _G.RARE2_API.resetToDefaults then
            _G.RARE2_API.resetToDefaults()
          end
        elseif action == "clear_memory_track" then
          local mem = _G.RARE2_API.getMemory and _G.RARE2_API.getMemory()
          if mem and mem.tracks and params.trackId then
            mem.tracks[params.trackId] = nil
            _G.RARE2_API._memoryDirty = true
          end
        elseif action == "clear_memory_all" then
          local mem = _G.RARE2_API.getMemory and _G.RARE2_API.getMemory()
          if mem then
            mem.tracks = {}
            _G.RARE2_API._memoryDirty = true
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
-- 2. Write to commandFile with { commands: [{ id: 1, action: "vsc_toggle", token: "secret" }] }
-- 3. Wait for commandFile to show processed ID

return M