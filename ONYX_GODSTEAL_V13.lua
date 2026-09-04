--[[ ONYX GODSTEAL V13 - Fyy-style architecture, proven-safe travel
  Sources fused:
  - Fyy Community StealAnEgg: runtime-module state layout, filter config,
    anti-afk via Idled-connection disabling, antiGuard counters, telemetry.
  - ONYX V7 (proven): gen-guard, watchdog respawn, 36-44 stud hops @1.5-2.5s
    (v473-verified safe), walk-only while CARRYING, RateLimiter-safe
    maintenance (3 plants / 2 hatches max every 3rd cycle).
  Stop: _G.__ONYX_FARM.stop = true (or re-run this file)
  Telemetry: _G.__ONYX_FARM + writefile('onyx_farm.txt')
]]
local RS   = game:GetService('ReplicatedStorage')
local WS   = game:GetService('Workspace')
local lp   = game:GetService('Players').LocalPlayer
local VU   = game:GetService('VirtualUser')
local ES       = require(RS.Client.EggState)
local Geometry = require(RS.Shared.Util.GuardAreaGeometry)
local SlotId   = require(RS.Shared.Util.AreaEggSlotIdentity)
local States   = require(RS.Shared.Types.AreaEggs).States
local line = WS.__OBJECTS.Areas.SeparationLine
WS:SetAttribute('ClientObbyAntiTp', false)

-- ============================ CONFIG =====================================
local CONFIG = {
  rarityEnabled   = false,                 -- true = only listed rarities
  rarities        = {'Divine','Eternal','Secret','Cosmic','Mythic'},
  minWeightKg     = 0,                     -- 0 = off
  maxTeleportStuds= 10000,                 -- skip eggs farther than this
  highestValueFirst = true,                -- rarity score first, weight tiebreak
  chaseSpeed      = 150,                   -- walkspeed when guard chases
  walkSpeed       = 65,
  maintenanceEvery= 3,                     -- cycles
}
local hopMin, hopMax = 36, 44             -- proven-safe window (v473)
local cadMin, cadMax = 1.5, 2.5           -- seconds between hops
local RARITY_SET = {}
for _, r in ipairs(CONFIG.rarities) do RARITY_SET[r] = true end

-- ======================= STATE / TELEMETRY ===============================
local prev = _G.__ONYX_FARM
if prev then prev.stop = true end
local myGen = (prev and prev.gen or 0) + 1
local S = {
  phase='boot', steals=(prev and prev.steals or 0), fails=(prev and prev.fails or 0),
  claims=(prev and prev.claims or 0), eggs=0, last='none', snaps=(prev and prev.snaps or 0),
  cycles=(prev and prev.cycles or 0), blockedHits=0, guardsSleeping=0,
  err='-', beat=os.clock(), stop=false, gen=myGen,
}
_G.__ONYX_FARM = S
local function telem()
  local msg = table.concat({
    'phase='..tostring(S.phase), 'steals='..tostring(S.steals), 'fails='..tostring(S.fails),
    'claims='..tostring(S.claims), 'eggs='..tostring(S.eggs),
    'last='..tostring(S.last):sub(1,20), 'err='..tostring(S.err):sub(1,60),
    'cyc='..tostring(S.cycles), 'snaps='..tostring(S.snaps),
    'blk='..tostring(S.blockedHits), 'sleep='..tostring(S.guardsSleeping),
  }, '|')
  pcall(function() writefile('onyx_farm.txt', msg) end)
end
local function alive() return not S.stop and S.gen == myGen end

-- ==================== ANTI-AFK (Fyy-style: disable Idled) ================
if not _G.__ONYX_AFK_V13 then
  _G.__ONYX_AFK_V13 = true
  local disabled = 0
  pcall(function()
    for _, conn in ipairs(getconnections(lp.Idled)) do
      pcall(function() conn:Disable() disabled = disabled + 1 end)
    end
  end)
  S.err = 'anti-afk disabled '..disabled..' idled conn(s)'
  -- VirtualUser fallback wiggle (kept from V7)
  local rng0 = Random.new()
  task.spawn(function()
    while _G.__ONYX_AFK_V13 and not S.stop do
      pcall(function()
        VU:CaptureController()
        VU:Set2DPosition(Vector2.new(rng0:NextInteger(80,500), rng0:NextInteger(80,400)))
      end)
      task.wait(25)
    end
  end)
end

