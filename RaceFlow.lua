SCRIPT_NAME = "RaceFlow"
SCRIPT_VERSION = "0.12.0"
_G.RACEFLOW_VERSION = "0.12.0"

-- Per-module load status, shown in the fallback window so a future
-- require() failure identifies the exact module (no more guessing).
local modStatus = {}
local function safeRequire(name)
  local ok, mod = pcall(require, name)
  if ok and mod then
    modStatus[name] = "OK"
    return mod
  end
  modStatus[name] = "FAIL: " .. tostring(mod)
  if ac and ac.log then ac.log(string.format("[RaceFlow] require('%s') failed: %s", tostring(name), tostring(mod))) end
  return nil
end

local ui_root      = safeRequire("src.ui")
local ai           = safeRequire("src.ai_controller")
local rolling      = safeRequire("src.rolling_start")
local strategy     = safeRequire("src.race_strategy")
local caution      = safeRequire("src.caution")       -- v0.6.0: FCY + sector yellow
local tracklimits  = safeRequire("src.tracklimits")   -- v0.7.0: warnings -> time penalty
local webui        = safeRequire("src.webui")         -- Remote Web UI (file polling)
-- NOTE v0.5.0+: src/vsc + src/github_update modules are DEPRECATED and no
-- longer required. GitHub check lives in this file (single source of truth)
-- to avoid dual-state bugs.

local RARE2_CFG = {
  enabled      = true,
  aggression   = 50,
  paceEnabled  = true,
  paceStrength = 65,
  difficultyBoost = 100,

  strategy = {
    enabled = true,
    manualRaceLaps = 20,
    forcedStops = 1,
    reserveLaps = 1.2,
    minRefuelLaps = 4.0,
    emergencyFuelLaps = 0.6,
    enforceWindowLaps = 1.0,
  },

  rollingStart = {
    enabled         = false,
    preset          = "Normal",
    limitSpeed      = 80,
    formationGap    = 4,
    maxOffset       = 0.4,
    releaseAtPct    = 50,
    singleFileMeters= 600,
  },

  -- v0.6.0: Caution system (FCY + sector yellow). Disabled by default.
  caution = {
    enabled = false,
    fcySpeedKmh = 80,
    yellowSpeedKmh = 80,
    minDuration = 60,
    maxDuration = 180,
    fcyChance = 0.5,
    autoTrigger = true,
    minDrivenKm = 0.5,
    cooldown = 10,
    overtakeEnabled = true,   -- v0.8.0: punish player overtakes
    giveBackTime = 10,
    overtimePenalty = 5,
  },

  -- v0.7.0: Track Limits (port of Mavil core). Disabled by default.
  tracklimits = {
    enabled = false,
    trackLimitsEnabled = true,
    penaltiesEnabled = true,
    maxWarnings = 4,
    penaltyTime = 5,
    cooldown = 7,
    extraTime = 10,
    strictPit = false,
    waitTime = 1.9,
    wheels = 4,
    aiEnabled = true,
    aiServe = false,
    qualiReset = true,
    finishAdd = true,
    gamePenaltyCompat = true, -- v0.9.0: skip new warnings while game punishes
    minOffTime = 0.25,        -- v0.10.0: sustained off-track debounce
    pitSpeedEnabled = true,   -- v0.10.0: punish pit-lane speeding
    pitLimitKmh = 80,
    pitGraceSec = 1.0,
  },

  -- NEW: GitHub update checker
  githubUpdate = {
    enabled = true,
    repo = "Silxyst/RaceFlow-V2",    -- GitHub repo (owner/repo)
    checkIntervalHours = 24,         -- auto-check interval
    notifyOnStartup = true,          -- check on app load
  },

  -- v0.12.0: Race Events HUD — fully customizable (see About -> HUD).
  hudEvents = {
    showCaution = true,
    showTrackLimits = true,
    showStrategy = true,
    showPosition = true,
    showSession = true,
    showLearning = false,
    compact = false,
    progressBars = true,
    blink = true,
    scale = 1.0,
  },

  -- NEW: Web UI remote
  webui = {
    enabled = false,
    port = 8080,
    authToken = "",                  -- optional bearer token
  },

  packs = { pace = true, ers = true, traffic = true, hud = true },

  -- v0.8.0: interface theme (About tab -> Appearance).
  ui = {
    accent = "cyan",   -- cyan|green|orange|purple|red|teal|pink
    bgAlpha = 1.0,     -- 0.4 .. 1.0 background opacity
    corner = 6,        -- 0 .. 12 corner rounding
    compactHeaders = false,
  },
}

