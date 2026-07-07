
local AutoCatch = {}
AutoCatch.__index = AutoCatch

-- ═══════════════════════════════════════════════════════════════
-- CONFIG (mirrors getgenv().AutoCatchConfig)
-- ═══════════════════════════════════════════════════════════════
local Config = getgenv().AutoCatchConfig or {
    HuntingEnabled = true,
    EncounterEnabled = true,
    EncounterCooldown = 3,
    EncounterTarget = {1000058, 1000059},
    EncounterTarget2 = nil,
    EncounterTarget3 = nil,
    EncounterTarget4 = nil,
    EncounterTarget5 = nil,
    NextChainEnabled = false,
    HuntMode = "Both",
    FleeFromShiny = false,
    UseSoftCatch = true,
    FleeNonShinyAtPityMax = true,
    NonShiny_NoPity = "Common",
    NonShiny_PityMax = "King",
    Shiny_NoPity = "Prismatic",
    Shiny_PityMax = "King",
    FastBattle = true,
    StopOnCatch = true,
    LoopAfterChainEnd = false,
    FallbackChain = {"Prismatic", "King", "Advanced", "Common"},

    SkillHealThreshold = 0.5,
    SkillPreferKillOrder = true,
    SkillAllowMultiTarget = true,
    SkillDebugMode = false,
    SkillFastMode = true,
    SkillInterval = 0.5,
}

-- ═══════════════════════════════════════════════════════════════
-- SERVICES & REMOTES
-- ═══════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BattleRemote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")
local ReqEnterPetBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqEnterPetBattle")
local BattleCatchPetWindowController = require(ReplicatedStorage.Controller.BattleCatchPetWindowController)
local BagService = require(ReplicatedStorage.Script.Bag.BagService)

local Core = ReplicatedStorage:WaitForChild("Core")
local Script = ReplicatedStorage:WaitForChild("Script")
local ConfigDataManager = require(Core:WaitForChild("Config"):WaitForChild("ConfigDataManager"))
local ConfigConst = require(Core:WaitForChild("Config"):WaitForChild("ConfigConst"))
local BattleDataGetModule = require(Script:WaitForChild("MainBattleWindow"):WaitForChild("BattleDataGetModule"))
local ElementModule = require(Script:WaitForChild("Element"):WaitForChild("ElementModule"))
local ElementConst = require(Script:WaitForChild("Element"):WaitForChild("Basic"):WaitForChild("ElementConst"))
local ReqOperateBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")

-- ═══════════════════════════════════════════════════════════════
-- MODULES (lazy-loaded with pcall)
-- ═══════════════════════════════════════════════════════════════
local PetConfig, ShinyPetLotteryStorage, ShinyPetLotteryService, ErrorCode
pcall(function() PetConfig = require(ReplicatedStorage.Config.PetConfig) end)

local function TryLoadModules()
    local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("Storage"):WaitForChild("ShinyPetLotteryStorage")) end)
    if ok then ShinyPetLotteryStorage = mod end
    ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("ShinyPetLottery"):WaitForChild("ShinyPetLotteryService")) end)
    if ok then ShinyPetLotteryService = mod end
    ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Tools"):WaitForChild("ErrorCode")) end)
    if ok then ErrorCode = mod end
end
TryLoadModules()

local SUCCEEDED = ErrorCode and ErrorCode.SUCCEEDED or 0

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════
local BALLS = {
    SoftCatch = 1000001, Common = 2000015, Advanced = 2000016,
    King = 2000017, Prismatic = 2000018,
}
local BALL_NAMES = {}
for name, id in pairs(BALLS) do BALL_NAMES[id] = name end
local UNLIMITED_BALLS = {Common = true, SoftCatch = true}

local EFFECTIVENESS_MULTIPLIER = {
    [ElementConst.ElementEffect.EXTREMELY] = 4.0, [ElementConst.ElementEffect.SUPER] = 4.0,
    [ElementConst.ElementEffect.STRONG] = 2.0, [ElementConst.ElementEffect.NORMAL] = 1.0,
    [ElementConst.ElementEffect.WEAK] = 0.5, [ElementConst.ElementEffect.NOTHING] = 0.0,
}
local EFFECTIVENESS_NAMES = {
    [ElementConst.ElementEffect.EXTREMELY] = "EXTREMELY", [ElementConst.ElementEffect.SUPER] = "SUPER",
    [ElementConst.ElementEffect.STRONG] = "STRONG", [ElementConst.ElementEffect.NORMAL] = "NORMAL",
    [ElementConst.ElementEffect.WEAK] = "WEAK", [ElementConst.ElementEffect.NOTHING] = "NOTHING",
}
local EFFECTIVENESS_PRIORITY = {
    [ElementConst.ElementEffect.EXTREMELY] = 6, [ElementConst.ElementEffect.SUPER] = 5,
    [ElementConst.ElementEffect.STRONG] = 4, [ElementConst.ElementEffect.NORMAL] = 3,
    [ElementConst.ElementEffect.WEAK] = 2, [ElementConst.ElementEffect.NOTHING] = 1,
}
local SKILL_TARGET = {SINGLE = 1, SELF = 2, ALL = 3, RANDOM = 4, ADJACENT = 5, TEAM = 6, ENEMY_TEAM = 7}
local VALID_RESPONSES = {[0] = true, [20000] = true}
local MOVE_DISABLED_CODES = {}
for i = 20001, 20030 do MOVE_DISABLED_CODES[i] = true end

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════
local State = {
    Running = false,
    Thread = nil,
    AutoBattleThread = nil,
    AutoBattleEnabled = false,
    FastBattleHooked = false,
    FastBattleOriginals = {},
    LastAction = nil,
    LastActionTime = 0,
    LastEncounterAttempt = 0,
    WasInCatchWindow = false,
    PendingLog = nil,
    CurrentChainIndex = 1,
    TargetChain = {},
    BallInventory = {},
    PityCache = {prismaticCurrent = nil, prismaticMax = nil, shinyCurrent = nil, shinyMax = nil, lastUpdated = 0},
    SessionStats = {encounters = 0, catches = 0, flees = 0, shinyEncounters = 0, shinyCaught = 0, goalCatches = 0},
}

-- ═══════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════
local function BuildTargetChain()
    State.TargetChain = {}
    local function add(t) if type(t) == "table" and #t > 0 then table.insert(State.TargetChain, t) end end
    add(Config.EncounterTarget); add(Config.EncounterTarget2); add(Config.EncounterTarget3)
    add(Config.EncounterTarget4); add(Config.EncounterTarget5)