-- ============== GUARD FORCE-SLEEP (Fyy technique, decompiled) ============
if not _G.__ONYX_GUARD_SLEEP then
  _G.__ONYX_GUARD_SLEEP = true
  task.spawn(function()
    while _G.__ONYX_GUARD_SLEEP and not S.stop do
      pcall(function()
        local ga = WS.__OBJECTS.Areas:FindFirstChild('GuardAreas')
        if ga then
          for _, gm in pairs(ga:GetChildren()) do
            local g = gm:FindFirstChild('Guard')
            if g and g:IsA('Model') and g:GetAttribute('GuardState') ~= 'Sleeping' then
              g:SetAttribute('Sleeping', true)
              g:SetAttribute('TargetPlayer', '')
              g:SetAttribute('WakeTargetPlayer', '')
              g:SetAttribute('GuardState', 'Sleeping')
            end
          end
        end
      end)
      task.wait(2)
    end
  end)
end

-- ===================== CHARACTER HELPERS =================================
local rng = Random.new()
local function hrp() local c = lp.Character return c and c:FindFirstChild('HumanoidRootPart') end
local function hum() local c = lp.Character return c and c:FindFirstChildOfClass('Humanoid') end
local function waitChar()
  local t0 = os.clock()
  while os.clock() - t0 < 20 do
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass('Humanoid')
    local r = c and c:FindFirstChild('HumanoidRootPart')
    if c and h and r and h.Health > 0 and not r.Anchored then return c, h, r end
    if r and r.Anchored then r.Anchored = false end
    task.wait(0.4)
  end
  return nil, nil, nil
end
local function upright()
  local h = hum() if not h then return false end
  local st = h:GetState().Name
  if st=='Running' or st=='RunningNoPhysics' or st=='Landed' then return true end
  local t0 = os.clock()
  while os.clock()-t0 < 10 do
    task.wait(0.4)
    local h2 = hum()
    if not h2 or h2.Health<=0 then return false end
    local s2 = h2:GetState().Name
    if s2=='Running' or s2=='RunningNoPhysics' or s2=='Landed' then return true end
  end
  return false
end
local function homePos()
  local ok, plot = pcall(function() return require(RS.Client.PlotState).ResolvePlot() end)
  if ok and plot and plot.PetArea then
    local pa = plot.PetArea
    return pa:IsA('BasePart') and pa.Position or pa:GetPivot().Position
  end
  return Vector3.new(464, 68, -304)
end
local function recPos(uid)
  for _, r in ES.ReadFieldEggs().Records do
    if r.Uid == uid and r.BottomCFrame then return r.BottomCFrame.Position end
  end
  return nil
end

-- ======================= GUARD SCAN (antiGuard-lite) =====================
local function guardThreat(refPos)
  local ga = WS.__OBJECTS.Areas:FindFirstChild('GuardAreas')
  if not ga then return false, 0 end
  local threat, sleeping = false, 0
  for _, gm in pairs(ga:GetChildren()) do
    local g = gm:FindFirstChild('Guard')
    if g and g:IsA('Model') then
      local gs = g:GetAttribute('GuardState')
      if gs == 'Sleeping' or gs == 'Idle' then sleeping = sleeping + 1 end
      if gs == 'Chasing' or gs == 'Waking' then
        local gr = g:FindFirstChild('HumanoidRootPart')
        if gr and (gr.Position - refPos).Magnitude < 120 then threat = true end
      end
    end
  end
  S.guardsSleeping = sleeping
  return threat, sleeping
end

-- ===================== TRAVEL (proven-safe hop engine) ===================
local function hopTo(target, stopDist)
  local r = hrp()
  if not r then return false end
  for i = 1, 16 do
    if not alive() then return false end
    if r.Anchored then r.Anchored = false end
    local d = (target - r.Position) * Vector3.new(1, 0, 1)
    if d.Magnitude <= stopDist then return true end
    local step = math.min(rng:NextInteger(hopMin, hopMax), d.Magnitude - stopDist * 0.6)
    if step <= 0 then return true end
    local dir = d.Unit
    local perp = Vector3.new(-dir.Z, 0, dir.X) * rng:NextNumber(-6, 6)
    local before = r.Position
    r.CFrame = CFrame.new(r.Position + dir * step + perp)
    task.wait(rng:NextNumber(cadMin, cadMax))
    if i % 2 == 0 then task.wait(rng:NextNumber(0.6, 1.2)) end
    local r2 = hrp()
    if not r2 then return false end
    local got = ((r2.Position - before) * Vector3.new(1, 0, 1)).Magnitude
    if got < step * 0.4 then
      S.snaps = S.snaps + 1
      telem()
      task.wait(rng:NextNumber(3, 5))
    end
    local h = hum()
    if not h or h.Health <= 0 then return false end
    r = r2
  end
  local r3 = hrp()
  return r3 ~= nil and ((target - r3.Position) * Vector3.new(1, 0, 1)).Magnitude <= stopDist + 18