-- Expose config globally for src/* modules (they run in same Lua state
-- but RARE2_CFG is local here). This fixes M.getState() returning nil config.
_G.RARE2_CFG = RARE2_CFG

-- ----------------------------------------------------------
-- Learning / safety defaults (can be overridden by config/UI)
-- ----------------------------------------------------------
RARE2_CFG.learningEnabled = true
-- NOTE v0.5.0: disableLearningDuringVSC removed with the VSC system.

-- Hard-event detection
RARE2_CFG.offTrackConfirmSec   = 0.8
RARE2_CFG.overshootTurnX       = 35
RARE2_CFG.overshootMinSpeedKmh = 95
RARE2_CFG.overshootMarginKmh   = 25
RARE2_CFG.overshootMinSamples  = 8
RARE2_CFG.overshootMaxTurnX    = 80

-- Hard-event impact on learning
RARE2_CFG.hardEventDangerAdd       = 2.0
RARE2_CFG.hardEventImprovePenalty  = 4.0
RARE2_CFG.crashSpeedDropKmh        = 55
RARE2_CFG.dangerDecayPerClean  = 0.35
RARE2_CFG.dangerDecayPerSecond = 0.004

RARE2_CFG.dangerGateCleanStreak = 12

RARE2_CFG.dangerOvercapBonusPerEvent = 0.10
RARE2_CFG.dangerOvercapMaxCeiling   = 2.80

RARE2_CFG.dangerRampStartEvent = 4
RARE2_CFG.dangerRampPow        = 1.35
RARE2_CFG.dangerRampGain       = 0.18

RARE2_CFG.brakeBiasAddOnHardEvent   = 0.03
RARE2_CFG.brakeBiasDecayPerClean    = 0.015
RARE2_CFG.brakeBiasMax              = 0.15
RARE2_CFG.brakeBiasThrottleLoss     = 0.06

RARE2_CFG.cornerLockEnabled     = true
RARE2_CFG.cornerLockMinSamples  = 80
RARE2_CFG.cornerLockCleanStreak = 120

RARE2_CFG.entryCapHeadroomKmh           = 6
RARE2_CFG.entryCapLearnUpKmhPerClean    = 1.0
RARE2_CFG.entryCapMinKmh                = 60
RARE2_CFG.entryCapMaxKmh                = 9999

RARE2_CFG.entryCapDropKmhOnOvershoot    = 12
RARE2_CFG.entryCapDropKmhOnContact      = 18
RARE2_CFG.entryCapDropKmhOnSlide        = 22
RARE2_CFG.entryCapDropKmhOnOfftrack     = 28

RARE2_CFG.entryCapPreMarginKmh          = 16
RARE2_CFG.entryCapExcessWindowKmh       = 60
RARE2_CFG.entryCapEarlyKickKmh          = 10
RARE2_CFG.entryCapEarlyStartTurnX       = 85
RARE2_CFG.entryCapEarlyEndTurnX         = 20

RARE2_CFG.entryCapEscalateEvents            = 3
RARE2_CFG.entryCapEscalateDanger            = 18
RARE2_CFG.entryCapPreMarginBonusEscalated   = 10
RARE2_CFG.entryCapWindowTightenEscalated    = 15
RARE2_CFG.entryCapEscalatedStrengthMul      = 1.15

RARE2_CFG.entryCapBrakeGain             = 0.42
RARE2_CFG.entryCapTopSpeedLoss          = 0.22
RARE2_CFG.entryCapThrottleLoss          = 0.16

RARE2_CFG.dangerCap            = 20
RARE2_CFG.dangerOvercapSlope   = 0.15
RARE2_CFG.dangerOvercapMax     = 1.30
RARE2_CFG.dangerBrakeGain      = 0.10
RARE2_CFG.dangerTopSpeedLoss   = 0.08
RARE2_CFG.dangerThrottleLoss   = 0.07

RARE2_CFG.paceBaseChillOverride     = -0.07
RARE2_CFG.paceBaseAttackOverride    =  0.07
RARE2_CFG.jitterScale               = 0.80
RARE2_CFG.singleClassBackCatchup    = 0.008
RARE2_CFG.singleClassBackCurve      = 2.5
RARE2_CFG.earlySpreadFrac           = 0.55
RARE2_CFG.earlySpreadNormalBoost    = 0.085
RARE2_CFG.earlySpreadAttackBoost    = 0.120
RARE2_CFG.multiclassYieldStrength  = 85
RARE2_CFG.multiclassPushStrength   = 75
RARE2_CFG.multiclassYieldDistM     = 120
RARE2_CFG.multiclassPushDistM      = 80

-- v0.10.0: racecraft mais vivo por padrão (mais brigas e ultrapassagens).
RARE2_CFG.stuckBehindDelay           = 0.8
RARE2_CFG.stuckBehindRampTime        = 5.0
RARE2_CFG.draftCommitRampGate        = 0.15
RARE2_CFG.draftCommitTime            = 3.5
RARE2_CFG.stuckBehindAggressionBoost = 0.26
RARE2_CFG.stuckBehindPushBoost       = 0.034
RARE2_CFG.draftCommitAggBoost        = 0.32
RARE2_CFG.draftCommitPushBoost       = 0.070
RARE2_CFG.draftCommitTopSpeedBoost   = 0.050

RARE2_CFG.difficultyTopSpeedScale    = 0.10

RARE2_CFG.lap1SuppressBase = 1.0
RARE2_CFG.lap1RampFrac     = 0.0
RARE2_CFG.lap1PaceBoost    = 0.05

RARE2_CFG.cleanAirTopSpeedBoost    = 0.020
RARE2_CFG.cleanAirPushBoost        = 0.018
RARE2_CFG.huntPaceBoost            = 0.030
RARE2_CFG.huntDuration             = 50.0
RARE2_CFG.tigerChancePerLap        = 0.07

local MEMORY_FILE = "RaceFlow_memory.lua"

local RARE2_MEMORY = {
  tracks = {},
  drivers = {},
}

---------------------------------------------------------------------
-- CONFIG SAVE / LOAD
---------------------------------------------------------------------
local CONFIG_FILE = "RaceFlow_config.lua"
local LEGACY_CONFIG_FILE = "RARE_2_0_config.lua"

local function serializeTable(tbl, indent)
  indent = indent or ""
  local nextIndent = indent .. "  "
  local parts = {}
  table.insert(parts, "{\n")

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

    table.insert(parts, key .. valueStr .. ",\n")
  end

  table.insert(parts, indent .. "}")
  return table.concat(parts)
end

local function saveConfigToFile()
  local f, err = io.open(CONFIG_FILE, "w")
  if not f then
    ac.log(string.format("[RaceFlow] Failed to save config: %s", tostring(err)))
    return false
  end

  f:write("return ")
  f:write(serializeTable(RARE2_CFG, ""))
  f:write("\n")
  f:close()

  ac.log("[RaceFlow] Config saved to " .. CONFIG_FILE)
  return true
end

local function deepMerge(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function loadConfigFromFile()
  local chunk, err = loadfile(CONFIG_FILE)
  if not chunk then
    chunk, err = loadfile(LEGACY_CONFIG_FILE)
  end
  if not chunk then
    ac.log(string.format("[RaceFlow] No config file to load or error: %s", tostring(err)))
    return
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[RaceFlow] Failed to load config table: " .. tostring(data))
    return
  end
  deepMerge(RARE2_CFG, data)
  ac.log("[RaceFlow] Config loaded successfully")
end

local function saveMemoryToFile()
  local f, err = io.open(MEMORY_FILE, "w")
  if not f then
    ac.log(string.format("[RaceFlow] Failed to save memory: %s", tostring(err)))
    return
  end

  f:write("return ")
  f:write(serializeTable(RARE2_MEMORY, ""))
  f:write("\n")
  f:close()

  ac.log("[RaceFlow] Memory saved to " .. MEMORY_FILE)
end

local function loadMemoryFromFile()
  local chunk, err = loadfile(MEMORY_FILE)
  if not chunk then
    ac.log(string.format("[RaceFlow] Memory load skipped (%s)", tostring(err)))
    return
  end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    ac.log("[RaceFlow] Failed to load memory table from " .. MEMORY_FILE)
    return
  end

  for k in pairs(RARE2_MEMORY) do
    RARE2_MEMORY[k] = nil
  end
  for k, v in pairs(data) do
    RARE2_MEMORY[k] = v
  end

  ac.log("[RaceFlow] Memory loaded from " .. MEMORY_FILE)
end

_G.RARE2_API = {
  saveConfig = saveConfigToFile,
  loadConfig = loadConfigFromFile,
  saveMemory = saveMemoryToFile,
  loadMemory = loadMemoryFromFile,
  getMemory  = function() return RARE2_MEMORY end,
  markConfigDirty = function()
    if _G.RARE2_API then _G.RARE2_API._configDirty = true end
  end,
  resetToDefaults = function()
    RARE2_CFG.aggression = 50
    RARE2_CFG.difficultyBoost = 100
    RARE2_CFG.paceStrength = 65
    -- v0.10.0: racecraft defaults (spicier racing).
    RARE2_CFG.stuckBehindDelay = 0.8
    RARE2_CFG.stuckBehindRampTime = 5.0
    RARE2_CFG.draftCommitRampGate = 0.15
    RARE2_CFG.draftCommitTime = 3.5
    RARE2_CFG.stuckBehindAggressionBoost = 0.26
    RARE2_CFG.stuckBehindPushBoost = 0.034
    RARE2_CFG.draftCommitAggBoost = 0.32
    RARE2_CFG.draftCommitPushBoost = 0.070
    RARE2_CFG.draftCommitTopSpeedBoost = 0.050
    RARE2_CFG.huntDuration = 50.0
    RARE2_CFG.tigerChancePerLap = 0.07
    if RARE2_CFG.strategy then
      RARE2_CFG.strategy.manualRaceLaps = 20
      RARE2_CFG.strategy.forcedStops = 1
      RARE2_CFG.strategy.tireChangeEnabled = true
      RARE2_CFG.strategy.tireFreshnessPct = 50
    end
    -- NOTE v0.5.0: vsc reset block removed with the VSC system.
    -- Old saved configs may still contain cfg.vsc; it is ignored.
    if RARE2_CFG.caution then
      local c = RARE2_CFG.caution
      c.enabled = false
      c.fcySpeedKmh = 80
      c.yellowSpeedKmh = 80
      c.minDuration = 60
      c.maxDuration = 180
      c.fcyChance = 0.5
      c.autoTrigger = true
      c.minDrivenKm = 0.5
      c.cooldown = 10
      c.overtakeEnabled = true
      c.giveBackTime = 10
      c.overtimePenalty = 5
    end
    if RARE2_CFG.tracklimits then
      local t = RARE2_CFG.tracklimits
      t.enabled = false
      t.trackLimitsEnabled = true
      t.penaltiesEnabled = true
      t.maxWarnings = 4
      t.penaltyTime = 5
      t.cooldown = 7
      t.extraTime = 10
      t.strictPit = false
      t.waitTime = 1.9
      t.wheels = 4
      t.aiEnabled = true
      t.aiServe = false
      t.qualiReset = true
      t.finishAdd = true
      t.gamePenaltyCompat = true
      t.syncWithCMRT = true
      t.minOffTime = 0.25
      t.pitSpeedEnabled = true
      t.pitLimitKmh = 80
      t.pitGraceSec = 1.0
    end
    if RARE2_CFG.hudEvents then
      local h = RARE2_CFG.hudEvents
      h.showCaution = (h.showCaution ~= false)
      h.showTrackLimits = (h.showTrackLimits ~= false)
      h.showStrategy = (h.showStrategy ~= false)
      h.showPosition = (h.showPosition ~= false)
      h.showSession = (h.showSession ~= false)
      h.showLearning = (h.showLearning == true)
      h.compact = (h.compact == true)
      h.progressBars = (h.progressBars ~= false)
      h.blink = (h.blink ~= false)
      h.scale = clamp(tonumber(h.scale) or 1.0, 0.7, 1.5)
    end
    if RARE2_CFG.githubUpdate then
      RARE2_CFG.githubUpdate.enabled = true
      RARE2_CFG.githubUpdate.repo = "Silxyst/RaceFlow-V2"
      RARE2_CFG.githubUpdate.checkIntervalHours = 24
      RARE2_CFG.githubUpdate.notifyOnStartup = true
    end
    if RARE2_CFG.webui then
      RARE2_CFG.webui.enabled = false
      RARE2_CFG.webui.port = 8080
      RARE2_CFG.webui.authToken = ""
    end
    if RARE2_CFG.ui then
      RARE2_CFG.ui.accent = "cyan"
      RARE2_CFG.ui.bgAlpha = 1.0
      RARE2_CFG.ui.corner = 6
      RARE2_CFG.ui.compactHeaders = false
    end
    saveConfigToFile()
    return true
  end,
}

-- ==========================================================
-- GITHUB UPDATE CHECKER (async, uses ac.webRequest)
-- ==========================================================
local githubState = {
  lastCheck = 0,
  checkInterval = 0,
  latestVersion = nil,
  hasUpdate = false,
  changelog = "",
  checking = false,
  error = nil,
}

-- Cached availability probe: ac.webRequest does not exist in some CSP
-- builds (incl. 0.3.0-preview542). Without this guard the check logs
-- EVERY frame (~400+ lines/session). Probe once, stay silent afterwards.
local webReqMissingLogged = false
local function githubCheckUpdates(cfg, force)
  if not cfg.githubUpdate.enabled then return end
  if not ac.webRequest then
    if not webReqMissingLogged then
      webReqMissingLogged = true
      githubState.error = "ac.webRequest indisponível nesta build do CSP (auto-check desativado; use verificação manual se disponível)"
      ac.log("[RaceFlow GitHub] ac.webRequest not available in this CSP build; automatic checks disabled (logged once)")
    end
    return
  end

  local now = os.clock()
  local interval = (cfg.githubUpdate.checkIntervalHours or 24) * 3600
  if not force and githubState.lastCheck > 0 and (now - githubState.lastCheck) < interval then
    return
  end
  if githubState.checking then return end

  githubState.checking = true
  githubState.error = nil
  githubState.lastCheck = now

  local url = string.format("https://api.github.com/repos/%s/releases/latest", cfg.githubUpdate.repo or "Silxyst/RaceFlow-V2")
  ac.log("[RaceFlow GitHub] Checking for updates: " .. url)

  ac.webRequest({
    url = url,
    method = "GET",
    headers = { ["User-Agent"] = "RaceFlow-AC-App" },
    callback = function(err, response)
      githubState.checking = false
      if err then
        githubState.error = tostring(err)
        ac.log("[RaceFlow GitHub] Request failed: " .. githubState.error)
        return
      end
      if not response or response.status ~= 200 then
        githubState.error = "HTTP " .. tostring(response and response.status or "nil")
        ac.log("[RaceFlow GitHub] " .. githubState.error)
        return
      end

      local ok, data = pcall(function() return ac.decodeJson(response.body) end)
      if not ok or not data then
        githubState.error = "JSON parse failed"
        ac.log("[RaceFlow GitHub] " .. githubState.error)
        return
      end

      local tag = data.tag_name or data.name or ""
      local version = tag:gsub("^v", "")
      githubState.latestVersion = version
      githubState.changelog = data.body or "No changelog provided."

      -- Compare versions (simple semantic version compare)
      local function parseVer(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
        return tonumber(major or 0), tonumber(minor or 0), tonumber(patch or 0)
      end
      local cM, cm, cP = parseVer(SCRIPT_VERSION)
      local lM, lm, lP = parseVer(version)
      githubState.hasUpdate = (lM > cM) or (lM == cM and lm > cm) or (lM == cM and lm == cm and lP > cP)

      ac.log(string.format("[RaceFlow GitHub] Current: %s, Latest: %s, Update: %s",
        SCRIPT_VERSION, version, githubState.hasUpdate and "YES" or "NO"))
    end
  })
end

-- ==========================================================
-- MAIN UPDATE (GitHub + WebUI + rolling + strategy + AI)
-- NOTE: Pure VSC system removed in v0.5.0 (see CHANGELOG).
-- ==========================================================
local configLoaded = false
local memoryLoaded = false
local githubStartupChecked = false

local memorySaveCooldown = 0.0
local memorySaveInterval = 12.0
local configSaveCooldown = 0.0
local configSaveInterval = 1.0

function script.update(dt)
  local sim = ac.getSim()
  if not sim then return end

  if not configLoaded then
    loadConfigFromFile()
    configLoaded = true
  end

  if not memoryLoaded and _G.RARE2_API and _G.RARE2_API.loadMemory then
    _G.RARE2_API.loadMemory()
    memoryLoaded = true
  end

  -- GitHub update check on startup + periodic (self-throttled inside)
  if RARE2_CFG.githubUpdate and RARE2_CFG.githubUpdate.enabled then
    if not githubStartupChecked and RARE2_CFG.githubUpdate.notifyOnStartup then
      githubStartupChecked = true
      githubCheckUpdates(RARE2_CFG, true) -- force check on startup
    else
      githubCheckUpdates(RARE2_CFG, false) -- interval check
    end
  end

  if sim.isOnlineRace then return end
  if not sim.isSessionStarted then return end
  if not RARE2_CFG.enabled then return end

  -- NOTE v0.5.0: VSC system removed (was here).

  -- Web UI (remote file-based polling)
  if webui and webui.update then
    webui.update(dt, sim, RARE2_CFG)
  end

  -- Rolling Start
  local rollingActive = false
  if rolling and rolling.update then
    rollingActive = (rolling.update(dt, sim, RARE2_CFG) == true)
  end

  if not rollingActive then
    if strategy and strategy.update then
      strategy.update(dt, sim, RARE2_CFG)
    end
  end

  if ai and ai.update then
    local okA, errA = pcall(ai.update, dt, sim, RARE2_CFG)
    if not okA then ac.log("[RaceFlow] ai.update: " .. tostring(errA)) end
  end

  -- Caution so its AI speed caps win over pace/strategy caps.
  -- Skipped during rolling start (formation has its own control).
  -- pcall: a module error must never kill the whole frame.
  if not rollingActive and caution and caution.update then
    local okC, errC = pcall(caution.update, dt, sim, RARE2_CFG)
    if not okC then ac.log("[RaceFlow] caution.update: " .. tostring(errC)) end
  end

  -- v0.11.1: Force AI to overtake a stopped/slow/off-track PLAYER
  -- instead of forming a queue. Runs after AI+Caution so it can
  -- override any cap (including FCY) when the player is clearly not
  -- racing (off track or crawling). Minimal, pcall-guarded.
  do
    local ok, pcar = pcall(ac.getCar, 0)
    if ok and pcar and not pcar.isInPitlane and not pcar.isInPit then
      local pSpd = tonumber(pcar.speedKmh) or 99
      local pOff = (tonumber(pcar.wheelsOutside) or 0) >= 2 or pcar.isLapValid == false
      local isBlocking = (pSpd < 5) or (pSpd < 12 and pOff)
      if isBlocking then
        local pPos = pcar.splinePosition
        local L = tonumber(sim.trackLengthM) or 0
        if pPos ~= nil and L > 0 then
          for i = 1, (sim.carsCount or 0) - 1 do
            local ok2, car = pcall(ac.getCar, i)
            if ok2 and car and car.isAIControlled and not car.isInPitlane and not car.isInPit then
              local aPos = car.splinePosition
              if aPos ~= nil then
                local gapFwd = (tonumber(pPos) - tonumber(aPos)) % 1
                if gapFwd > 0.002 and gapFwd < 0.03 then -- ~8-120m behind
                  pcall(physics.setAITopSpeed, i, 320)
                  pcall(physics.setAIThrottleLimit, i, 1.0)
                  if physics.setAIAggression then pcall(physics.setAIAggression, i, 1.0) end
                end
              end
            end
          end
        end
      end
    end
  end

  -- Track limits AFTER caution (uses pit/brake checks + teleport +
  -- result APIs, no fight over AI top speed except penalized AI slowdown).
  if not rollingActive and tracklimits and tracklimits.update then
    local okT, errT = pcall(tracklimits.update, dt, sim, RARE2_CFG)
    if not okT then ac.log("[RaceFlow] tracklimits.update: " .. tostring(errT)) end
  end

  memorySaveCooldown = math.max(0.0, memorySaveCooldown - dt)
  if _G.RARE2_API and _G.RARE2_API._memoryDirty and memorySaveCooldown <= 0.0 then
    if _G.RARE2_API.saveMemory then
      pcall(_G.RARE2_API.saveMemory)
    end
    _G.RARE2_API._memoryDirty = false
    memorySaveCooldown = memorySaveInterval
  end

  configSaveCooldown = math.max(0.0, configSaveCooldown - dt)
  if _G.RARE2_API and _G.RARE2_API._configDirty and configSaveCooldown <= 0.0 then
    if _G.RARE2_API.saveConfig then
      pcall(_G.RARE2_API.saveConfig)
    end
    _G.RARE2_API._configDirty = false
    configSaveCooldown = configSaveInterval
  end
end

-- ==========================================================
-- EXPORTS for UI / other modules
-- NOTE v0.5.0: VSC exports removed with the VSC system.
-- GitHub state is LOCAL single-source (no dual-state modules).
-- v0.6.0: caution exports (module is single-source).
-- ==========================================================
_G.RARE2_API.getCautionState = function() return caution and caution.getState and caution.getState() or {} end
_G.RARE2_API.cautionManualTrigger = function(sim, cfg) return caution and caution.manualTrigger and caution.manualTrigger(sim or ac.getSim(), cfg or RARE2_CFG) end
_G.RARE2_API.getTrackLimitsState = function() return tracklimits and tracklimits.getState and tracklimits.getState() or {} end
_G.RARE2_API.getStrategyState = function(cfg) return strategy and strategy.getState and strategy.getState(cfg or RARE2_CFG) or {} end
_G.RARE2_API.githubCheckUpdates = function(cfg, force)
  githubCheckUpdates(cfg or RARE2_CFG, force)
end
_G.RARE2_API.githubGetState = function()
  return {
    checking = githubState.checking,
    lastCheck = githubState.lastCheck,
    latestVersion = githubState.latestVersion,
    currentVersion = SCRIPT_VERSION,
    hasUpdate = githubState.hasUpdate,
    changelog = githubState.changelog,
    error = githubState.error,
    tagName = githubState.tagName,
    publishedAt = githubState.publishedAt,
    htmlUrl = githubState.htmlUrl,
    repo = RARE2_CFG.githubUpdate and RARE2_CFG.githubUpdate.repo or "Silxyst/RaceFlow-V2",
  }
end
_G.RARE2_API.webuiGetState = function() return webui and webui.getState and webui.getState() or {} end

-- ==========================================================
-- WINDOWS
-- ==========================================================
local function drawFallbackIfMissingModules()
  ui.pushFont(ui.Font.Title)
  ui.textAligned("RaceFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
  ui.popFont()
  ui.newLine(4)
  ui.textWrapped("RaceFlow modules failed to load. Check custom_shaders_patch.log for require() errors.")
  ui.newLine(4)
  ui.separator()
  ui.text("Module status:")
  local names = {"src.ui", "src.ai_controller", "src.rolling_start", "src.race_strategy", "src.caution", "src.tracklimits", "src.webui"}
  for _, n in ipairs(names) do
    ui.text((modStatus[n] == "OK" and "✓ " or "✗ ") .. n .. ": " .. tostring(modStatus[n] or "not attempted"))
  end
end

function script.windowMain()
  local sim = ac.getSim()
  if ui_root and ui_root.draw then
    ui_root.draw(sim, RARE2_CFG)
  else
    drawFallbackIfMissingModules()
  end
end

function script.windowSetup()
  local sim = ac.getSim()
  if ui_root and ui_root.draw then
    ui_root.draw(sim, RARE2_CFG)
  else
    ui.pushFont(ui.Font.Title)
    ui.textAligned("RaceFlow", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
    ui.popFont()
    drawFallbackIfMissingModules()
  end
end

function script.windowMainSettings()
  if ui.checkbox("Show window in setup", ac.isWindowOpen("main_setup")) then
    ac.setWindowOpen("main_setup", not ac.isWindowOpen("main_setup"))
  end
end

---------------------------------------------------------------------
-- EXTRA HUD: live race events (caution + track limits) - v0.7.0
-- Small overlay window; every read is guarded so it never crashes.
---------------------------------------------------------------------
-- v0.12.0: Full-featured, customizable Race Events HUD.
-- Each section honors RARE2_CFG.hudEvents toggles; visuals degrade gracefully.
local function hudPulse(speed, lo, hi)
  local t = (os.clock() or 0) * (speed or 4)
  local s = (math.sin(t) + 1) / 2
  return lo + (hi - lo) * s
end

local function hudBar(frac, hudCfg)
  if hudCfg and hudCfg.progressBars == false then return end
  frac = math.max(0, math.min(1, tonumber(frac) or 0))
  if ui.progressBar then
    pcall(ui.progressBar, frac, vec2(-1, 10))
  else
    local n = math.floor(frac * 20 + 0.5)
    ui.textDisabled("[" .. string.rep("█", n) .. string.rep("░", 20 - n) .. "]")
  end
end

local function hudBlinkText(text, color, hudCfg, forceStatic)
  local doBlink = hudCfg and hudCfg.blink ~= false and not forceStatic
  if doBlink and math.floor((os.clock() or 0) * 2.5) % 2 == 1 then
    ui.textDisabled(text)
  else
    if color then ui.textColored(text, color) else ui.text(text) end
  end
end

local function drawRaceEventsBody()
    local sim = ac.getSim()
    local inSession = sim and sim.isSessionStarted
    local hudCfg = (RARE2_CFG and RARE2_CFG.hudEvents) or {}
    local showCaution = hudCfg.showCaution ~= false
    local showLimits  = hudCfg.showTrackLimits ~= false
    local showStrategy= hudCfg.showStrategy ~= false
    local showPos     = hudCfg.showPosition ~= false
    local showSess    = hudCfg.showSession ~= false
    local showLearn   = hudCfg.showLearning == true
    local compact     = hudCfg.compact == true
    local amber = rgbm and rgbm(1.0, 0.78, 0.20, hudCfg.blink == false and 1.0 or hudPulse(4, 0.75, 1.0)) or nil
    local red   = rgbm and rgbm(1.0, 0.35, 0.35, hudCfg.blink == false and 1.0 or hudPulse(5, 0.7, 1.0)) or nil
    local cyan  = rgbm and rgbm(0.22, 0.88, 1.00, 1.0) or nil

    -- Header: version + live status dot
    do
      local v = _G.RACEFLOW_VERSION or SCRIPT_VERSION or "?"
      ui.textDisabled("RaceFlow v" .. tostring(v) .. (inSession and " • LIVE" or " • SETUP"))
      if not compact then ui.separator() end
    end

    -- Session info (when enabled)
    if showSess then
      local track = ac.getTrackName and pcall(ac.getTrackName) and ac.getTrackName() or ""
      local sessName = ""
      if sim and ac.getSessionName then
        local ok, n = pcall(ac.getSessionName, sim.currentSessionIndex)
        if ok and n then sessName = tostring(n) end
      end
      if sessName ~= "" or track ~= "" then
        local line = ""
        if sessName ~= "" then line = sessName end
        if track ~= "" then line = line .. (line ~= "" and " • " or "") .. track end
        if not compact then
          ui.textDisabled(line)
          if sim and sim.sessionTimeLeft and sim.sessionTimeLeft > 0 then
            local mins = math.floor(sim.sessionTimeLeft / 60000)
            local secs = math.floor((sim.sessionTimeLeft % 60000)/1000)
            ui.textDisabled(string.format("⏱ %02d:%02d restante", mins, secs))
          end
        else
          ui.textDisabled(line)
        end
      end
      if not compact then ui.separator() end
    end

    -- Position / lap (when enabled and in session)
    if showPos and inSession then
      local ok, pcar = pcall(ac.getCar, 0)
      if ok and pcar then
        local pos = pcar.racePosition or 0
        local lap = pcar.lapCount or 0
        local spd = math.floor(pcar.speedKmh or 0)
        local gear = pcar.gear or 0
        ui.text(string.format("🏁 P%d • L%d • %d km/h • G%d", pos, lap+1, spd, gear))
        if not compact then
          local fuel = pcar.fuel or 0
          local maxF = pcar.maxFuel or 100
          local pct = maxF > 0 and (fuel/maxF*100) or 0
          ui.textDisabled(string.format("⛽ %.1f L (%d%%) • Voltas: %d", fuel, math.floor(pct), lap+1))
        end
      end
      if not compact then ui.separator() end
    end

    -- Caution status
    if showCaution then
      local cs = _G.RARE2_API and _G.RARE2_API.getCautionState and _G.RARE2_API.getCautionState() or {}
      if cs.active then
        if cs.mode == "FCY" then
          hudBlinkText(string.format("🟡 FCY %.0fs / %.0fs", cs.timer or 0, cs.duration or 0), amber, hudCfg)
        else
          hudBlinkText(string.format("🟡 YELLOW S%s %.0fs", tostring(cs.sector), cs.timer or 0), amber, hudCfg)
        end
        if (cs.duration or 0) > 0 then hudBar((cs.timer or 0) / cs.duration, hudCfg) end
        if cs.reason and cs.reason ~= "" then ui.textDisabled("→ " .. tostring(cs.reason)) end
        if cs.overtake then
          hudBlinkText(string.format("⛔ Devolva p/ %s: %.0fs",
            tostring(cs.overtake.name), cs.overtake.timer or 0), red, hudCfg)
          if (cs.overtake.total or 0) > 0 then hudBar((cs.overtake.timer or 0) / cs.overtake.total, hudCfg) end
        end
      else
        ui.textDisabled("🟢 Track green")
        if not compact and cs.cooldown and cs.cooldown > 0 then
          ui.textDisabled(string.format("Cooldown: %.0fs", cs.cooldown))
        end
      end
      if not compact then ui.separator() end
    end

    -- Track limits status (player)
    if showLimits then
      local ts = _G.RARE2_API and _G.RARE2_API.getTrackLimitsState and _G.RARE2_API.getTrackLimitsState() or {}
      if ts.penaltyActive and (ts.timeLeft or 0) > 0 then
        hudBlinkText(string.format("🛑 Penalty: %.1fs%s", ts.timeLeft, ts.serving and " (serving)" or ""), red, hudCfg)
        if (ts.origTime or 0) > 0 then hudBar((ts.timeLeft or 0) / ts.origTime, hudCfg) end
        if not ts.serving then ui.textDisabled("⏸ Stop in pit + hold brake") end
      elseif (ts.warn or 0) > 0 then
        ui.text(string.format("⚠ Warnings: %d/%d", ts.warn, ts.maxWarn or 4))
        if ts.lastEvent and ts.lastEvent ~= "" and not compact then
          ui.textDisabled("↳ " .. tostring(ts.lastEvent))
        end
      else
        ui.textDisabled("⚖ No warnings")
      end
      if ts.pitAlert then
        hudBlinkText("🚧 PIT SPEED: reduza!", red, hudCfg)
      end
      if (ts.gamePenApi and (ts.gamePen or 0) > 0.5) then
        ui.textDisabled(string.format("🎮 Game penalty: %.1fs", ts.gamePen))
      end
      if (ts.aiWithPenalties or 0) > 0 then
        ui.textDisabled(string.format("🤖 AI penalized: %d", ts.aiWithPenalties))
      elseif not compact and (ts.aiWithWarnings or 0) > 0 then
        ui.textDisabled(string.format("🤖 AI warnings: %d", ts.aiWithWarnings))
      end
      if not compact then ui.separator() end
    end

    -- Strategy (next pit)
    if showStrategy and inSession then
      local st = _G.RARE2_API and _G.RARE2_API.getStrategyState and _G.RARE2_API.getStrategyState(RARE2_CFG) or {}
      if st and st.cars and #st.cars > 0 then
        -- Find player's next pit or nearest AI
        local nextPit = nil
        for _, c in ipairs(st.cars) do
          if c.index == 0 then nextPit = c.nextPit; break end
        end
        if nextPit then
          ui.textDisabled(string.format("⛽ Próximo pit: volta %d", nextPit))
        else
          ui.textDisabled("⛽ Sem pit agendado")
        end
        if not compact and st.totalLaps then
          ui.textDisabled(string.format("Total: %d voltas", st.totalLaps))
        end
      else
        ui.textDisabled("⛽ Estratégia: aguardando dados")
      end
      if not compact then ui.separator() end
    end

    -- Learning (when enabled)
    if showLearn then
      local mem = _G.RARE2_API and _G.RARE2_API.getMemory and _G.RARE2_API.getMemory() or nil
      if mem and mem.tracks then
        local cnt = 0
        for _ in pairs(mem.tracks) do cnt = cnt + 1 end
        ui.textDisabled(string.format("📚 Learning: %d pistas memorizadas", cnt))
        if not compact then
          local trackId = ac.getTrackID and pcall(ac.getTrackID) and ac.getTrackID() or (sim and sim.trackName or "")
          ui.textDisabled("Pista atual: " .. tostring(trackId))
        end
      else
        ui.textDisabled("📚 Learning: sem dados")
      end
    end

    if not inSession then
      ui.newLine(2)
      ui.textDisabled("Live data appears during the session.")
    end
end

function script.windowRaceEvents()
  -- push/pop always paired; only the data body is protected.
  ui.pushFont(ui.Font.Title)
  ui.text("RACE EVENTS")
  ui.popFont()
  local ok = pcall(drawRaceEventsBody)
  if not ok then
    ui.textDisabled("Events HUD unavailable.")
  end
end