end
BuildTargetChain()

local function GetCurrentTargets()
    if State.CurrentChainIndex <= #State.TargetChain then return State.TargetChain[State.CurrentChainIndex] end
    if Config.LoopAfterChainEnd and #State.TargetChain > 0 then State.CurrentChainIndex = 1; return State.TargetChain[1] end
    return nil
end

local function AdvanceChain()
    if not Config.NextChainEnabled then return false end
    State.CurrentChainIndex = State.CurrentChainIndex + 1
    if State.CurrentChainIndex > #State.TargetChain then
        if Config.LoopAfterChainEnd then State.CurrentChainIndex = 1; print("[AutoCatch] Chain complete. Looping.") return true
        else print("[AutoCatch] Chain complete. Stopping.") return false end
    end
    print("[AutoCatch] Advanced to group " .. State.CurrentChainIndex)
    return true
end

local function UpdateBallInventory()
    State.BallInventory = {}
    for name, itemId in pairs(BALLS) do
        if UNLIMITED_BALLS[name] then State.BallInventory[name] = math.huge
        else local c = BagService.getItemNumById(itemId); State.BallInventory[name] = (type(c) == "number" and c > 0) and c or 0 end
    end
    return State.BallInventory
end

local function HasBall(name) return (State.BallInventory[name] or 0) > 0 end

local function GetAvailableBall(preferred)
    local start = 1
    for i, n in ipairs(Config.FallbackChain) do if n == preferred then start = i; break end end
    for i = start, #Config.FallbackChain do local n = Config.FallbackChain[i]; if HasBall(n) then return n, BALLS[n] end end
    return nil, nil
end

local function IsInBattle()
    local w = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("MainBattleWindow")
    return w and w.Enabled == true
end

local function IsCatchWindowActive()
    local w = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("BattleCatchPetWindow")
    return w and w.Enabled == true
end

local function GetTargetPetId()
    local ok, r = pcall(function()
        local w = BattleCatchPetWindowController.getWindow()
        if not (w and type(w.data) == "table") then return nil end
        local d = w.data
        if type(d.catchPetInfo) == "table" then
            local i = d.catchPetInfo
            for _, k in ipairs({"id","petId","configId","monsterId","creatureId"}) do if type(i[k]) == "number" then return i[k] end end
            for _, k in ipairs({"id","petId"}) do if type(i[k]) == "string" then local n = tonumber(i[k]); if n then return n end end end
        end
        for _, k in ipairs({"petId","id","catchPetId","targetPetId","configId"}) do if type(d[k]) == "number" then return d[k] end end
        if type(d.targetPetModel) == "Instance" then
            local m = d.targetPetModel
            for _, a in ipairs({"Id","PetId","ConfigId"}) do local v = m:GetAttribute(a); if v then return v end end
        end
        for k, v in pairs(d) do if type(v) == "number" and (tostring(k):lower():find("id") or tostring(k):lower():find("pet")) then return v end end
        return nil
    end)
    if ok then return r end; return nil
end

local function GetPrismaticPity()
    local petId = GetTargetPetId(); if not petId then return nil, nil end
    if ShinyPetLotteryService and ShinyPetLotteryService.getColorPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryService.getColorPityInfo(petId) end)
        if ok and code == SUCCEEDED and type(info) == "table" and type(info.current) == "number" and type(info.pity) == "number" then return info.current, info.pity end
    end
    if ShinyPetLotteryStorage and ShinyPetLotteryStorage.getColorPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryStorage.getColorPityInfo(petId) end)
        if ok and code == SUCCEEDED and type(info) == "table" and type(info.current) == "number" and type(info.pity) == "number" then return info.current, info.pity end
    end
    if State.PityCache.prismaticCurrent and State.PityCache.prismaticMax then return State.PityCache.prismaticCurrent, State.PityCache.prismaticMax end
    return nil, nil
end

local function GetShinyPity()
    local petId = GetTargetPetId(); if not petId then return nil, nil end
    if ShinyPetLotteryService and ShinyPetLotteryService.getPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryService.getPityInfo(petId) end)
        if ok and code == SUCCEEDED and type(info) == "table" and type(info.current) == "number" and type(info.pity) == "number" then return info.current, info.pity end
    end
    if ShinyPetLotteryStorage and ShinyPetLotteryStorage.getPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryStorage.getPityInfo(petId) end)
        if ok and code == SUCCEEDED and type(info) == "table" and type(info.current) == "number" and type(info.pity) == "number" then return info.current, info.pity end
    end
    if State.PityCache.shinyCurrent and State.PityCache.shinyMax then return State.PityCache.shinyCurrent, State.PityCache.shinyMax end
    return nil, nil
end

local function IsPityMaxed()
    local c, m = GetPrismaticPity(); if type(c) ~= "number" or type(m) ~= "number" then return nil end
    return c >= (m - 1)
end

local function IsCurrentTargetShiny()
    local ok, r = pcall(function()
        local w = BattleCatchPetWindowController.getWindow()
        if w and type(w.data) == "table" then
            if w.data.isCatchPetShiny ~= nil then return w.data.isCatchPetShiny == true end
            if w.data.isShiny ~= nil then return w.data.isShiny == true end
            if w.data.shiny ~= nil then return w.data.shiny == true end
        end; return nil
    end)
    if ok and r ~= nil then return r end; return nil
end

local function IsCurrentTargetColorful()
    local ok, r = pcall(function()
        local w = BattleCatchPetWindowController.getWindow()
        if w and type(w.data) == "table" then
            if w.data.isCatchPetColorful ~= nil then return w.data.isCatchPetColorful == true end
            if w.data.isColorful ~= nil then return w.data.isColorful == true end
            if w.data.colorful ~= nil then return w.data.colorful == true end
        end; return nil
    end)
    if ok and r ~= nil then return r end; return nil
end

local function GetPetNameFromConfig(petId)
    if not PetConfig or not petId then return nil end
    local d = PetConfig[petId]; if type(d) == "table" and d.name then return tostring(d.name) end; return nil
end