end
local function walkLive(getPos, stopDist, budget, speed)
  local h, r = hum(), hrp()
  if not (h and r) then return false end
  h.WalkSpeed = speed or CONFIG.walkSpeed
  local t0 = os.clock()
  while os.clock() - t0 < budget and alive() do
    local h2, r2 = hum(), hrp()
    if not (h2 and r2 and h2.Parent) then return false end
    if r2.Anchored then r2.Anchored = false end
    if h2.Health <= 0 then return false end
    local tp = getPos()
    if not tp then return false end
    local d = (tp - r2.Position) * Vector3.new(1, 0, 1)
    if d.Magnitude <= stopDist then return true end
    h2:MoveTo(d.Unit * 12 + r2.Position)
    task.wait(0.2)
  end
  return false
end
-- carrying: WALK ONLY (hops = instant confiscation, v473-proven)
local function runHome(home, maxT)
  local h, r = hum(), hrp()
  if not (h and r) then return 'lost' end
  local lastP, stuck, side = r.Position, 0, 1
  local t0 = os.clock()
  while os.clock() - t0 < (maxT or 110) and alive() do
    local h2, r2 = hum(), hrp()
    if not (h2 and r2 and h2.Parent) then return 'lost' end
    if r2.Anchored then r2.Anchored = false end
    if h2.Health <= 0 then return 'lost' end
    local chase = guardThreat(r2.Position)
    h2.WalkSpeed = chase and CONFIG.chaseSpeed or rng:NextInteger(62, 70)
    local d = (home - r2.Position) * Vector3.new(1, 0, 1)
    if d.Magnitude <= 4 then return 'arrived' end
    local wp = d.Unit * 30 + r2.Position
    if stuck > 1 then
      local perp = Vector3.new(-d.Z, 0, d.X).Unit * side * 25
      wp = d.Unit * 14 + perp + r2.Position
      side = -side; stuck = 0
    end
    h2:MoveTo(wp)
    task.wait(0.2)
    local moved = ((r2.Position - lastP) * Vector3.new(1, 0, 1)).Magnitude
    lastP = r2.Position
    if moved < 1 then stuck = stuck + 0.2 else stuck = 0 end
  end
  local r3 = hrp()
  local dist = r3 and ((home - r3.Position) * Vector3.new(1, 0, 1)).Magnitude or 999
  return dist <= 10 and 'arrived' or 'timeout'
end

-- ===================== TARGETING (Fyy-style filters) =====================
local Rarities = nil
pcall(function() Rarities = require(RS.Data.Rarity).Rarities end)
local rc = {}
local function scoreCategory(cat)
  cat = tostring(cat)
  if rc[cat] ~= nil then return rc[cat] end
  local s = 0
  pcall(function()
    local cfg = RS.Data.Assets.Configs:FindFirstChild(cat)
    if cfg then
      local m = require(cfg)
      local rn = Rarities and Rarities[tostring(m.Rarity or 'Basic')]
      if rn and rn.RarityNumber then s = rn.RarityNumber end
    end
  end)
  rc[cat] = s
  return s
end
local function eggWeight(rec)
  local w = 0
  pcall(function() w = rec.WeightKg or rec.Weight or 0 end)
  return tonumber(w) or 0
end
local function pickBest(ref)
  local best, bs, bd = nil, -1, math.huge
  for _, rec in ES.ReadFieldEggs().Records do
    if rec.BottomCFrame and rec.State == States.Slot and not rec.HasParasite
      and Geometry.IsPastLine(line, rec.BottomCFrame.Position)
      and not SlotId.LooksLikeFirstAreaUid(rec.Uid) then
      local pos = rec.BottomCFrame.Position
      local d = (pos - ref.Position).Magnitude
      local pass = d <= CONFIG.maxTeleportStuds
      if pass and CONFIG.rarityEnabled and #CONFIG.rarities > 0 then
        pass = RARITY_SET[tostring(rec.AssetCategory)] == true
      end
      if pass and CONFIG.minWeightKg > 0 then
        pass = eggWeight(rec) >= CONFIG.minWeightKg
      end
      if pass then
        local sc = scoreCategory(rec.AssetCategory)
        local w = CONFIG.highestValueFirst and eggWeight(rec) or 0
        if sc > bs or (sc == bs and d < bd) then best, bs, bd = rec, sc, d end
        if best and sc == bs and w > eggWeight(best) then best = rec end
      end
    end
  end
  return best, bs, bd
end

