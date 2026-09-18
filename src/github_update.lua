-- src/github_update.lua
-- GitHub Release Checker using ac.webRequest (CSP 0.2.7+)
-- Checks for updates asynchronously, caches result

local M = {}

local state = {
  lastCheck = 0,
  checkInterval = 0,
  latestVersion = nil,
  hasUpdate = false,
  changelog = "",
  checking = false,
  error = nil,
  tagName = "",
  publishedAt = "",
  htmlUrl = "",
}

local function parseVersion(v)
  local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
  return tonumber(major or 0), tonumber(minor or 0), tonumber(patch or 0)
end

local function versionNewer(latest, current)
  local lM, lm, lP = parseVersion(latest)
  local cM, cm, cP = parseVersion(current)
  return (lM > cM) or (lM == cM and lm > cm) or (lM == cM and lm == cm and lP > cP)
end

function M.checkUpdates(cfg, force)
  if not cfg.githubUpdate or not cfg.githubUpdate.enabled then
    return false, "disabled"
  end
  if not ac.webRequest then
    return false, "ac.webRequest not available (requires CSP 0.2.7+)"
  end
  if state.checking then
    return false, "already checking"
  end

  local now = os.clock()
  local interval = (cfg.githubUpdate.checkIntervalHours or 24) * 3600
  if not force and state.lastCheck > 0 and (now - state.lastCheck) < interval then
    return false, "interval not elapsed"
  end

  state.checking = true
  state.error = nil
  state.lastCheck = now

  local repo = cfg.githubUpdate.repo or "Silxyst/ApexFlow"
  local url = string.format("https://api.github.com/repos/%s/releases/latest", repo)
  ac.log("[ApexFlow GitHub] Checking updates: " .. url)

  ac.webRequest({
    url = url,
    method = "GET",
    headers = {
      ["User-Agent"] = "ApexFlow-AC-App/" .. (SCRIPT_VERSION or "0.4.6"),
      ["Accept"] = "application/vnd.github.v3+json",
    },
    timeout = 10000,
    callback = function(err, response)
      state.checking = false
      if err then
        state.error = tostring(err)
        state.latestVersion = nil
        state.hasUpdate = false
        ac.log("[ApexFlow GitHub] Request failed: " .. state.error)
        return
      end
      if not response or response.status ~= 200 then
        state.error = "HTTP " .. tostring(response and response.status or "nil")
        state.latestVersion = nil
        state.hasUpdate = false
        ac.log("[ApexFlow GitHub] " .. state.error)
        return
      end

      local ok, data = pcall(function() return ac.decodeJson(response.body) end)
      if not ok or not data then
        state.error = "JSON parse failed"
        state.latestVersion = nil
        state.hasUpdate = false
        ac.log("[ApexFlow GitHub] " .. state.error)
        return
      end

      state.tagName = data.tag_name or data.name or ""
      state.latestVersion = state.tagName:gsub("^v", "")
      state.changelog = data.body or "No changelog provided."
      state.publishedAt = data.published_at or ""
      state.htmlUrl = data.html_url or ""

      state.hasUpdate = versionNewer(state.latestVersion, SCRIPT_VERSION)

      ac.log(string.format("[ApexFlow GitHub] Current: %s | Latest: %s | Update: %s",
        SCRIPT_VERSION, state.latestVersion, state.hasUpdate and "YES" or "NO"))
    end
  })

  return true, "started"
end

function M.getState(cfg)
  cfg = cfg or (_G.APEXFLOW_CFG or {})
  return {
    checking = state.checking,
    lastCheck = state.lastCheck,
    latestVersion = state.latestVersion,
    currentVersion = SCRIPT_VERSION,
    hasUpdate = state.hasUpdate,
    changelog = state.changelog,
    error = state.error,
    tagName = state.tagName,
    publishedAt = state.publishedAt,
    htmlUrl = state.htmlUrl,
    repo = (cfg.githubUpdate and cfg.githubUpdate.repo) or "Silxyst/ApexFlow",
  }
end

function M.forceCheck(cfg)
  return M.checkUpdates(cfg, true)
end

function M.openReleasePage()
  if state.htmlUrl and state.htmlUrl ~= "" and ac.openWebLink then
    pcall(ac.openWebLink, state.htmlUrl)
    return true
  end
  return false
end

return M