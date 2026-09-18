-- ApexFlow AI Controller v3 — Race Logic (reescrita v0.30.0)
-- Foco: correr de verdade, disputar limpo, pensar antes de passar.
-- Sem danger/memory/entryCap: ritmo livre, teto alto, freio tardio.
-- API compat: update, applyProfileAggression, getSessionCarStats, multiclassClassifyNow

local M = {}

M._implProbe = M._implProbe or {}
M._eventProbe = M._eventProbe or {}
M._eventLog = M._eventLog or {}

_G.APEXFLOW_API = _G.APEXFLOW_API or {}
local APEXFLOW_API = _G.APEXFLOW_API

local drivers = {}
local lastSessionIndex = -1
local lastCarsCount = -1
local lastAggression = -1

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function lerp(a, b, t) return a + (b - a) * t end

local function hash01(s)
  local h = 0
  s = tostring(s or "")
  for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000000 end
  return h / 1000000
end

local function safeNumber(getter, default)
  local ok, v = pcall(getter)
  if ok then v = tonumber(v); if v ~= nil then return v end end
  return default
end

local function applyBrakeHintMul(curr, mul, cfg)
  if cfg and cfg.invertBrakeHint then return curr * mul end
  return curr / mul
end

local function getTrackId(sim)
  if ac.getTrackID then
    local ok, id = pcall(ac.getTrackID)
    if ok and id and id ~= "" then return id end
  end
  return sim and sim.trackName or "unknown"
end