-- ===================== MAINTENANCE (RateLimiter-safe) ====================
local function maintenance()
  S.phase = 'maintenance'; S.beat = os.clock(); telem()
  pcall(function()
    local SaveM = require(RS.Shared.Save)
    local BaseU = require(RS.Client.BaseUpgrade)
    local save = SaveM.Get()
    if save and BaseU.IsNextTierAffordable(save) then BaseU.PurchaseNextTier() end
  end)
  task.wait(0.5)
  pcall(function()
    require(lp.PlayerScripts.GUI.TreadmillUpgrade.Client).RequestCashUpgrade()
  end)
  task.wait(0.5)
  pcall(function()
    ES.SyncOwnedEggs(); task.wait(1)
    local rows = ES.ReadOwnedEggs()
    local mine = rows[lp.UserId] or {}
    local okP, plot = pcall(function() return require(RS.Client.PlotState).ResolvePlot() end)
    local center = okP and plot and plot.CenterPoint
    local home = homePos()
    local unplaced = {}
    for uid, rec in pairs(mine) do
      if rec.Placement == nil then unplaced[#unplaced+1] = uid end
    end
    local planted = 0
    for _, uid in unplaced do
      if planted >= 3 then break end
      if center then
        local off = Vector3.new(math.random(-70,70)/10, 2, math.random(-70,70)/10)
        ES.PlantEgg(uid, center.CFrame:ToObjectSpace(CFrame.new(home + off)))
        planted = planted + 1
        task.wait(0.6)
      end
    end
    task.wait(1)
    ES.SyncOwnedEggs(); task.wait(1)
    rows = ES.ReadOwnedEggs(); mine = rows[lp.UserId] or {}
    local hatched = 0
    for uid, rec in pairs(mine) do
      if hatched >= 2 then break end
      if rec.Placement ~= nil then
        local ready = false
        pcall(function() ready = ES.IsReadyToHatch(uid) end)
        if ready then
          pcall(function() ES.BeginHatch(uid) end); task.wait(1.2)
          pcall(function() ES.FinishHatch(uid) end)
          hatched = hatched + 1; task.wait(0.8)
        end
      end
    end
    ES.SyncOwnedEggs()
    local cnt = 0
    for _ in pairs(ES.ReadOwnedEggs()[lp.UserId] or {}) do cnt = cnt + 1 end
    S.eggs = cnt
  end)
  telem()
end
ES.FieldClaimed:Connect(function(p)
  S.claims = S.claims + 1
  S.last = tostring(p.DisplayName or p.AssetCategory or '?')
  telem()
end)

-- ============================ MAIN CYCLE =================================
local function cycleBody()
  S.phase = 'scout'; S.beat = os.clock()
  local c, h, r = waitChar()
  if not c then task.wait(2) return end
  local best, bs = pickBest(r)
  if not best then
    S.phase = 'wait-field'; telem(); task.wait(10); return
  end
  S.last = tostring(best.AssetCategory):sub(1,14) .. ':r' .. tostring(bs)
  S.phase = 'warp'; telem()
  hopTo(best.BottomCFrame.Position, 26)
  S.phase = 'approach'; S.beat = os.clock(); telem()
  walkLive(function() return recPos(best.Uid) end, 3.5, 45, CONFIG.walkSpeed)
  S.phase = 'grab'; telem()
  upright()
  local ok = ES.CarryFieldEgg(best.Uid)
  if not ok then
    S.fails = S.fails + 1; S.phase = 'cooldown'; telem(); task.wait(3); return
  end
  S.phase = 'run-home'; telem()
  local res = runHome(homePos(), 110)
  if res == 'arrived' then
    S.steals = S.steals + 1
    S.phase = 'settle'; telem()
    task.wait(rng:NextNumber(4, 6))
    S.cycles = S.cycles + 1
    if S.cycles % CONFIG.maintenanceEvery == 0 then maintenance() end
    task.wait(rng:NextNumber(1.5, 3))
  else
    S.fails = S.fails + 1; S.phase = 'recover'; telem(); task.wait(2.5)
  end
end
local function mainLoop()
  task.wait(1)
  while alive() do
    local okP, errP = pcall(cycleBody)
    if not okP then
      S.err = tostring(errP):sub(1, 180)
      S.phase = 'error-recover'; telem(); task.wait(4)
    end
    S.beat = os.clock()
  end
  if S.gen == myGen then S.phase = 'stopped'; telem() end
end
task.spawn(function()
  while alive() do
    task.wait(10)
    if not alive() then break end
    local idle = os.clock() - S.beat
    if idle > 90 then
      local r = hrp()
      local moving = r and r.AssemblyLinearVelocity.Magnitude > 2
      if not moving then
        S.gen = S.gen + 1; myGen = S.gen
        S.err = 'watchdog respawn @age' .. string.format('%.0f', idle)
        telem(); task.spawn(mainLoop)
      else
        S.beat = os.clock()
      end
    end
  end
end)
task.spawn(mainLoop)
telem()
return 'ONYX GODSTEAL V13 ONLINE - gen ' .. myGen .. ' | anti-afk + antiGuard-lite + filters'