local function GetTargetModel()
    local ok, r = pcall(function()
        local w = BattleCatchPetWindowController.getWindow()
        if w and type(w.data) == "table" then
            local d = w.data; local petId
            if type(d.catchPetInfo) == "table" then
                local i = d.catchPetInfo
                for _, k in ipairs({"id","petId","configId","monsterId","creatureId"}) do if type(i[k]) == "number" then petId = i[k]; break end end
            end
            if not petId then for _, k in ipairs({"petId","id","catchPetId","targetPetId","configId"}) do if type(d[k]) == "number" then petId = d[k]; break end end end
            if petId then local n = GetPetNameFromConfig(petId); if n then return n end end
            local m = d.targetPetModel; if type(m) == "string" then return m elseif type(m) == "Instance" then return m.Name else return tostring(m) end
        end; return "Unknown"
    end)
    if ok then if type(r) == "string" then return r elseif type(r) == "Instance" then return r.Name else return tostring(r) end end
    return "Unknown"
end

local function BuildTargetLabel()
    local model = GetTargetModel()
    local shiny = IsCurrentTargetShiny(); local colorful = IsCurrentTargetColorful()
    local tags = {}
    if shiny == true then table.insert(tags, "Shiny") elseif shiny == false then table.insert(tags, "Unshiny") else table.insert(tags, "?Shiny") end
    if colorful == true then table.insert(tags, "Prismatic") elseif colorful == false then table.insert(tags, "Unprismatic") else table.insert(tags, "?Prismatic") end
    return tostring(model) .. " (" .. table.concat(tags, "/") .. ")"
end

local function LeaveBattle() return pcall(function() BattleRemote:InvokeServer(unpack({{actionType = 8}})) end) end
local function PerformCatch(itemId) return pcall(function() BattleRemote:InvokeServer(unpack({{sourcePos = 1, targetPos = 1, actionType = 5, itemId = itemId}})) end) end

local function DoCatch(preferred)
    local name, id = GetAvailableBall(preferred)
    if not id then if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end; return "wait", nil, nil, false end
    return "catch", id, name, true
end

local function DecideAction()
    if not IsCatchWindowActive() then return "wait", nil, nil, false end
    UpdateBallInventory()
    local shiny = IsCurrentTargetShiny(); local pityMaxed = IsPityMaxed(); local mode = Config.HuntMode
    if pityMaxed == nil then return "wait", nil, nil, false end; if shiny == nil then shiny = false end

    if mode == "PrismaticShiny" then
        if shiny and pityMaxed then return DoCatch(Config.Shiny_PityMax) end
        if shiny and not pityMaxed then return "flee", nil, nil, false end
        if not shiny and pityMaxed then return "flee", nil, nil, false end
        if not shiny and not pityMaxed then if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end; return DoCatch(Config.NonShiny_NoPity) end
    elseif mode == "ShinyOnly" then
        if shiny and pityMaxed then return DoCatch(Config.Shiny_PityMax) end
        if shiny and not pityMaxed then if Config.FleeFromShiny then return "flee", nil, nil, false end; return DoCatch(Config.Shiny_NoPity) end
        if not shiny and pityMaxed then return "flee", nil, nil, false end
        if not shiny and not pityMaxed then if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end; return DoCatch(Config.NonShiny_NoPity) end
    elseif mode == "PrismaticOnly" then
        if shiny and pityMaxed then return DoCatch(Config.Shiny_PityMax) end
        if shiny and not pityMaxed then if Config.FleeFromShiny then return "flee", nil, nil, false end; return DoCatch(Config.Shiny_NoPity) end
        if not shiny and pityMaxed then return DoCatch(Config.NonShiny_PityMax) end
        if not shiny and not pityMaxed then if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end; return DoCatch(Config.NonShiny_NoPity) end
    elseif mode == "Both" then
        if shiny and pityMaxed then return DoCatch(Config.Shiny_PityMax) end
        if shiny and not pityMaxed then if Config.FleeFromShiny then return "flee", nil, nil, false end; return DoCatch(Config.Shiny_NoPity) end
        if not shiny and pityMaxed then if Config.FleeNonShinyAtPityMax then return "flee", nil, nil, false end; return DoCatch(Config.NonShiny_PityMax) end
        if not shiny and not pityMaxed then if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end; return DoCatch(Config.NonShiny_NoPity) end
    end
    return "wait", nil, nil, false
end

local function GetCreatureModelCache()
    local ok, c = pcall(function() return Workspace:WaitForChild("RuntimeCache"):WaitForChild("RuntimeCacheServer"):WaitForChild("CreatureModelCache") end)
    if ok then return c end; return nil
end

local function FindTargetCreatures()
    local cache = GetCreatureModelCache(); if not cache then return {} end
    local targets = GetCurrentTargets(); if not targets then return {} end
    local found = {}
    for _, child in ipairs(cache:GetChildren()) do
        local configId = child:GetAttribute("configId")
        for _, targetId in ipairs(targets) do if configId == targetId then table.insert(found, child.Name); break end end
    end
    return found
end

local function FireEncounter(creatureId) if not creatureId then return false end; return pcall(function() ReqEnterPetBattle:FireServer(creatureId) end) end

-- ═══════════════════════════════════════════════════════════════
-- FAST BATTLE
-- ═══════════════════════════════════════════════════════════════
local function GetControllerManager()
    local core = ReplicatedStorage:FindFirstChild("Core"); if not core then return nil end
    local ctrl = core:FindFirstChild("Controller"); if not ctrl then return nil end
    local cm = ctrl:FindFirstChild("ControllerManager"); if not cm then return nil end
    return require(cm)
end

local function GetMainBattleController()
    local cm = GetControllerManager(); if not cm then return nil end
    return cm.getController("MainBattleWindowController")
end