-- Perfis: divide grid por hash (estável por sessão)
local function rebuildDrivers(sim, cfg)
  drivers = {}
  local carsCount = sim.carsCount or 0
  local list = {}
  for i = 0, carsCount - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and car.isAIControlled then
      local okN, nm = pcall(ac.getDriverName, i)
      if not okN or type(nm) ~= "string" or nm == "" then nm = "AI" .. i end
      list[#list + 1] = { index = i, name = nm, r = hash01(i .. "|" .. nm) }
    end
  end
  table.sort(list, function(a, b) return a.r < b.r end)
  local N = #list
  if N == 0 then return end
  local aggrNorm = clamp((cfg.aggression or 65) / 100.0, 0, 1)
  local nAttack = math.floor(N * (0.15 + 0.55 * aggrNorm) + 0.5)
  local nChill = math.floor(N * (0.50 - 0.35 * aggrNorm) + 0.5)
  if nAttack < 1 and N >= 3 then nAttack = 1 end
  if nChill < 1 and N >= 3 then nChill = 1 end
  if nAttack + nChill > N then nAttack = N - nChill end
  for pos, info in ipairs(list) do
    local class = "normal"
    if pos <= nChill then class = "chill"
    elseif pos > N - nAttack then class = "attack" end
    drivers[info.index] = {
      index = info.index, name = info.name, class = class,
      stalkTime = 0, state = "follow", stateTimer = 0, cooldown = 0,
      offsetSide = (info.index % 2 == 0) and 0.55 or -0.55,
    }
  end
end

function M.applyProfileAggression(cfg)
  cfg = cfg or (_G.APEXFLOW_CFG or {})
  for idx, d in pairs(drivers) do
    local lv = 1.0
    if d.class == "attack" then lv = 1.05
    elseif d.class == "chill" then lv = 0.96 end
    pcall(physics.setAILevel, idx, lv)
    pcall(physics.setAIAggression, idx, d.class == "attack" and 0.9 or (d.class == "chill" and 0.4 or 0.65))
  end
end

function M.getSessionCarStats(sim, cfg)
  local out = {}
  local okS, s = pcall(ac.getSim)
  sim = sim or (okS and s or nil)
  if not sim or not sim.carsCount then return out end
  for i = 0, sim.carsCount - 1 do
    local ok, car = pcall(ac.getCar, i)
    if ok and car and car.isAIControlled then
      local okN, nm = pcall(ac.getDriverName, i)
      if not okN or type(nm) ~= "string" or nm == "" then nm = "AI" .. i end
      local d = drivers[i]
      out[#out + 1] = {
        index = i, name = nm,
        class = d and d.class or "?",
        state = d and d.state or "?",
        topSpeedKmh = nil, p2w = nil,
      }
    end
  end
  return out
end

function M.multiclassClassifyNow(sim, cfg)
  return true
end

local function getRain(sim)
  local okS, s = pcall(function() return sim or ac.getSim() end)
  local sm = (okS and s) or sim
  if not sm then return 0 end
  local rain = tonumber(sm.rainIntensity) or tonumber(sm.trackWetness) or 0
  local okR, isR = pcall(function() return sm.isRaining end)
  if okR and isR then rain = math.max(rain, 0.5) end
  return rain or 0
end

function M.update(dt, sim, cfg)
  if not sim or not cfg or not cfg.enabled then return end
  if sim.isOnlineRace then return end
  if not sim.isSessionStarted then return end
  if sim.isPaused then return end
  -- Não briga com rolling formation
  if cfg._rollingStartActive == true then return end
  if sim.raceSessionType ~= nil and sim.raceSessionType ~= 3 then
    -- treino/quali: só ritmo base, sem briga
  end

  local carsCount = sim.carsCount or 0
  if carsCount <= 0 then return end
  local aggression = cfg.aggression or 65
  local sessionIndex = sim.currentSessionIndex or 0
  if sessionIndex ~= lastSessionIndex or carsCount ~= lastCarsCount or aggression ~= lastAggression then
    rebuildDrivers(sim, cfg)
    lastSessionIndex = sessionIndex
    lastCarsCount = carsCount
    lastAggression = aggression
  end
  if not next(drivers) then return end

  local trackLenM = safeNumber(function() return sim.trackLengthM end, 4000)
  if trackLenM < 100 then trackLenM = 4000 end
  local rain = getRain(sim)
  local rainHeavy = rain > 0.3
  local rainLight = rain > 0.05 and not rainHeavy

  local paceNorm = clamp((cfg.paceStrength or 78) / 100.0, 0, 1)
  local strengthBoost = clamp((cfg.difficultyBoost or 104) / 100.0, 0.70, 1.35)
  local intensity = 0.70
  if cfg.physicsPush and cfg.physicsPush.intensity ~= nil then
    intensity = clamp(cfg.physicsPush.intensity / 100.0, 0, 1)
  end
  local isRace = (sim.raceSessionType == nil or sim.raceSessionType == 3)

  -- Snapshot barato 1x/frame
  local snap = {}
  for idx, d in pairs(drivers) do
    local ok, car = pcall(ac.getCar, idx)
    if ok and car then
      snap[idx] = {
        d = d, car = car,
        sp = safeNumber(function() return car.splinePosition end, 0),
        speed = safeNumber(function() return car.speedKmh end, 0),
        lap = safeNumber(function() return car.lapCount end, 0),
        pos = safeNumber(function() return car.racePosition end, 99),
        inPit = (car.isInPitlane or car.isInPit) and true or false,
        retired = car.isRetired == true,
      }
    end
  end

  for idx, s in pairs(snap) do
    local d = s.d
    local car = s.car
    if not s.inPit and not s.retired then
      -- Base por classe: spread real para não virar trem
      local classBase = 0.0
      if d.class == "attack" then classBase = 0.09
      elseif d.class == "chill" then classBase = -0.045 end
      local j = (hash01("j|" .. idx) - 0.5) * 0.05 * (cfg.jitterScale or 1.1)
      local paceOffset = classBase * (0.5 + 0.5 * paceNorm) + j
      -- Confiança na reta: intensity empurra
      paceOffset = paceOffset + (intensity - 0.5) * 0.04

      local level = clamp((1.0 + paceOffset) * strengthBoost, 0.85, 1.35)
      local throttle = clamp((1.0 + paceOffset * 0.7) * lerp(1.0, strengthBoost, 0.7), 0.92, 1.28)
      -- TETO LIVRE: nunca ancora — reta sempre libera
      local topKmh = 320
      if d.class == "attack" then topKmh = 332
      elseif d.class == "normal" then topKmh = 324
      else topKmh = 314 end
      topKmh = topKmh + (strengthBoost - 1.0) * 150 + (intensity - 0.5) * 20
      topKmh = clamp(topKmh, 250, 350)
      local brakeHint = 1.0
      if d.class == "attack" then brakeHint = applyBrakeHintMul(brakeHint, 0.96, cfg)
      elseif d.class == "chill" then brakeHint = applyBrakeHintMul(brakeHint, 1.04, cfg) end

      -- Acha carro da frente (menor distância spline à frente, mesma volta ideal)
      local bestGap, bestRel, bestAhead = nil, nil, nil
      local bestWreckGap, bestWreck = nil, nil
      for oIdx, o in pairs(snap) do
        if oIdx ~= idx and not o.inPit and not o.retired then
          local fwd = (o.sp - s.sp) % 1
          local distM = fwd * trackLenM
          if distM > 1 and distM < 250 then
            local rel = s.speed - o.speed
            if o.speed < 8 and distM < 180 and distM > 4 then
              if not bestWreckGap or distM < bestWreckGap then
                bestWreckGap = distM; bestWreck = o
              end
            end
            -- ignora quem está muito atrás em voltas (retardatário não conta como alvo)
            if o.pos < s.pos or (o.pos == s.pos and distM < 60) then
              if not bestGap or distM < bestGap then
                bestGap = distM; bestRel = rel; bestAhead = o
              end
            end
          end
        end
      end

      -- Curva ou reta? turn.x = distância (m) até a próxima curva
      -- >120 reta | 70-120 aproximação | 25-70 freada | <25 ápice (lenta)
      local isStraight = true
      local turnDist = 9999
      if ac.getTrackUpcomingTurn then
        local okT, turn = pcall(ac.getTrackUpcomingTurn, idx)
        if okT and turn and turn.x then
          turnDist = tonumber(turn.x) or 9999
          if turnDist <= 120 then isStraight = false end
        end
      end
      -- Freada progressiva para curva lenta (ex: Bahrein T10): quanto mais perto e mais rápido, mais freia
      -- Evita ir "com tudo" e rodar na freada brusca
      if turnDist < 160 then
        local over = clamp((s.speed - 120) / 130, 0, 1) -- 120->0, 250->1
        local prox = clamp((160 - turnDist) / 160, 0, 1) -- 160m->0, 0m->1
        local brakeNeed = over * prox
        if brakeNeed > 0.05 then
          throttle = throttle * (1.0 - 0.45 * brakeNeed)
          brakeHint = applyBrakeHintMul(brakeHint, 1.0 + 0.35 * brakeNeed, cfg)
          -- teto desce junto para não reacelerar na placa de 50m
          topKmh = math.min(topKmh, math.max(70, s.speed - brakeNeed * 90))
        end
      end

      -- Chuva: mantém ritmo, só tira um pouco da ousadia
      local rainDamp = 1.0
      if rainHeavy then rainDamp = 0.65
      elseif rainLight then rainDamp = 0.85 end
      if rainHeavy then brakeHint = applyBrakeHintMul(brakeHint, 1.05, cfg) end

      -- Lado a lado na curva: alivia para não tocar
      local sideClose = (bestGap and bestGap < 9 and math.abs(bestRel or 0) < 4 and not isStraight)
      if sideClose then
        throttle = throttle * 0.92
        brakeHint = applyBrakeHintMul(brakeHint, 1.10, cfg)
      end

      -- v0.31.0: forma do dia (só acelerador ±1.5%, sem mexer em offset) + ponto de freada próprio
      do
        local ph = (hash01("form|" .. idx) * 6.28) + (s.lap / 3.0) * 6.28
        throttle = clamp(throttle * (1.0 + math.sin(ph) * 0.015), 0.85, 1.30)
        if d.brakeJitter == nil then
          d.brakeJitter = (hash01("brk|" .. idx .. "|" .. d.name) - 0.5) * 0.06
        end
        brakeHint = applyBrakeHintMul(brakeHint, 1.0 + d.brakeJitter, cfg)
      end



      -- Multiclass leve: cede para classe mais rápida, empurra mais lenta
      if cfg.multiclassEnabled and cfg._multiclassClassForIndex then
        local myTier = tonumber(cfg._multiclassClassForIndex[idx]) or 1
        -- atrás: alguém mais rápido colado?
        for oIdx, o in pairs(snap) do
          if oIdx ~= idx and not o.inPit then
            local oTier = tonumber(cfg._multiclassClassForIndex[oIdx]) or 1
            local back = (s.sp - o.sp) % 1 * trackLenM
            if oTier < myTier and back > 1 and back < 40 then
              throttle = throttle * 0.92 -- cede
              break
            end
          end
        end
      end

      -- Máquina de estados: follow -> stalk -> commit -> cooldown
      d.cooldown = math.max(0, (d.cooldown or 0) - dt)
      local st = d.state or "follow"
      -- stalk: colado há um tempo?
      if bestGap and bestGap < 60 then
        d.stalkTime = (d.stalkTime or 0) + dt
      else
        d.stalkTime = math.max(0, (d.stalkTime or 0) - dt * 2)
      end

      -- Traçado próprio: cada piloto tem sua linha + variação por volta (dinâmico, sem trenzinho)
      if d.lineBias == nil then
        d.lineBias = (hash01("line|" .. idx .. "|" .. d.name) - 0.5) * 0.5 -- ±0.25
        d.lineWobble = hash01("wob|" .. idx) * 6.28
      end
      local wantOffset = d.lineBias * 0.7
      -- na freada/curva: volta QUASE para a linha ideal (evita cruzar na lenta)
      if not isStraight then wantOffset = d.lineBias * 0.20 end
      if st == "follow" then
        local delay = (cfg.stuckBehindDelay ~= nil) and cfg.stuckBehindDelay or 0.7
        local gate = (cfg.draftCommitRampGate ~= nil) and cfg.draftCommitRampGate or 0.16
        -- pensa: SÓ em reta longa (120m+ livres), 6-150m, 0.5 m/s mais rápido
        local gapOk = bestGap and bestGap > 6 and bestGap < 150
        local relOk = bestRel and bestRel > 0.5
        local stalkOk = (d.stalkTime or 0) > delay
        local eager = (d.stalkTime or 0) / 5.0 > gate
        if isRace and isStraight and turnDist > 120 and gapOk and relOk and stalkOk and eager and d.cooldown <= 0 then
          d.state = "commit"; d.stateTimer = 0
          st = "commit"
        end
      elseif st == "commit" then
        d.stateTimer = (d.stateTimer or 0) + dt
        local commitTime = (cfg.draftCommitTime ~= nil) and cfg.draftCommitTime or 3.2
        -- durante commit: empurra com teto alto e freio tardio
        throttle = clamp(throttle + 0.055 * rainDamp, 0.92, 1.30)
        topKmh = topKmh + 16 * rainDamp
        brakeHint = applyBrakeHintMul(brakeHint, 0.95, cfg)
        wantOffset = (d.offsetSide or 0.55) * 0.55 -- 0.30 máx (suave, sem fechar a porta com tudo)
        -- aborta se: chegou perto da freada (110m), perdeu vácuo, passou tempo, alvo sumiu
        local abort = false
        if not isStraight or turnDist < 110 then abort = true end
        if not bestGap or bestGap > 200 then abort = true end
        if (bestRel or 0) < -2.5 then abort = true end
        if d.stateTimer > commitTime then abort = true end
        if abort then
          d.state = "cooldown"; d.stateTimer = 0
          d.cooldown = 2.0 + hash01("cd|" .. idx .. "|" .. tostring(s.lap)) * 2.0
          st = "cooldown"
          wantOffset = d.lineBias * 0.7
        end
      else -- cooldown: volta para sua linha
        d.stateTimer = (d.stateTimer or 0) + dt
        if d.cooldown <= 0 and d.stateTimer > 1.0 then
          d.state = "follow"; d.stateTimer = 0
        end
        wantOffset = d.lineBias * 0.7
      end

      -- Wreck à frente: desvia e passa (só em reta; na curva só alivia o pé)
      if bestWreck and bestWreckGap then
        topKmh = math.max(topKmh, 320)
        throttle = math.max(throttle, 1.0)
        if isStraight then
          wantOffset = (d.offsetSide or 0.9) * 0.35 -- ~0.30 (desvio curto e suave)
        else
          wantOffset = d.lineBias * 0.20 -- na curva não cruza: segura a linha e espera
          throttle = math.max(throttle * 0.9, 0.85)
        end
      end

      -- v0.31.0: grid parado = sem offset lateral (não joga carro para o lado na largada)
      if (s.speed or 0) < 15 and (s.lap or 0) <= 0 then wantOffset = 0 end
      -- v0.31.2: linha ULTRA-SUAVE (trocas bruscas causavam colisões sem sentido)
      -- teto ±0.30 + 0.5 m/s na reta + 0.25 m/s na curva (quase congela na freada)
      if wantOffset > 0.30 then wantOffset = 0.30
      elseif wantOffset < -0.30 then wantOffset = -0.30 end
      d.curOffset = tonumber(d.curOffset) or 0
      do
        local rate = isStraight and 0.5 or 0.25
        local step = rate * (dt or 0.016)
        if wantOffset > d.curOffset + step then d.curOffset = d.curOffset + step
        elseif wantOffset < d.curOffset - step then d.curOffset = d.curOffset - step
        else d.curOffset = wantOffset end
      end
      -- Aplica (tudo pcall, CSP 0.3.0 safe)
      local phys = (ac and ac.physics) or rawget(_G, "physics")
      if phys then
        pcall(physics.setAIThrottleLimit, idx, clamp(throttle, 0.85, 1.30))
        pcall(physics.setAILevel, idx, clamp(level, 0.85, 1.35))
        pcall(physics.setAIBrakeHint, idx, clamp(brakeHint, 0.85, 1.15))
        pcall(physics.setAITopSpeed, idx, clamp(topKmh, 240, 350))
        if physics.setAISplineOffset then
          pcall(physics.setAISplineOffset, idx, d.curOffset, false)
        end
        if physics.setAIAggression then
          local ag = d.class == "attack" and 0.85 or (d.class == "chill" and 0.45 or 0.65)
          if rainHeavy then ag = ag * 0.8 end
          pcall(physics.setAIAggression, idx, ag)
        end
      end
    end
  end
end

return M
