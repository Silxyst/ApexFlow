-- src/gap_behind.lua
-- RaceFlow Gap to Car Behind — v0.25.0
-- Conformidade iRacing/CBA: display do gap em tempo real para o carro imediatamente atrás.

local M = {}

-- RARE2_API guard
_G.RARE2_API = _G.RARE2_API or {}
local RARE2_API = _G.RARE2_API

local state = {
  gapBehindKm = 0,
  gapBehindM = 0,
  carBehindPos = 0,
  carBehindIdx = nil,
  lastUpdate = 0,
  deltaBehind = 0,      -- v0.28.2: delta tempo em segundos
  isLappedBehind = false, -- v0.28.2: azul se retardatário
}

local function getAppDataPath()
  local ok, docs = pcall(ac.getFolder, ac.FolderID.Documents)
  if not ok or not docs or docs=="" then return nil end
  return docs .. "/Assetto Corsa/"
end

local function findCarBehind(sim, myCar)
  -- v0.28.2: gap ultra-preciso com delta tempo e filtro retardatário
  local carsCount = sim and sim.carsCount or 0
  if carsCount <= 1 then return 0, nil end
  local myPos = tonumber(myCar.racePosition) or 0
  if myPos <= 0 then return 0, nil end
  local bestGap, bestIdx, bestDelta = nil, nil, nil
  local mySp = tonumber(myCar.splinePosition) or 0
  local myLap = tonumber(myCar.lapCount) or 0
  local mySpeed = tonumber(myCar.speedKmh) or 50
  for i = 1, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and not car.isInPitlane and not car.isInPit then
      local cPos = tonumber(car.racePosition) or 0
      if cPos > myPos then
        local cSp = tonumber(car.splinePosition) or 0
        local cLap = tonumber(car.lapCount) or 0
        local isLapped = cLap < myLap
        local L = tonumber(sim.trackLengthM) or 0
        if L > 0 then
          -- v0.28.3 fix: gap correto = (mySp - cSp) %1 *L, pequeno = logo atrás
          local d = ((mySp - cSp) % 1) * L
          if d > 0 and d < (L*0.5) then
            -- delta tempo = distância / velocidade média
            local avgSpeed = (mySpeed + (tonumber(car.speedKmh) or mySpeed))/2
            if avgSpeed < 10 then avgSpeed = 10 end
            local delta = d / (avgSpeed/3.6)
            if bestGap == nil or d < bestGap then
              bestGap = d
              bestIdx = i
              bestDelta = delta
              -- guarda se é retardatário para HUD azul
              state.isLappedBehind = isLapped
              state.deltaBehind = delta
            end
          end
        end
      end
    end
  end
  return bestGap, bestIdx
end

local function say(title, text)
  if ac and ac.setMessage then pcall(ac.setMessage, title, text) end
end

function M.update(dt, sim, cfg)
  if not sim or not sim.isSessionStarted or sim.isOnlineRace then return end
  local okP, pcar = pcall(ac.getCar, 0)
  if not okP or not pcar then return end

  state.lastUpdate = (os.clock() or 0)

  local myPos = tonumber(pcar.racePosition) or 0
  if myPos <= 0 then
    state.gapBehindKm = 0
    state.gapBehindM = 0
    state.carBehindPos = 0
    state.carBehindIdx = nil
    return
  end

  local gapKm, idx = findCarBehind(sim, pcar)

  if gapKm ~= nil then
    state.gapBehindKm = math.max(0, gapKm / 1000) -- converter de metros para km
    state.gapBehindM = math.max(0, gapKm)
    state.carBehindIdx = idx
    if idx then
      local okC, ccar = pcall(ac.getCar, idx)
      if okC and ccar then
        state.carBehindPos = tonumber(ccar.racePosition) or 0
      end
    end
  else
    state.gapBehindKm = 0
    state.gapBehindM = 0
    state.carBehindPos = 0
    state.carBehindIdx = nil
  end
end

function M.getState()
  return {
    gapBehindKm = state.gapBehindKm,
    gapBehindM = state.gapBehindM,
    carBehindPos = state.carBehindPos,
    carBehindIdx = state.carBehindIdx,
    lastUpdate = state.lastUpdate,
    deltaBehind = state.deltaBehind or 0,
    isLappedBehind = state.isLappedBehind or false,
  }
end

function M.forceReset()
  state.gapBehindKm = 0
  state.gapBehindM = 0
  state.carBehindPos = 0
  state.carBehindIdx = nil
  state.lastUpdate = 0
  state.deltaBehind = 0
  state.isLappedBehind = false
end

return M