local function ApplyFastBattle()
    local ctrl = GetMainBattleController(); if not ctrl then return false end
    if State.FastBattleHooked then return true end
    State.FastBattleOriginals.getSpeed = ctrl.getBattlePlaybackSpeed
    State.FastBattleOriginals.isEnabled = ctrl.isBattleSpeedEnabled

    ctrl.getBattlePlaybackSpeed = function(...)
        local BattleService = nil; pcall(function() BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService")) end)
        if BattleService and BattleService.getCurrentBattle() then return 25 end
        return State.FastBattleOriginals.getSpeed(...)
    end
    ctrl.isBattleSpeedEnabled = function(...)
        local BattleService = nil; pcall(function() BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService")) end)
        if BattleService and BattleService.getCurrentBattle() then return true end
        return State.FastBattleOriginals.isEnabled(...)
    end
    State.FastBattleHooked = true; print("[FastBattle] Enabled"); return true
end

local function RemoveFastBattle()
    if not State.FastBattleHooked then return end
    local ctrl = GetMainBattleController()
    if ctrl then
        if State.FastBattleOriginals.getSpeed then ctrl.getBattlePlaybackSpeed = State.FastBattleOriginals.getSpeed end
        if State.FastBattleOriginals.isEnabled then ctrl.isBattleSpeedEnabled = State.FastBattleOriginals.isEnabled end
    end
    State.FastBattleHooked = false; print("[FastBattle] Disabled")
end

-- ═══════════════════════════════════════════════════════════════
-- AUTO SKILL SYSTEM
-- ═══════════════════════════════════════════════════════════════
local function getCurrentBattleData()
    local BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    local battle = BattleService.getCurrentBattle()
    if battle and type(battle) == "table" then return battle end
    local ControllerManager = require(Core:WaitForChild("Controller"):WaitForChild("ControllerManager"))
    local main = ControllerManager.getController("MainBattleWindowController")
    if main and main.getBattleDataCache then return main.getBattleDataCache() end
    return nil
end

local function getAllLocalPets(battleData)
    if not battleData or type(battleData) ~= "table" then return {} end
    local active = BattleDataGetModule.getActivePetsData(battleData); if not active or not active.selfPets then return {} end
    return active.selfPets
end

local function getAllEnemyPets(battleData)
    if not battleData or type(battleData) ~= "table" then return {} end
    local active = BattleDataGetModule.getActivePetsData(battleData); if not active or not active.enemyPets then return {} end
    return active.enemyPets
end

local function getOrderedTarget(battleData)
    local BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    local ok, result = pcall(function() return BattleService.getSequenceKillOrder(battleData) end)
    if ok and type(result) == "table" and #result > 0 then
        for _, t in ipairs(result) do
            if type(t) == "table" and type(t.uid) == "string" and t.aliveState == 1 then
                for _, e in ipairs(getAllEnemyPets(battleData)) do if type(e) == "table" and e.uid == t.uid then return e end end
                return t
            end
        end
    end
    return nil
end

local function getPrimaryTarget(battleData)
    if Config.SkillPreferKillOrder then local ot = getOrderedTarget(battleData); if ot then return ot end end
    for _, e in ipairs(getAllEnemyPets(battleData)) do if type(e) == "table" and BattleDataGetModule.isAliveBattlePet(e) then return e end end
    return getAllEnemyPets(battleData)[1]
end

local function getPetElementIdList(configId)
    local t = {}; if type(configId) ~= "number" then return t end
    local pc = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, configId)
    if type(pc) ~= "table" or type(pc.elements) ~= "table" then return t end
    for _, v in ipairs(pc.elements) do if type(v) == "number" then table.insert(t, v) end end
    return t
end

local function calculateSkillEffectiveness(skillConfig, targetElementIdList)
    if type(skillConfig) ~= "table" then return ElementConst.ElementEffect.NOTHING, 0, 0 end
    local power = skillConfig.power; if type(power) ~= "number" or power <= 0 then if skillConfig.skillCategory == 3 then return nil, 0, 0 end; return ElementConst.ElementEffect.NOTHING, 0, 0 end
    local skillElement = skillConfig.element; if type(skillElement) ~= "number" then return ElementConst.ElementEffect.NORMAL, 1.0, power end
    if type(targetElementIdList) ~= "table" or #targetElementIdList == 0 then return ElementConst.ElementEffect.NORMAL, 1.0, power end
    local result = ElementModule.calculateMultiElementRestraintRate(skillElement, targetElementIdList)
    if result.result ~= ErrorCode.SUCCEEDED then return ElementConst.ElementEffect.NORMAL, 1.0, power end
    local effect = result.effect; local mult = EFFECTIVENESS_MULTIPLIER[effect] or 1.0
    return effect, mult, math.floor(power * mult)
end

local function findBestTargetForSkill(battleData, skillConfig)
    if type(skillConfig) ~= "table" then return nil, nil, nil, nil, 0, 0 end
    local enemies = getAllEnemyPets(battleData); if #enemies == 0 then return nil, nil, nil, nil, 0, 0 end
    local bestEnemy, bestScore, bestPos, bestCampId, bestEffect, bestMult, bestPower = nil, -99999, nil, nil, ElementConst.ElementEffect.NORMAL, 1.0, 0
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData); if not enemyCampId then return nil, nil, nil, nil, 0, 0 end
    local enemyCamp = nil
    if battleData.camp1 and battleData.camp1.campId == enemyCampId then enemyCamp = battleData.camp1
    elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then enemyCamp = battleData.camp2 end

    for _, enemy in ipairs(enemies) do
        if type(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            local elements = getPetElementIdList(enemy.configId)
            local effect, mult, estPower = calculateSkillEffectiveness(skillConfig, elements)
            local score = ((EFFECTIVENESS_PRIORITY[effect] or 3) * 10000) + estPower
            if score > bestScore then
                bestScore = score; bestEnemy = enemy; bestEffect = effect; bestMult = mult; bestPower = estPower
                if enemyCamp and type(enemyCamp.slots) == "table" then
                    for pos, slot in pairs(enemyCamp.slots) do if type(slot) == "table" and type(slot.pet) == "table" and slot.pet.uid == enemy.uid then bestPos = tonumber(pos); break end end
                end
                if not bestPos then for i, e in ipairs(enemies) do if e.uid == enemy.uid then bestPos = i; break end end end
                bestCampId = enemyCampId
            end
        end
    end
    return bestEnemy, bestPos or 1, bestCampId, bestEffect, bestMult, bestPower
end

local function needsHealing(pet) if type(pet) ~= "table" then return false end; local c, m = pet.currHp or 0, pet.maxHp or 1; if m <= 0 then return false end; return (c / m) < Config.SkillHealThreshold end

local function scoreSkill(skillData, battleData, currentEnergy)
    if type(skillData) ~= "table" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillId = skillData.id; if type(skillId) ~= "number" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    if skillData.lock == true then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId); if type(skillConfig) ~= "table" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillCategory = skillConfig.skillCategory or 0; local targetType = skillConfig.targetType or 1
    local isEnergyMove = skillConfig.skillType == 2; local energyCost = skillConfig.energyCost or 0; local basePower = skillConfig.power or 0

    if isEnergyMove and energyCost > 0 then if type(currentEnergy) ~= "number" or currentEnergy < energyCost then return -9999, nil, 0, false, false, 0, nil, nil, nil end end
    if not isEnergyMove then local pp = skillData.pp; if type(pp) == "number" and pp <= 0 then return -9999, nil, 0, false, false, 0, nil, nil, nil end end

    local isHeal = false
    if basePower == 0 and skillCategory == 3 then local sn = (skillConfig.name or "):lower()"; if sn:find("heal") or sn:find("recover") or sn:find("aqua") then isHeal = true end end
    if isHeal then return -350, nil, 0, true, true, 1, nil, nil, nil end
    if skillCategory == 3 and basePower <= 0 then return -450, nil, 0, true, false, 0, nil, nil, nil end

    local effect, mult, estPower, targetCount = nil, nil, nil, 1
    local bestEnemy, bestPos, bestCampId = nil, nil, nil

    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if not Config.SkillAllowMultiTarget then return -9999, nil, 0, false, false, 0, nil, nil, nil end
        bestEnemy, bestPos, bestCampId, effect, mult, estPower = findBestTargetForSkill(battleData, skillConfig)
        targetCount = #getAllEnemyPets(battleData)
    elseif targetType == SKILL_TARGET.SELF or targetType == SKILL_TARGET.TEAM then
        return -100, nil, 0, true, false, 0, nil, nil, nil
    else
        bestEnemy, bestPos, bestCampId, effect, mult, estPower = findBestTargetForSkill(battleData, skillConfig)
    end

    local penalty = 0; if effect == ElementConst.ElementEffect.WEAK then penalty = -300 elseif effect == ElementConst.ElementEffect.NOTHING then penalty = -500 end
    local bonus = 0; if effect == ElementConst.ElementEffect.EXTREMELY then bonus = 10000 elseif effect == ElementConst.ElementEffect.SUPER then bonus = 5000 elseif effect == ElementConst.ElementEffect.STRONG then bonus = 2000 end
    local aoeBonus = 0; if targetCount > 1 then aoeBonus = estPower * (targetCount - 1) * 0.8 end
    return estPower + bonus + aoeBonus + penalty, effect, estPower, true, false, targetCount, bestEnemy, bestPos, bestCampId
end

local function getAllScoredSkillsForPet(battleData, pet)
    if not pet then return {} end; local skills = pet.skills; if type(skills) ~= "table" then return {} end
    local trainer = BattleDataGetModule.getLocalPlayerTrainer(battleData)
    local currentEnergy = (trainer and type(trainer.energy) == "number") and trainer.energy or 0
    local scored = {}
    for i = 1, 4 do
        local skillData = skills[i]
        local score, effect, estPower, canUse, isHeal, targetCount, bestEnemy, bestPos, bestCampId = scoreSkill(skillData, battleData, currentEnergy)
        if isHeal and needsHealing(pet) then score = 10000 end
        if canUse then table.insert(scored, {index = i, score = score, effect = effect, estPower = estPower, isHeal = isHeal, targetCount = targetCount, skillData = skillData, bestEnemy = bestEnemy, bestPos = bestPos, bestCampId = bestCampId}) end
    end
    table.sort(scored, function(a, b) return a.score > b.score end); return scored
end

local function getSourcePosForPet(battleData, pet)
    if not pet or type(pet) ~= "table" then return 1 end
    local localCampId = BattleDataGetModule.getLocalPlayerCampId(battleData); if not localCampId then return 1 end
    local camp = nil; if battleData.camp1 and battleData.camp1.campId == localCampId then camp = battleData.camp1 elseif battleData.camp2 and battleData.camp2.campId == localCampId then camp = battleData.camp2 end
    if camp and type(camp.slots) == "table" then for pos, slot in pairs(camp.slots) do if type(slot) == "table" and type(slot.pet) == "table" and slot.pet.uid == pet.uid then return tonumber(pos) or 1 end end end
    return 1
end

local function getTargetInfo(battleData, skillConfig, precomputed)
    if not battleData then return nil, nil end
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData); if not enemyCampId then return nil, nil end
    if precomputed and precomputed.bestPos and precomputed.bestCampId then return precomputed.bestCampId, precomputed.bestPos end
    local targetType = skillConfig and skillConfig.targetType or 1
    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if Config.SkillPreferKillOrder then local ot = getOrderedTarget(battleData); if ot and type(ot) == "table" then
            local camp = nil; if battleData.camp1 and battleData.camp1.campId == enemyCampId then camp = battleData.camp1 elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then camp = battleData.camp2 end
            if camp and type(camp.slots) == "table" then for pos, slot in pairs(camp.slots) do if type(slot) == "table" and type(slot.pet) == "table" and slot.pet.uid == ot.uid then return enemyCampId, tonumber(pos) or 1 end end end
        end end
        local _, bestPos, bestCampId = findBestTargetForSkill(battleData, skillConfig); if bestPos then return bestCampId or enemyCampId, bestPos end; return enemyCampId, 1
    end
    if Config.SkillPreferKillOrder then local ot = getOrderedTarget(battleData); if ot and type(ot) == "table" then
        local camp = nil; if battleData.camp1 and battleData.camp1.campId == enemyCampId then camp = battleData.camp1 elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then camp = battleData.camp2 end
        if camp and type(camp.slots) == "table" then for pos, slot in pairs(camp.slots) do if type(slot) == "table" and type(slot.pet) == "table" and slot.pet.uid == ot.uid then return enemyCampId, tonumber(pos) or 1 end end end
    end end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if activePets and activePets.enemyPets then for pos, pet in ipairs(activePets.enemyPets) do if type(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then return enemyCampId, pos end end end
    return enemyCampId, 1
end

local function getSkillIdFromPet(pet, index) if not pet then return nil end; local skills = pet.skills; if type(skills) ~= "table" then return nil end; local sd = skills[index]; if type(sd) ~= "table" then return nil end; return sd.id end

local function executeSkillForPet(battleData, pet, skillIndex, precomputed)
    if not pet or not skillIndex then return false, nil end
    local skillId = getSkillIdFromPet(pet, skillIndex); if not skillId then return false, nil end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId)
    local targetCampId, targetPos = getTargetInfo(battleData, skillConfig, precomputed); if not targetCampId or not targetPos then return false, nil end
    local sourcePos = getSourcePosForPet(battleData, pet)
    local args = {{skillType = skillConfig and skillConfig.skillType or 1, targetPos = targetPos, sourcePos = sourcePos, actionType = 1, targetCampId = targetCampId, skillId = skillId}}
    local ok, result = pcall(function() return ReqOperateBattle:InvokeServer(unpack(args)) end)
    if ok then if VALID_RESPONSES[result] == true then return true, result else return false, result end else return false, nil end
