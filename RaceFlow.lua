SCRIPT_NAME = "RaceFlow"
SCRIPT_VERSION = "0.7.0"
_G.RACEFLOW_VERSION = "0.7.0"

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
  },

  -- NEW: GitHub update checker
  githubUpdate = {
    enabled = true,
    repo = "Silxyst/RaceFlow-V2",    -- GitHub repo (owner/repo)
    checkIntervalHours = 24,         -- auto-check interval
    notifyOnStartup = true,          -- check on app load
  },

  -- NEW: Web UI remote
  webui = {
    enabled = false,
    port = 8080,
    authToken = "",                  -- optional bearer token
  },

  packs = { pace = true, ers = true, traffic = true, hud = true },
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

RARE2_CFG.stuckBehindDelay           = 1.0
RARE2_CFG.stuckBehindRampTime        = 6.0
RARE2_CFG.draftCommitRampGate        = 0.20
RARE2_CFG.draftCommitTime            = 3.5
RARE2_CFG.stuckBehindAggressionBoost = 0.22
RARE2_CFG.stuckBehindPushBoost       = 0.028
RARE2_CFG.draftCommitAggBoost        = 0.28
RARE2_CFG.draftCommitPushBoost       = 0.060
RARE2_CFG.draftCommitTopSpeedBoost   = 0.045

RARE2_CFG.difficultyTopSpeedScale    = 0.10

RARE2_CFG.lap1SuppressBase = 1.0
RARE2_CFG.lap1RampFrac     = 0.0
RARE2_CFG.lap1PaceBoost    = 0.05

RARE2_CFG.cleanAirTopSpeedBoost    = 0.020
RARE2_CFG.cleanAirPushBoost        = 0.018
RARE2_CFG.huntPaceBoost            = 0.030
RARE2_CFG.huntDuration             = 45.0
RARE2_CFG.tigerChancePerLap        = 0.05

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
    ai.update(dt, sim, RARE2_CFG)
  end

  -- Caution so its AI speed caps win over pace/strategy caps.
  -- Skipped during rolling start (formation has its own control).
  if not rollingActive and caution and caution.update then
    caution.update(dt, sim, RARE2_CFG)
  end

  -- Track limits AFTER caution (uses pit/brake checks + teleport +
  -- result APIs, no fight over AI top speed except penalized AI slowdown).
  if not rollingActive and tracklimits and tracklimits.update then
    tracklimits.update(dt, sim, RARE2_CFG)
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
function script.windowRaceEvents()
  local ok = pcall(function()
    local sim = ac.getSim()
    local inSession = sim and sim.isSessionStarted

    ui.pushFont(ui.Font.Title)
    ui.text("RACE EVENTS")
    ui.popFont()

    -- Caution status
    local cs = _G.RARE2_API and _G.RARE2_API.getCautionState and _G.RARE2_API.getCautionState() or {}
    if cs.active then
      if cs.mode == "FCY" then
        ui.text(string.format("🟡 FCY %.0fs/%.0fs", cs.timer or 0, cs.duration or 0))
      else
        ui.text(string.format("🟡 YELLOW S%s %.0fs", tostring(cs.sector), cs.timer or 0))
      end
      if cs.reason and cs.reason ~= "" then ui.textDisabled(tostring(cs.reason)) end
    else
      ui.textDisabled("🟢 Track green")
    end

    ui.separator()

    -- Track limits status (player)
    local ts = _G.RARE2_API and _G.RARE2_API.getTrackLimitsState and _G.RARE2_API.getTrackLimitsState() or {}
    if ts.penaltyActive and (ts.timeLeft or 0) > 0 then
      ui.text(string.format("🛑 Penalty: %.1fs%s", ts.timeLeft, ts.serving and " (serving)" or ""))
      if not ts.serving then ui.textDisabled("Stop in pit + hold brake") end
    elseif (ts.warn or 0) > 0 then
      ui.text(string.format("⚠ Warnings: %d/%d", ts.warn, ts.maxWarn or 4))
    else
      ui.textDisabled("⚖ No warnings")
    end
    if (ts.aiWithPenalties or 0) > 0 then
      ui.textDisabled(string.format("AI penalized: %d", ts.aiWithPenalties))
    end

    if not inSession then
      ui.newLine(2)
      ui.textDisabled("Live data appears during the session.")
    end
  end)
  if not ok then
    ui.textDisabled("Events HUD unavailable.")
  end
end