end

local function executeBestSkillsForAllPets()
    local battleData = getCurrentBattleData(); if not battleData then return false end
    local allPets = getAllLocalPets(battleData); if #allPets == 0 then return false end
    local allMoves = {}
    for _, pet in ipairs(allPets) do
        if type(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then
            local scored = getAllScoredSkillsForPet(battleData, pet)
            if #scored > 0 then
                local petName = "Unknown"; if pet.configId then local pc = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, pet.configId); petName = pc and pc.name or "Unknown" end
                table.insert(allMoves, {pet = pet, scoredSkills = scored, sourcePos = getSourcePosForPet(battleData, pet), petName = petName, bestScore = scored[1].score})
            end
        end
    end
    if #allMoves == 0 then return false end
    table.sort(allMoves, function(a, b) return a.bestScore > b.bestScore end)
    local anySuccess = false
    for _, move in ipairs(allMoves) do
        local success, resultCode = false, nil
        for i, sk in ipairs(move.scoredSkills) do
            success, resultCode = executeSkillForPet(battleData, move.pet, sk.index, sk)
            if success then anySuccess = true; if not Config.SkillFastMode then task.wait(0.2) end; break
            else if resultCode == 27811 then break end; if resultCode and MOVE_DISABLED_CODES[resultCode] then else break end end
        end
        battleData = getCurrentBattleData(); if not battleData then break end
    end
    return anySuccess
end

local function startAutoBattle(interval)
    interval = interval or Config.SkillInterval; State.AutoBattleEnabled = true
    if State.AutoBattleThread then State.AutoBattleThread = nil end
    State.AutoBattleThread = task.spawn(function()
        while State.AutoBattleEnabled do
            local bd = getCurrentBattleData()
            if bd then local s = executeBestSkillsForAllPets(); if s then task.wait(interval) else task.wait(0.2) end else task.wait(1) end
        end
    end)
    return State.AutoBattleThread
end

local function stopAutoBattle() State.AutoBattleEnabled = false; State.AutoBattleThread = nil end

-- ═══════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════
local function MainLoop()
    while State.Running do
        task.wait(0.3)
        if not Config.HuntingEnabled and not Config.EncounterEnabled then if State.FastBattleHooked then RemoveFastBattle() end; continue end

        if IsInBattle() then
            if not Config.HuntingEnabled then if State.FastBattleHooked then RemoveFastBattle() end; continue end
            if Config.FastBattle and not State.FastBattleHooked then ApplyFastBattle() end
            if not State.AutoBattleEnabled then startAutoBattle() end

            local catchActive = IsCatchWindowActive()
            if catchActive and not State.WasInCatchWindow then
                State.WasInCatchWindow = true; State.SessionStats.encounters = State.SessionStats.encounters + 1
            end

            if not catchActive then if State.PendingLog then print(State.PendingLog); State.PendingLog = nil end; State.LastAction = nil; continue end
            if State.LastAction and (tick() - State.LastActionTime) < 1.5 then continue end

            local targetLabel = BuildTargetLabel(); local shiny = IsCurrentTargetShiny()
            local action, param, methodName, isGoalCatch = DecideAction()
            local method = methodName or BALL_NAMES[param] or (action == "flee" and "FLEE" or "WAIT")

            if action == "catch" and param then
                PerformCatch(param); State.SessionStats.catches = State.SessionStats.catches + 1
                if shiny == true then State.SessionStats.shinyEncounters = State.SessionStats.shinyEncounters + 1; State.SessionStats.shinyCaught = State.SessionStats.shinyCaught + 1 end
                if isGoalCatch and Config.StopOnCatch then
                    State.SessionStats.goalCatches = State.SessionStats.goalCatches + 1
                    print("[AutoCatch] GOAL CAUGHT! (" .. method .. ") Stopping.")
                    State.Running = false; RemoveFastBattle(); stopAutoBattle(); return
                end
                if Config.NextChainEnabled then if not AdvanceChain() then State.Running = false; RemoveFastBattle(); stopAutoBattle(); return end end
                State.LastAction = action; State.LastActionTime = tick(); task.wait(1.2)
                State.PendingLog = "[AutoCatch] CATCH | Target: " .. targetLabel .. " | Method: " .. method .. (isGoalCatch and " [GOAL]" or " [PITY]")
                task.wait(0.5)
            elseif action == "flee" then
                LeaveBattle(); State.SessionStats.flees = State.SessionStats.flees + 1
                State.LastAction = action; State.LastActionTime = tick()
                State.PendingLog = "[AutoCatch] FLEE | Target: " .. targetLabel
                task.wait(2.5)
            elseif action == "wait" then task.wait(0.5) end
        else
            State.WasInCatchWindow = false
            if State.PendingLog then print(State.PendingLog); State.PendingLog = nil end
            if Config.FastBattle and State.FastBattleHooked then RemoveFastBattle() end
            if State.AutoBattleEnabled then stopAutoBattle() end
            if not Config.EncounterEnabled then continue end
            if (tick() - State.LastEncounterAttempt) >= Config.EncounterCooldown then
                State.LastEncounterAttempt = tick(); local found = FindTargetCreatures()
                if #found > 0 then for _, cid in ipairs(found) do FireEncounter(cid); print("[AutoEncounter] Fired:", cid); break end end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC API (getgenv() exports)
-- ═══════════════════════════════════════════════════════════════
function AutoCatch:Start()
    if State.Running then print("[AutoCatch] Already running.") return end
    State.Running = true
    task.spawn(function()
        local ok, err = pcall(MainLoop)
        if not ok then warn("[AutoCatch] Crashed: " .. tostring(err)); warn(debug.traceback()) end
    end)
    print("[AutoCatch] Started.")
end

function AutoCatch:Stop()
    State.Running = false; RemoveFastBattle(); stopAutoBattle()
    print("[AutoCatch] Stopped.")
end

function AutoCatch:Toggle() if State.Running then self:Stop() else self:Start() end; return State.Running end
function AutoCatch:IsRunning() return State.Running end

function AutoCatch:SetHuntingEnabled(v) Config.HuntingEnabled = v == true; print("[AutoCatch] Hunting:", Config.HuntingEnabled) end
function AutoCatch:SetEncounterEnabled(v) Config.EncounterEnabled = v == true; print("[AutoCatch] Encounter:", Config.EncounterEnabled) end
function AutoCatch:SetHuntMode(v) if v ~= "Both" and v ~= "ShinyOnly" and v ~= "PrismaticOnly" and v ~= "PrismaticShiny" then warn("Invalid mode") return end; Config.HuntMode = v; print("[AutoCatch] Mode:", v) end
function AutoCatch:SetFleeFromShiny(v) Config.FleeFromShiny = v == true; print("[AutoCatch] FleeShiny:", Config.FleeFromShiny) end
function AutoCatch:SetUseSoftCatch(v) Config.UseSoftCatch = v ~= false; print("[AutoCatch] SoftCatch:", Config.UseSoftCatch) end
function AutoCatch:SetFleeNonShinyAtPityMax(v) Config.FleeNonShinyAtPityMax = v ~= false; print("[AutoCatch] FleeNonShinyMax:", Config.FleeNonShinyAtPityMax) end
function AutoCatch:SetFastBattle(v) Config.FastBattle = v ~= false; print("[AutoCatch] FastBattle:", Config.FastBattle) end
function AutoCatch:SetStopOnCatch(v) Config.StopOnCatch = v == true; print("[AutoCatch] StopOnCatch:", Config.StopOnCatch) end
function AutoCatch:SetNextChainEnabled(v) Config.NextChainEnabled = v == true; print("[AutoCatch] NextChain:", Config.NextChainEnabled) end
function AutoCatch:SetLoopAfterChainEnd(v) Config.LoopAfterChainEnd = v == true; print("[AutoCatch] LoopChain:", Config.LoopAfterChainEnd) end
function AutoCatch:SetEncounterCooldown(v) if type(v) ~= "number" or v < 0 then warn("Need positive number") return end; Config.EncounterCooldown = v; print("[AutoCatch] Cooldown:", v) end

function AutoCatch:SetEncounterTarget(t)
    if type(t) ~= "table" then if type(t) == "number" then t = {t} else warn("Need table or number") return end end
    Config.EncounterTarget = t; BuildTargetChain(); State.CurrentChainIndex = 1; print("[AutoCatch] Targets:", table.concat(t, ", "))
end

function AutoCatch:SetEncounterTargetGroup(groupNum, t)
    if type(groupNum) ~= "number" or groupNum < 1 or groupNum > 5 then warn("Group 1-5") return end
    if type(t) ~= "table" then if type(t) == "number" then t = {t} else warn("Need table or number") return end end
    local key = "EncounterTarget"; if groupNum > 1 then key = key .. groupNum end
    Config[key] = t; BuildTargetChain(); print("[AutoCatch] " .. key .. ":", table.concat(t, ", "))
end

function AutoCatch:AddTarget(configId)
    if type(configId) ~= "number" then warn("Need number") return end
    local targets = GetCurrentTargets(); if not targets then warn("No active group") return end
    for _, id in ipairs(targets) do if id == configId then print("Already in group") return end end
    table.insert(targets, configId); print("[AutoCatch] Added:", configId)
end

function AutoCatch:RemoveTarget(configId)
    if type(configId) ~= "number" then warn("Need number") return end
    local targets = GetCurrentTargets(); if not targets then warn("No active group") return end
    for i, id in ipairs(targets) do if id == configId then table.remove(targets, i); print("[AutoCatch] Removed:", configId); return end end
    print("[AutoCatch] Not found:", configId)
end

function AutoCatch:ListTargets()
    print("[AutoCatch] Current group (" .. State.CurrentChainIndex .. "):", table.concat(GetCurrentTargets() or {}, ", "))
    for i, g in ipairs(State.TargetChain) do print("  Group " .. i .. ":" .. (i == State.CurrentChainIndex and " <--" or ""), table.concat(g, ", ")) end
    return GetCurrentTargets()
end

function AutoCatch:AdvanceChain() return AdvanceChain() end
function AutoCatch:ResetChain() State.CurrentChainIndex = 1; print("[AutoCatch] Chain reset") end

function AutoCatch:SetFallbackChain(chain) if type(chain) ~= "table" then warn("Need table") return end; Config.FallbackChain = chain; print("[AutoCatch] Fallback:", table.concat(chain, " -> ")) end
function AutoCatch:SetBallForScenario(scenario, ballName)
    local valid = {NonShiny_NoPity = true, NonShiny_PityMax = true, Shiny_NoPity = true, Shiny_PityMax = true}
    if not valid[scenario] then warn("Invalid scenario") return end; if not BALLS[ballName] then warn("Invalid ball") return end
    Config[scenario] = ballName; print("[AutoCatch] " .. scenario .. " -> " .. ballName)
end

function AutoCatch:SetSkillSettings(s)
    if type(s) ~= "table" then warn("Need table") return end
    if s.healThreshold ~= nil then Config.SkillHealThreshold = type(s.healThreshold) == "number" and s.healThreshold or Config.SkillHealThreshold end
    if s.preferKillOrder ~= nil then Config.SkillPreferKillOrder = s.preferKillOrder == true end
    if s.allowMultiTarget ~= nil then Config.SkillAllowMultiTarget = s.allowMultiTarget == true end
    if s.debugMode ~= nil then Config.SkillDebugMode = s.debugMode == true end
    if s.fastMode ~= nil then Config.SkillFastMode = s.fastMode ~= false end
    if s.interval ~= nil then Config.SkillInterval = type(s.interval) == "number" and s.interval or Config.SkillInterval end
    print("[AutoCatch] Skill settings updated")
end

function AutoCatch:GetSkillSettings()
    return {healThreshold = Config.SkillHealThreshold, preferKillOrder = Config.SkillPreferKillOrder, allowMultiTarget = Config.SkillAllowMultiTarget, debugMode = Config.SkillDebugMode, fastMode = Config.SkillFastMode, interval = Config.SkillInterval}
end

function AutoCatch:ToggleFastBattle() if State.FastBattleHooked then RemoveFastBattle() else ApplyFastBattle() end; return State.FastBattleHooked end
function AutoCatch:SetFastBattleState(v) if v then ApplyFastBattle() else RemoveFastBattle() end; return State.FastBattleHooked end

function AutoCatch:GetSessionStats() return {encounters = State.SessionStats.encounters, catches = State.SessionStats.catches, goalCatches = State.SessionStats.goalCatches, flees = State.SessionStats.flees, shinyEncounters = State.SessionStats.shinyEncounters, shinyCaught = State.SessionStats.shinyCaught} end
function AutoCatch:ResetSessionStats() State.SessionStats = {encounters = 0, catches = 0, flees = 0, shinyEncounters = 0, shinyCaught = 0, goalCatches = 0}; print("[AutoCatch] Stats reset") end

function AutoCatch:GetStatus()
    return {running = State.Running, huntingEnabled = Config.HuntingEnabled, encounterEnabled = Config.EncounterEnabled, huntMode = Config.HuntMode, fastBattle = State.FastBattleHooked, autoBattle = State.AutoBattleEnabled, currentChainIndex = State.CurrentChainIndex, currentTargets = GetCurrentTargets(), ballInventory = UpdateBallInventory()}
end

function AutoCatch:PrintConfig()
    print("
========== AutoCatch Config ==========")
    print("  HuntingEnabled:       " .. tostring(Config.HuntingEnabled))
    print("  EncounterEnabled:     " .. tostring(Config.EncounterEnabled))
    print("  EncounterCooldown:    " .. tostring(Config.EncounterCooldown))
    print("  HuntMode:             " .. tostring(Config.HuntMode))
    print("  FleeFromShiny:        " .. tostring(Config.FleeFromShiny))
    print("  UseSoftCatch:         " .. tostring(Config.UseSoftCatch))
    print("  FleeNonShiny@Max:     " .. tostring(Config.FleeNonShinyAtPityMax))
    print("  FastBattle:           " .. tostring(Config.FastBattle))
    print("  StopOnCatch:          " .. tostring(Config.StopOnCatch))
    print("  NextChain:            " .. tostring(Config.NextChainEnabled))
    print("  LoopAfterChain:       " .. tostring(Config.LoopAfterChainEnd))
    print("  SkillHealThreshold:   " .. tostring(Config.SkillHealThreshold))
    print("  SkillPreferKillOrder: " .. tostring(Config.SkillPreferKillOrder))
    print("  SkillAllowMultiTarget:" .. tostring(Config.SkillAllowMultiTarget))
    print("  SkillDebugMode:       " .. tostring(Config.SkillDebugMode))
    print("  SkillFastMode:        " .. tostring(Config.SkillFastMode))
    print("  SkillInterval:        " .. tostring(Config.SkillInterval))
    print("  Target Chain:")
    for i, g in ipairs(State.TargetChain) do print("    Group " .. i .. ": " .. table.concat(g, ", ")) end
    print("  Ball Inventory:")
    for _, n in ipairs(Config.FallbackChain) do local c = State.BallInventory[n] or 0; print("    " .. n .. ": " .. (c == math.huge and "UNLIMITED" or c)) end
    print("  SoftCatch: UNLIMITED")
    print("  Fallback Chain: " .. table.concat(Config.FallbackChain, " -> "))
    print("  Scenario Balls:")
    print("    NonShiny + NoPity:    " .. Config.NonShiny_NoPity)
    print("    NonShiny + PityMax:   " .. Config.NonShiny_PityMax)
    print("    Shiny + NoPity:       " .. Config.Shiny_NoPity)
    print("    Shiny + PityMax:      " .. Config.Shiny_PityMax)
    print("======================================
")
end

-- ═══════════════════════════════════════════════════════════════
-- getgenv() EXPORTS (legacy toggle support)
-- ═══════════════════════════════════════════════════════════════
getgenv().AutoCatch = AutoCatch
getgenv().StartAutoCatch = function() AutoCatch:Start() end
getgenv().StopAutoCatch = function() AutoCatch:Stop() end
getgenv().ToggleAutoCatch = function() return AutoCatch:Toggle() end
getgenv().RestartAutoCatch = function() AutoCatch:Stop(); task.wait(0.5); AutoCatch:Start() end

getgenv().ToggleFastBattle = function() return AutoCatch:ToggleFastBattle() end
getgenv().SetFastBattle = function(v) return AutoCatch:SetFastBattleState(v) end

getgenv().SetHuntingEnabled = function(v) AutoCatch:SetHuntingEnabled(v) end
getgenv().SetEncounterEnabled = function(v) AutoCatch:SetEncounterEnabled(v) end
getgenv().SetEncounterCooldown = function(v) AutoCatch:SetEncounterCooldown(v) end
getgenv().SetHuntMode = function(v) AutoCatch:SetHuntMode(v) end
getgenv().SetFleeFromShiny = function(v) AutoCatch:SetFleeFromShiny(v) end
getgenv().SetUseSoftCatch = function(v) AutoCatch:SetUseSoftCatch(v) end
getgenv().SetFleeNonShinyAtPityMax = function(v) AutoCatch:SetFleeNonShinyAtPityMax(v) end
getgenv().SetStopOnCatch = function(v) AutoCatch:SetStopOnCatch(v) end
getgenv().SetNextChainEnabled = function(v) AutoCatch:SetNextChainEnabled(v) end
getgenv().SetLoopAfterChainEnd = function(v) AutoCatch:SetLoopAfterChainEnd(v) end
getgenv().SetEncounterTarget = function(t) AutoCatch:SetEncounterTarget(t) end
getgenv().SetChainTarget = function(g, t) AutoCatch:SetEncounterTargetGroup(g, t) end
getgenv().AddTarget = function(id) AutoCatch:AddTarget(id) end
getgenv().RemoveTarget = function(id) AutoCatch:RemoveTarget(id) end
getgenv().ListTargets = function() return AutoCatch:ListTargets() end
getgenv().AdvanceTargetChain = function() return AutoCatch:AdvanceChain() end
getgenv().ResetTargetChain = function() AutoCatch:ResetChain() end
getgenv().SetFallbackChain = function(c) AutoCatch:SetFallbackChain(c) end
getgenv().SetBallForScenario = function(s, b) AutoCatch:SetBallForScenario(s, b) end
getgenv().SetSkillSettings = function(s) AutoCatch:SetSkillSettings(s) end
getgenv().GetSkillSettings = function() return AutoCatch:GetSkillSettings() end
getgenv().GetSessionStats = function() return AutoCatch:GetSessionStats() end
getgenv().ResetSessionStats = function() AutoCatch:ResetSessionStats() end
getgenv().GetStatus = function() return AutoCatch:GetStatus() end
getgenv().PrintConfig = function() AutoCatch:PrintConfig() end

-- ═══════════════════════════════════════════════════════════════
-- AUTO-START (if HuntingEnabled or EncounterEnabled)
-- ═══════════════════════════════════════════════════════════════
UpdateBallInventory()
AutoCatch:PrintConfig()

if Config.FastBattle then task.spawn(function() task.wait(3); ApplyFastBattle() end) end
if Config.HuntingEnabled or Config.EncounterEnabled then AutoCatch:Start() end

return AutoCatch
