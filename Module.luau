local Evolink = {}
Evolink.__index = Evolink

local Config = {
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

local BALLS = {
    SoftCatch = 1000001,
    Common = 2000015,
    Advanced = 2000016,
    King = 2000017,
    Prismatic = 2000018,
}

local BALL_NAMES = {}
for name, id in pairs(BALLS) do
    BALL_NAMES[id] = name
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BattleRemote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")
local ReqEnterPetBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqEnterPetBattle")
local BattleCatchPetWindowController = require(ReplicatedStorage.Controller.BattleCatchPetWindowController)
local BagService = require(ReplicatedStorage.Script.Bag.BagService)

local PetConfig = nil
pcall(function()
    PetConfig = require(game:GetService("ReplicatedStorage").Config.PetConfig)
end)

local ShinyPetLotteryStorage = nil
local ShinyPetLotteryService = nil
local ErrorCode = nil

pcall(function()
    ShinyPetLotteryStorage = require(ReplicatedStorage:WaitForChild("Storage"):WaitForChild("ShinyPetLotteryStorage"))
end)

pcall(function()
    ShinyPetLotteryService = require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("ShinyPetLottery"):WaitForChild("ShinyPetLotteryService"))
end)

pcall(function()
    ErrorCode = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Tools"):WaitForChild("ErrorCode"))
end)

local SUCCEEDED = ErrorCode and ErrorCode.SUCCEEDED or 0

local Core = ReplicatedStorage:WaitForChild("Core")
local Script = ReplicatedStorage:WaitForChild("Script")
local ConfigModule = Core:WaitForChild("Config")
local ConfigDataManager = require(ConfigModule:WaitForChild("ConfigDataManager"))
local ConfigConst = require(ConfigModule:WaitForChild("ConfigConst"))

local BattleDataGetModule = require(Script:WaitForChild("MainBattleWindow"):WaitForChild("BattleDataGetModule"))
local ElementModule = require(Script:WaitForChild("Element"):WaitForChild("ElementModule"))
local ElementConst = require(Script:WaitForChild("Element"):WaitForChild("Basic"):WaitForChild("ElementConst"))
local ReqOperateBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")

local TargetChain = {}
local CurrentChainIndex = 1
local BallInventory = {}
local UNLIMITED_BALLS = {Common = true, SoftCatch = true}

local PityCache = {
    prismaticCurrent = nil, prismaticMax = nil,
    shinyCurrent = nil, shinyMax = nil,
    lastUpdated = 0,
}

local FastBattleState = {enabled = false, originalGetSpeed = nil, originalIsEnabled = nil, hooked = false}
local autoBattleEnabled = false
local autoBattleThread = nil
local Running = true
local LastAction = nil
local LastActionTime = 0
local PendingLog = nil
local WasInCatchWindow = false
local LastEncounterAttempt = 0

local SessionStats = {
    encounters = 0, catches = 0, flees = 0,
    shinyEncounters = 0, shinyCaught = 0, goalCatches = 0,
}

local EFFECTIVENESS_MULTIPLIER = {
    [ElementConst.ElementEffect.EXTREMELY] = 4.0,
    [ElementConst.ElementEffect.SUPER] = 4.0,
    [ElementConst.ElementEffect.STRONG] = 2.0,
    [ElementConst.ElementEffect.NORMAL] = 1.0,
    [ElementConst.ElementEffect.WEAK] = 0.5,
    [ElementConst.ElementEffect.NOTHING] = 0.0,
}

local EFFECTIVENESS_NAMES = {
    [ElementConst.ElementEffect.EXTREMELY] = "EXTREMELY",
    [ElementConst.ElementEffect.SUPER] = "SUPER",
    [ElementConst.ElementEffect.STRONG] = "STRONG",
    [ElementConst.ElementEffect.NORMAL] = "NORMAL",
    [ElementConst.ElementEffect.WEAK] = "WEAK",
    [ElementConst.ElementEffect.NOTHING] = "NOTHING",
}

local EFFECTIVENESS_PRIORITY = {
    [ElementConst.ElementEffect.EXTREMELY] = 6,
    [ElementConst.ElementEffect.SUPER] = 5,
    [ElementConst.ElementEffect.STRONG] = 4,
    [ElementConst.ElementEffect.NORMAL] = 3,
    [ElementConst.ElementEffect.WEAK] = 2,
    [ElementConst.ElementEffect.NOTHING] = 1,
}

local SKILL_TARGET = {
    SINGLE = 1, SELF = 2, ALL = 3, RANDOM = 4,
    ADJACENT = 5, TEAM = 6, ENEMY_TEAM = 7,
}

local VALID_RESPONSES = {[0] = true, [20000] = true}

local MOVE_DISABLED_CODES = {
    [20001] = true, [20002] = true, [20003] = true, [20004] = true,
    [20005] = true, [20006] = true, [20007] = true, [20008] = true,
    [20009] = true, [20010] = true, [20011] = true, [20012] = true,
    [20013] = true, [20014] = true, [20015] = true, [20016] = true,
    [20017] = true, [20018] = true, [20019] = true, [20020] = true,
    [20021] = true, [20022] = true, [20023] = true, [20024] = true,
    [20025] = true, [20026] = true, [20027] = true, [20028] = true,
    [20029] = true, [20030] = true,
}

local function BuildTargetChain()
    TargetChain = {}
    local function addIfValid(t)
        if type(t) == "table" and #t > 0 then
            table.insert(TargetChain, t)
        end
    end
    addIfValid(Config.EncounterTarget)
    addIfValid(Config.EncounterTarget2)
    addIfValid(Config.EncounterTarget3)
    addIfValid(Config.EncounterTarget4)
    addIfValid(Config.EncounterTarget5)
end

local function GetCurrentTargets()
    if CurrentChainIndex <= #TargetChain then
        return TargetChain[CurrentChainIndex]
    end
    if Config.LoopAfterChainEnd and #TargetChain > 0 then
        CurrentChainIndex = 1
        return TargetChain[1]
    end
    return nil
end

local function AdvanceChain()
    if not Config.NextChainEnabled then return false end
    CurrentChainIndex = CurrentChainIndex + 1
    if CurrentChainIndex > #TargetChain then
        if Config.LoopAfterChainEnd then
            CurrentChainIndex = 1
            print("[Evolink] Chain complete. Looping back to target group 1.")
            return true
        else
            print("[Evolink] Chain complete. No more targets. Stopping.")
            return false
        end
    end
    print("[Evolink] Advanced to target group " .. CurrentChainIndex .. ": " .. table.concat(GetCurrentTargets() or {}, ", "))
    return true
end

local function UpdatePityCacheFromUI()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("BattleCatchPetWindow")
    if window then
        local textObj = window:FindFirstChild("MainCanvasGroup") 
            and window.MainCanvasGroup:FindFirstChild("SpecialRateFrame")
            and window.MainCanvasGroup.SpecialRateFrame:FindFirstChild("SparkleInfoFrame")
            and window.MainCanvasGroup.SpecialRateFrame.SparkleInfoFrame:FindFirstChild("SparklePityText")
        if textObj and textObj:IsA("TextLabel") then
            local text = textObj.Text
            if text and text ~= "" then
                local current, max = text:match("(%d+)/(%d+)")
                if current and max then
                    PityCache.prismaticCurrent = tonumber(current)
                    PityCache.prismaticMax = tonumber(max)
                end
            end
        end

        local paths = {
            {"MainCanvasGroup", "SpecialRateFrame", "ShinyInfoFrame", "ShinyPityText"},
            {"MainCanvasGroup", "ShinyPityFrame", "ShinyPityText"},
            {"MainCanvasGroup", "ShinyFrame", "PityText"},
            {"MainCanvasGroup", "InfoFrame", "ShinyPity"},
            {"ShinyPityText"},
        }
        for _, path in ipairs(paths) do
            local obj = window
            for _, childName in ipairs(path) do
                obj = obj and obj:FindFirstChild(childName)
            end
            if obj and obj:IsA("TextLabel") and obj.Text ~= "" then
                local current, max = obj.Text:match("(%d+)/(%d+)")
                if current and max then
                    PityCache.shinyCurrent = tonumber(current)
                    PityCache.shinyMax = tonumber(max)
                    break
                end
            end
        end
        PityCache.lastUpdated = tick()
    end
end

local function GetDisplayPityStrings(actionType)
    local prisCurrent, prisMax = PityCache.prismaticCurrent, PityCache.prismaticMax
    local shinyCurrent, shinyMax = PityCache.shinyCurrent, PityCache.shinyMax

    if shinyCurrent and shinyMax then shinyCurrent = shinyCurrent + 1 end
    if actionType == "catch" and prisCurrent and prisMax then prisCurrent = prisCurrent + 1 end

    local prisStr = (prisCurrent and prisMax) and (prisCurrent .. "/" .. prisMax) or "??/??"
    local shinyStr = (shinyCurrent and shinyMax) and (shinyCurrent .. "/" .. shinyMax) or "??/??"
    return prisStr, shinyStr
end

local function ClearPityCache()
    PityCache.prismaticCurrent = nil; PityCache.prismaticMax = nil
    PityCache.shinyCurrent = nil; PityCache.shinyMax = nil
    PityCache.lastUpdated = 0
end

local function UpdateBallInventory()
    BallInventory = {}
    for name, itemId in pairs(BALLS) do
        if UNLIMITED_BALLS[name] then
            BallInventory[name] = math.huge
        else
            local count = BagService.getItemNumById(itemId)
            BallInventory[name] = (typeof(count) == "number" and count > 0) and count or 0
        end
    end
    return BallInventory
end

local function HasBall(ballName)
    return (BallInventory[ballName] or 0) > 0
end

local function GetAvailableBall(preferredBallName)
    local startIndex = 1
    for i, name in ipairs(Config.FallbackChain) do
        if name == preferredBallName then startIndex = i; break end
    end
    for i = startIndex, #Config.FallbackChain do
        local ballName = Config.FallbackChain[i]
        if HasBall(ballName) then return ballName, BALLS[ballName] end
    end
    return nil, nil
end

local function IsInBattle()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("MainBattleWindow")
    return window and window.Enabled == true
end

local function IsCatchWindowActive()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("BattleCatchPetWindow")
    return window and window.Enabled == true
end

local function GetTargetPetId()
    local success, result = pcall(function()
        local window = BattleCatchPetWindowController.getWindow()
        if not (window and typeof(window.data) == "table") then return nil end
        local data = window.data

        if typeof(data.catchPetInfo) == "table" then
            local info = data.catchPetInfo
            if typeof(info.id) == "number" then return info.id end
            if typeof(info.petId) == "number" then return info.petId end
            if typeof(info.configId) == "number" then return info.configId end
            if typeof(info.monsterId) == "number" then return info.monsterId end
            if typeof(info.creatureId) == "number" then return info.creatureId end
            if typeof(info.id) == "string" then local n = tonumber(info.id); if n then return n end end
            if typeof(info.petId) == "string" then local n = tonumber(info.petId); if n then return n end end
        end

        if typeof(data.petId) == "number" then return data.petId end
        if typeof(data.id) == "number" then return data.id end
        if typeof(data.catchPetId) == "number" then return data.catchPetId end
        if typeof(data.targetPetId) == "number" then return data.targetPetId end
        if typeof(data.configId) == "number" then return data.configId end

        if typeof(data.targetPetModel) == "Instance" then
            local model = data.targetPetModel
            if model:GetAttribute("Id") then return model:GetAttribute("Id") end
            if model:GetAttribute("PetId") then return model:GetAttribute("PetId") end
            if model:GetAttribute("ConfigId") then return model:GetAttribute("ConfigId") end
        end

        for key, value in pairs(data) do
            if typeof(value) == "number" and (tostring(key):lower():find("id") or tostring(key):lower():find("pet")) then
                return value
            end
        end
        return nil
    end)
    if success then return result end
    return nil
end

local function GetPrismaticPityFromModule()
    local petId = GetTargetPetId()
    if not petId then return nil, nil end
    if ShinyPetLotteryService and ShinyPetLotteryService.getColorPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryService.getColorPityInfo(petId) end)
        if ok and code == SUCCEEDED and info and typeof(info) == "table" then
            if typeof(info.current) == "number" and typeof(info.pity) == "number" then
                return info.current, info.pity
            end
        end
    end
    if ShinyPetLotteryStorage and ShinyPetLotteryStorage.getColorPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryStorage.getColorPityInfo(petId) end)
        if ok and code == SUCCEEDED and info and typeof(info) == "table" then
            if typeof(info.current) == "number" and typeof(info.pity) == "number" then
                return info.current, info.pity
            end
        end
    end
    return nil, nil
end

local function GetShinyPityFromModule()
    local petId = GetTargetPetId()
    if not petId then return nil, nil end
    if ShinyPetLotteryService and ShinyPetLotteryService.getPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryService.getPityInfo(petId) end)
        if ok and code == SUCCEEDED and info and typeof(info) == "table" then
            if typeof(info.current) == "number" and typeof(info.pity) == "number" then
                return info.current, info.pity
            end
        end
    end
    if ShinyPetLotteryStorage and ShinyPetLotteryStorage.getPityInfo then
        local ok, code, info = pcall(function() return ShinyPetLotteryStorage.getPityInfo(petId) end)
        if ok and code == SUCCEEDED and info and typeof(info) == "table" then
            if typeof(info.current) == "number" and typeof(info.pity) == "number" then
                return info.current, info.pity
            end
        end
    end
    return nil, nil
end

local function GetPrismaticPity()
    local current, max = GetPrismaticPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if PityCache.prismaticCurrent and PityCache.prismaticMax then
        return PityCache.prismaticCurrent, PityCache.prismaticMax
    end
    return nil, nil
end

local function GetShinyPity()
    local current, max = GetShinyPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if PityCache.shinyCurrent and PityCache.shinyMax then
        return PityCache.shinyCurrent, PityCache.shinyMax
    end
    return nil, nil
end

local function IsPityMaxed()
    local current, max = GetPrismaticPity()
    if type(current) ~= "number" or type(max) ~= "number" then return nil end
    return current >= (max - 1)
end

local function IsCurrentTargetShiny()
    local success, result = pcall(function()
        local window = BattleCatchPetWindowController.getWindow()
        if window and typeof(window.data) == "table" then
            if window.data.isCatchPetShiny ~= nil then return window.data.isCatchPetShiny == true end
            if window.data.isShiny ~= nil then return window.data.isShiny == true end
            if window.data.shiny ~= nil then return window.data.shiny == true end
        end
        return nil
    end)
    if success and result ~= nil then return result end
    return nil
end

local function IsCurrentTargetColorful()
    local success, result = pcall(function()
        local window = BattleCatchPetWindowController.getWindow()
        if window and typeof(window.data) == "table" then
            if window.data.isCatchPetColorful ~= nil then return window.data.isCatchPetColorful == true end
            if window.data.isColorful ~= nil then return window.data.isColorful == true end
            if window.data.colorful ~= nil then return window.data.colorful == true end
        end
        return nil
    end)
    if success and result ~= nil then return result end
    return nil
end

local function GetPetNameFromConfig(petId)
    if not PetConfig or not petId then return nil end
    local petData = PetConfig[petId]
    if petData and typeof(petData) == "table" and petData.name then
        return tostring(petData.name)
    end
    return nil
end

local function GetTargetModel()
    local success, result = pcall(function()
        local window = BattleCatchPetWindowController.getWindow()
        if window and typeof(window.data) == "table" then
            local data = window.data
            local petId = nil
            if typeof(data.catchPetInfo) == "table" then
                local info = data.catchPetInfo
                if typeof(info.id) == "number" then petId = info.id
                elseif typeof(info.petId) == "number" then petId = info.petId
                elseif typeof(info.configId) == "number" then petId = info.configId
                elseif typeof(info.monsterId) == "number" then petId = info.monsterId
                elseif typeof(info.creatureId) == "number" then petId = info.creatureId
                end
            end
            if not petId then
                if typeof(data.petId) == "number" then petId = data.petId end
                if typeof(data.id) == "number" then petId = data.id end
                if typeof(data.catchPetId) == "number" then petId = data.catchPetId end
                if typeof(data.targetPetId) == "number" then petId = data.targetPetId end
                if typeof(data.configId) == "number" then petId = data.configId end
            end
            if petId then
                local configName = GetPetNameFromConfig(petId)
                if configName then return configName end
            end
            local model = data.targetPetModel
            if typeof(model) == "string" then return model
            elseif typeof(model) == "Instance" then return model.Name
            else return tostring(model) end
        end
        return "Unknown"
    end)
    if success then
        if typeof(result) == "string" then return result
        elseif typeof(result) == "Instance" then return result.Name
        else return tostring(result) end
    end
    return "Unknown"
end

local function BuildTargetLabel()
    local model = GetTargetModel()
    local shiny = IsCurrentTargetShiny()
    local colorful = IsCurrentTargetColorful()
    local tags = {}
    if shiny == true then table.insert(tags, "Shiny")
    elseif shiny == false then table.insert(tags, "Unshiny")
    else table.insert(tags, "?Shiny") end
    if colorful == true then table.insert(tags, "Prismatic")
    elseif colorful == false then table.insert(tags, "Unprismatic")
    else table.insert(tags, "?Prismatic") end
    return tostring(model) .. " (" .. table.concat(tags, "/") .. ")"
end

local function LeaveBattle()
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{ actionType = 8 }}))
    end)
    return success
end

local function PerformCatch(itemId)
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{
            sourcePos = 1, targetPos = 1,
            actionType = 5, itemId = itemId
        }}))
    end)
    return success
end

local function DoCatch(preferredBall)
    local ballName, ballId = GetAvailableBall(preferredBall)
    if not ballId then
        if Config.UseSoftCatch then
            return "catch", BALLS.SoftCatch, "SoftCatch", false
        end
        return "wait", nil, nil, false
    end
    return "catch", ballId, ballName, true
end

local function DecideAction()
    if not IsCatchWindowActive() then return "wait", nil, nil, false end
    UpdateBallInventory()
    local shiny = IsCurrentTargetShiny()
    local pityMaxed = IsPityMaxed()
    local mode = Config.HuntMode
    if pityMaxed == nil then return "wait", nil, nil, false end
    if shiny == nil then shiny = false end

    if mode == "PrismaticShiny" then
        if shiny == true and pityMaxed == true then return DoCatch(Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return DoCatch(Config.NonShiny_NoPity)
        end
    end

    if mode == "ShinyOnly" then
        if shiny == true and pityMaxed == true then return DoCatch(Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if Config.FleeFromShiny then return "flee", nil, nil, false end
            return DoCatch(Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return DoCatch(Config.NonShiny_NoPity)
        end
    end

    if mode == "PrismaticOnly" then
        if shiny == true and pityMaxed == true then return DoCatch(Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if Config.FleeFromShiny then return "flee", nil, nil, false end
            return DoCatch(Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return DoCatch(Config.NonShiny_PityMax) end
        if shiny == false and pityMaxed == false then
            if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return DoCatch(Config.NonShiny_NoPity)
        end
    end

    if mode == "Both" then
        if shiny == true and pityMaxed == true then return DoCatch(Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if Config.FleeFromShiny then return "flee", nil, nil, false end
            return DoCatch(Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then
            if Config.FleeNonShinyAtPityMax then return "flee", nil, nil, false end
            return DoCatch(Config.NonShiny_PityMax)
        end
        if shiny == false and pityMaxed == false then
            if Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return DoCatch(Config.NonShiny_NoPity)
        end
    end
    return "wait", nil, nil, false
end

local function GetCreatureModelCache()
    local ok, cache = pcall(function()
        return Workspace:WaitForChild("RuntimeCache"):WaitForChild("RuntimeCacheServer"):WaitForChild("CreatureModelCache")
    end)
    if ok then return cache end
    return nil
end

local function FindTargetCreatures()
    local cache = GetCreatureModelCache()
    if not cache then return {} end
    local targets = GetCurrentTargets()
    if not targets then return {} end
    local found = {}
    for _, child in ipairs(cache:GetChildren()) do
        local configId = child:GetAttribute("configId")
        for _, targetId in ipairs(targets) do
            if configId == targetId then
                table.insert(found, child.Name)
                break
            end
        end
    end
    return found
end

local function FireEncounter(creatureId)
    if not creatureId then return false end
    local ok = pcall(function() ReqEnterPetBattle:FireServer(creatureId) end)
    return ok
end

local function GetControllerManager()
    local core = ReplicatedStorage:FindFirstChild("Core")
    if not core then return nil end
    local controller = core:FindFirstChild("Controller")
    if not controller then return nil end
    local cm = controller:FindFirstChild("ControllerManager")
    if not cm then return nil end
    return require(cm)
end

local function GetMainBattleController()
    local cm = GetControllerManager()
    if not cm then return nil end
    return cm.getController("MainBattleWindowController")
end

local function ApplyFastBattle()
    local controller = GetMainBattleController()
    if not controller then return false end
    if FastBattleState.hooked then return true end
    FastBattleState.originalGetSpeed = controller.getBattlePlaybackSpeed
    FastBattleState.originalIsEnabled = controller.isBattleSpeedEnabled

    controller.getBattlePlaybackSpeed = function(...)
        local BattleService = nil
        pcall(function()
            local Script = ReplicatedStorage:WaitForChild("Script")
            local Battle = Script:WaitForChild("Battle")
            BattleService = require(Battle:WaitForChild("BattleService"))
        end)
        if BattleService and BattleService.getCurrentBattle() then return 25 end
        return FastBattleState.originalGetSpeed(...)
    end

    controller.isBattleSpeedEnabled = function(...)
        local BattleService = nil
        pcall(function()
            local Script = ReplicatedStorage:WaitForChild("Script")
            local Battle = Script:WaitForChild("Battle")
            BattleService = require(Battle:WaitForChild("BattleService"))
        end)
        if BattleService and BattleService.getCurrentBattle() then return true end
        return FastBattleState.originalIsEnabled(...)
    end

    FastBattleState.hooked = true
    FastBattleState.enabled = true
    print("[Evolink] FastBattle Started")
    return true
end

local function RemoveFastBattle()
    if not FastBattleState.hooked then return end
    local controller = GetMainBattleController()
    if controller then
        if FastBattleState.originalGetSpeed then controller.getBattlePlaybackSpeed = FastBattleState.originalGetSpeed end
        if FastBattleState.originalIsEnabled then controller.isBattleSpeedEnabled = FastBattleState.originalIsEnabled end
    end
    FastBattleState.hooked = false
    FastBattleState.enabled = false
    print("[Evolink] FastBattle Ended")
end

local function ToggleFastBattle()
    if FastBattleState.enabled then RemoveFastBattle() else ApplyFastBattle() end
    return FastBattleState.enabled
end

local function getCurrentBattleData()
    local BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    local battle = BattleService.getCurrentBattle()
    if battle and typeof(battle) == "table" then return battle end
    local ControllerManager = require(Core:WaitForChild("Controller"):WaitForChild("ControllerManager"))
    local mainController = ControllerManager.getController("MainBattleWindowController")
    if mainController and mainController.getBattleDataCache then
        return mainController.getBattleDataCache()
    end
    return nil
end

local function getAllLocalPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.selfPets then return {} end
    return activePets.selfPets
end

local function getAllEnemyPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.enemyPets then return {} end
    return activePets.enemyPets
end

local function getKillOrderTargets(battleData)
    local BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    local success, result = pcall(function() return BattleService.getSequenceKillOrder(battleData) end)
    if success and typeof(result) == "table" and #result > 0 then return result end
    return nil
end

local function getOrderedTarget(battleData)
    local killOrder = getKillOrderTargets(battleData)
    if not killOrder then return nil end
    for _, targetInfo in ipairs(killOrder) do
        if typeof(targetInfo) == "table" and typeof(targetInfo.uid) == "string" then
            if targetInfo.aliveState == 1 then
                local allEnemies = getAllEnemyPets(battleData)
                for _, enemy in ipairs(allEnemies) do
                    if typeof(enemy) == "table" and enemy.uid == targetInfo.uid then
                        return enemy
                    end
                end
                return targetInfo
            end
        end
    end
    return nil
end

local function getPrimaryTarget(battleData)
    if Config.SkillPreferKillOrder then
        local orderedTarget = getOrderedTarget(battleData)
        if orderedTarget then return orderedTarget end
    end
    local allEnemies = getAllEnemyPets(battleData)
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            return enemy
        end
    end
    return allEnemies[1]
end

local function getPetElementIdList(configId)
    local t = {}
    if typeof(configId) ~= "number" then return t end
    local petConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, configId)
    if typeof(petConfig) ~= "table" then return t end
    if typeof(petConfig.elements) ~= "table" then return t end
    for _, v in ipairs(petConfig.elements) do
        if typeof(v) == "number" then table.insert(t, v) end
    end
    return t
end

local function calculateSkillEffectiveness(skillConfig, targetElementIdList)
    if typeof(skillConfig) ~= "table" then
        return ElementConst.ElementEffect.NOTHING, 0, 0
    end
    local power = skillConfig.power
    if typeof(power) ~= "number" or power <= 0 then
        if skillConfig.skillCategory == 3 then return nil, 0, 0 end
        return ElementConst.ElementEffect.NOTHING, 0, 0
    end
    local skillElement = skillConfig.element
    if typeof(skillElement) ~= "number" then
        return ElementConst.ElementEffect.NORMAL, 1.0, power
    end
    if typeof(targetElementIdList) ~= "table" or #targetElementIdList == 0 then
        return ElementConst.ElementEffect.NORMAL, 1.0, power
    end
    local result = ElementModule.calculateMultiElementRestraintRate(skillElement, targetElementIdList)
    if result.result ~= ErrorCode.SUCCEEDED then
        return ElementConst.ElementEffect.NORMAL, 1.0, power
    end
    local effect = result.effect
    local multiplier = EFFECTIVENESS_MULTIPLIER[effect] or 1.0
    local estimatedPower = math.floor(power * multiplier)
    return effect, multiplier, estimatedPower
end

local function calculateAoeEffectiveness(skillConfig, battleData)
    if typeof(skillConfig) ~= "table" then return nil, 0, 0 end
    local allEnemies = getAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, 0, 0 end
    local totalEstPower, totalMultiplier, bestEffect, bestPriority, aliveCount = 0, 0, ElementConst.ElementEffect.NORMAL, 1, 0
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            aliveCount = aliveCount + 1
            local elements = getPetElementIdList(enemy.configId)
            local effect, mult, estPower = calculateSkillEffectiveness(skillConfig, elements)
            totalEstPower = totalEstPower + estPower
            totalMultiplier = totalMultiplier + mult
            local priority = EFFECTIVENESS_MULTIPLIER[effect] or 1
            if priority > bestPriority then bestPriority = priority; bestEffect = effect end
        end
    end
    if aliveCount == 0 then return nil, 0, 0 end
    return bestEffect, totalMultiplier / aliveCount, math.floor(totalEstPower / aliveCount)
end

local function findBestTargetForSkill(battleData, skillConfig)
    if typeof(skillConfig) ~= "table" then return nil, nil, nil, nil, 0, 0 end
    local allEnemies = getAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, nil, nil, nil, 0, 0 end
    local bestEnemy, bestScore, bestPos, bestCampId, bestEffect, bestMultiplier, bestEstPower = nil, -99999, nil, nil, ElementConst.ElementEffect.NORMAL, 1.0, 0
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil, nil, nil, 0, 0 end
    local enemyCamp = nil
    if battleData.camp1 and battleData.camp1.campId == enemyCampId then enemyCamp = battleData.camp1
    elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then enemyCamp = battleData.camp2 end

    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            local elements = getPetElementIdList(enemy.configId)
            local effect, multiplier, estPower = calculateSkillEffectiveness(skillConfig, elements)
            local effPriority = EFFECTIVENESS_PRIORITY[effect] or 3
            local score = (effPriority * 10000) + estPower
            if score > bestScore then
                bestScore = score; bestEnemy = enemy; bestEffect = effect; bestMultiplier = multiplier; bestEstPower = estPower
                if enemyCamp and typeof(enemyCamp.slots) == "table" then
                    for pos, slot in pairs(enemyCamp.slots) do
                        if typeof(slot) == "table" and typeof(slot.pet) == "table" and slot.pet.uid == enemy.uid then
                            bestPos = tonumber(pos); break
                        end
                    end
                end
                if not bestPos then
                    for i, e in ipairs(allEnemies) do
                        if e.uid == enemy.uid then bestPos = i; break end
                    end
                end
                bestCampId = enemyCampId
            end
        end
    end
    return bestEnemy, bestPos or 1, bestCampId, bestEffect, bestMultiplier, bestEstPower
end

local function needsHealing(pet)
    if typeof(pet) ~= "table" then return false end
    local currHp, maxHp = pet.currHp or 0, pet.maxHp or 1
    if maxHp <= 0 then return false end
    return (currHp / maxHp) < Config.SkillHealThreshold
end

local function scoreSkill(skillData, battleData, currentEnergy)
    if typeof(skillData) ~= "table" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillId = skillData.id
    if typeof(skillId) ~= "number" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    if skillData.lock == true then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId)
    if typeof(skillConfig) ~= "table" then return -9999, nil, 0, false, false, 0, nil, nil, nil end
    local skillCategory = skillConfig.skillCategory or 0
    local targetType = skillConfig.targetType or 1
    local isEnergyMove = skillConfig.skillType == 2
    local energyCost = skillConfig.energyCost or 0
    local basePower = skillConfig.power or 0

    if isEnergyMove and energyCost > 0 then
        if typeof(currentEnergy) ~= "number" or currentEnergy < energyCost then
            return -9999, nil, 0, false, false, 0, nil, nil, nil
        end
    end
    if not isEnergyMove then
        local pp = skillData.pp
        if typeof(pp) == "number" and pp <= 0 then
            return -9999, nil, 0, false, false, 0, nil, nil, nil
        end
    end

    local isHeal = false
    if basePower == 0 and skillCategory == 3 then
        local skillName = (skillConfig.name or ""):lower()
        if skillName:find("heal") or skillName:find("recover") or skillName:find("aqua") then isHeal = true end
    end
    if isHeal then return -350, nil, 0, true, true, 1, nil, nil, nil end
    if skillCategory == 3 and basePower <= 0 then return -450, nil, 0, true, false, 0, nil, nil, nil end

    local effect, multiplier, estimatedPower
    local targetCount = 1
    local bestTargetEnemy, bestTargetPos, bestTargetCampId = nil, nil, nil

    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if not Config.SkillAllowMultiTarget then return -9999, nil, 0, false, false, 0, nil, nil, nil end
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = findBestTargetForSkill(battleData, skillConfig)
        local _, _, aoeAvgPower = calculateAoeEffectiveness(skillConfig, battleData)
        targetCount = #getAllEnemyPets(battleData)
        estimatedPower = aoeAvgPower
    elseif targetType == SKILL_TARGET.SELF or targetType == SKILL_TARGET.TEAM then
        return -100, nil, 0, true, false, 0, nil, nil, nil
    else
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = findBestTargetForSkill(battleData, skillConfig)
    end

    local penalty = 0
    if effect == ElementConst.ElementEffect.WEAK then penalty = -300
    elseif effect == ElementConst.ElementEffect.NOTHING then penalty = -500 end

    local effectivenessBonus = 0
    if effect == ElementConst.ElementEffect.EXTREMELY then effectivenessBonus = 10000
    elseif effect == ElementConst.ElementEffect.SUPER then effectivenessBonus = 5000
    elseif effect == ElementConst.ElementEffect.STRONG then effectivenessBonus = 2000 end

    local aoeBonus = 0
    if targetCount > 1 then aoeBonus = estimatedPower * (targetCount - 1) * 0.8 end

    local score = estimatedPower + effectivenessBonus + aoeBonus + penalty
    return score, effect, estimatedPower, true, false, targetCount, bestTargetEnemy, bestTargetPos, bestTargetCampId
end

local function getAllScoredSkillsForPet(battleData, pet)
    if not pet then return {} end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return {} end
    local trainer = BattleDataGetModule.getLocalPlayerTrainer(battleData)
    local currentEnergy = (trainer and typeof(trainer.energy) == "number") and trainer.energy or 0
    local scoredSkills = {}

    for i = 1, 4 do
        local skillData = skills[i]
        local score, effect, estPower, canUse, isHeal, targetCount, bestEnemy, bestPos, bestCampId = scoreSkill(skillData, battleData, currentEnergy)
        if isHeal and needsHealing(pet) then score = 10000 end
        if canUse then
            table.insert(scoredSkills, {
                index = i, score = score, effect = effect, estPower = estPower,
                isHeal = isHeal, targetCount = targetCount, skillData = skillData,
                bestEnemy = bestEnemy, bestPos = bestPos, bestCampId = bestCampId
            })
        end
    end
    table.sort(scoredSkills, function(a, b) return a.score > b.score end)
    return scoredSkills
end

local function getSourcePosForPet(battleData, pet)
    if not pet or typeof(pet) ~= "table" then return 1 end
    local localCampId = BattleDataGetModule.getLocalPlayerCampId(battleData)
    if not localCampId then return 1 end
    local camp = nil
    if battleData.camp1 and battleData.camp1.campId == localCampId then camp = battleData.camp1
    elseif battleData.camp2 and battleData.camp2.campId == localCampId then camp = battleData.camp2 end
    if camp and typeof(camp.slots) == "table" then
        for pos, slot in pairs(camp.slots) do
            if typeof(slot) == "table" and typeof(slot.pet) == "table" and slot.pet.uid == pet.uid then
                return tonumber(pos) or 1
            end
        end
    end
    return 1
end

local function getTargetInfo(battleData, skillConfig, precomputedTarget)
    if not battleData then return nil, nil end
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil end
    if precomputedTarget and precomputedTarget.bestPos and precomputedTarget.bestCampId then
        return precomputedTarget.bestCampId, precomputedTarget.bestPos
    end
    local targetType = skillConfig and skillConfig.targetType or 1

    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if Config.SkillPreferKillOrder then
            local orderedTarget = getOrderedTarget(battleData)
            if orderedTarget and typeof(orderedTarget) == "table" then
                local camp = nil
                if battleData.camp1 and battleData.camp1.campId == enemyCampId then camp = battleData.camp1
                elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then camp = battleData.camp2 end
                if camp and typeof(camp.slots) == "table" then
                    for pos, slot in pairs(camp.slots) do
                        if typeof(slot) == "table" and typeof(slot.pet) == "table" and slot.pet.uid == orderedTarget.uid then
                            return enemyCampId, tonumber(pos) or 1
                        end
                    end
                end
            end
        end
        local _, bestPos, bestCampId = findBestTargetForSkill(battleData, skillConfig)
        if bestPos then return bestCampId or enemyCampId, bestPos end
        return enemyCampId, 1
    end

    if Config.SkillPreferKillOrder then
        local orderedTarget = getOrderedTarget(battleData)
        if orderedTarget and typeof(orderedTarget) == "table" then
            local camp = nil
            if battleData.camp1 and battleData.camp1.campId == enemyCampId then camp = battleData.camp1
            elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then camp = battleData.camp2 end
            if camp and typeof(camp.slots) == "table" then
                for pos, slot in pairs(camp.slots) do
                    if typeof(slot) == "table" and typeof(slot.pet) == "table" and slot.pet.uid == orderedTarget.uid then
                        return enemyCampId, tonumber(pos) or 1
                    end
                end
            end
        end
    end

    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if activePets and activePets.enemyPets then
        for pos, pet in ipairs(activePets.enemyPets) do
            if typeof(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then
                return enemyCampId, pos
            end
        end
    end
    return enemyCampId, 1
end

local function getSkillIdFromPet(pet, index)
    if not pet then return nil end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return nil end
    local skillData = skills[index]
    if typeof(skillData) ~= "table" then return nil end
    return skillData.id
end

local function executeSkillForPet(battleData, pet, skillIndex, precomputedTarget)
    if not pet or not skillIndex then return false, nil end
    local skillId = getSkillIdFromPet(pet, skillIndex)
    if not skillId then
        if Config.SkillDebugMode then warn("Could not get skill ID for pet") end
        return false, nil
    end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId)
    local targetCampId, targetPos = getTargetInfo(battleData, skillConfig, precomputedTarget)
    if not targetCampId or not targetPos then
        if Config.SkillDebugMode then warn("No valid target found") end
        return false, nil
    end
    local sourcePos = getSourcePosForPet(battleData, pet)
    local args = {{
        skillType = skillConfig and skillConfig.skillType or 1,
        targetPos = targetPos, sourcePos = sourcePos,
        actionType = 1, targetCampId = targetCampId, skillId = skillId
    }}
    local skillName = skillConfig and skillConfig.name or "Unknown"
    local targetTypeName = skillConfig and skillConfig.targetType or 1
    local isAoe = (targetTypeName == SKILL_TARGET.ALL or targetTypeName == SKILL_TARGET.ENEMY_TEAM)

    if Config.SkillDebugMode then
        print(string.format("[Evolink] Pet %d (%s) uses %s (ID: %d) | Target: Camp %d Pos %d | AOE: %s",
            sourcePos, pet.name or "Pet", skillName, skillId, targetCampId, targetPos, tostring(isAoe)))
    end

    local success, result = pcall(function() return ReqOperateBattle:InvokeServer(unpack(args)) end)
    if success then
        if VALID_RESPONSES[result] == true then return true, result
        else return false, result end
    else
        if Config.SkillDebugMode then warn("[Evolink] Invoke failed:", result) end
        return false, nil
    end
end

local function executeBestSkillsForAllPets()
    local battleData = getCurrentBattleData()
    if not battleData then
        if Config.SkillDebugMode then warn("No active battle found") end
        return false
    end
    local allPets = getAllLocalPets(battleData)
    if #allPets == 0 then
        if Config.SkillDebugMode then warn("No pets found") end
        return false
    end

    if Config.SkillDebugMode then print("\n=== Evaluating ALL Pets ===") end
    local allMoves = {}

    for petIndex, pet in ipairs(allPets) do
        if typeof(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then
            local scoredSkills = getAllScoredSkillsForPet(battleData, pet)
            local petName = "Unknown"
            if pet.configId then
                local petConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, pet.configId)
                petName = petConfig and petConfig.name or "Unknown"
            end
            local sourcePos = getSourcePosForPet(battleData, pet)
            if #scoredSkills > 0 then
                table.insert(allMoves, {
                    pet = pet, scoredSkills = scoredSkills, currentSkillIndex = 1,
                    sourcePos = sourcePos, petName = petName, bestScore = scoredSkills[1].score
                })
                if Config.SkillDebugMode then
                    print(string.format("  Pet [%d] %s (Pos: %d) | Best: Skill %d | Score: %d | Effect: %s | Target: Pos %d",
                        petIndex, petName, sourcePos, scoredSkills[1].index, scoredSkills[1].score,
                        scoredSkills[1].effect and EFFECTIVENESS_NAMES[scoredSkills[1].effect] or "nil",
                        scoredSkills[1].bestPos or 1))
                end
            end
        end
    end

    if Config.SkillDebugMode then print("===========================\n") end
    if #allMoves == 0 then
        if Config.SkillDebugMode then warn("No valid moves for any pet") end
        return false
    end

    table.sort(allMoves, function(a, b) return a.bestScore > b.bestScore end)
    local anySuccess = false

    for _, move in ipairs(allMoves) do
        local pet = move.pet
        local scoredSkills = move.scoredSkills
        local skillTried, success, resultCode = 0, false, nil

        for i, sk in ipairs(scoredSkills) do
            skillTried = skillTried + 1
            if Config.SkillDebugMode then
                print(string.format("[Evolink] Pet %d (%s) | Fallback [%d/%d] | Skill %d | Score: %d | Effect: %s",
                    move.sourcePos, move.petName, i, #scoredSkills, sk.index, sk.score,
                    sk.effect and EFFECTIVENESS_NAMES[sk.effect] or "nil"))
            end
            success, resultCode = executeSkillForPet(battleData, pet, sk.index, sk)
            if success then
                anySuccess = true
                if not Config.SkillFastMode then task.wait(0.2) end
                break
            else
                if resultCode == 27811 then break end
                if resultCode and MOVE_DISABLED_CODES[resultCode] then
                    if Config.SkillDebugMode then print(string.format("[Evolink] Move disabled (code: %d), trying next fallback...", resultCode)) end
                else
                    if Config.SkillDebugMode then print(string.format("[Evolink] Move failed (code: %s), stopping fallback chain.", tostring(resultCode))) end
                    break
                end
            end
        end

        if not success and skillTried >= #scoredSkills then
            if Config.SkillDebugMode then
                print(string.format("[Evolink] All %d moves failed for Pet %d (%s)", #scoredSkills, move.sourcePos, move.petName))
            end
        end
        battleData = getCurrentBattleData()
        if not battleData then break end
    end
    return anySuccess
end

local function startAutoBattle(interval)
    interval = interval or Config.SkillInterval
    autoBattleEnabled = true
    if Config.SkillDebugMode then
        print("[Evolink] Auto-battle started")
        print("[Evolink] Interval:", interval)
        print("[Evolink] FastMode:", Config.SkillFastMode)
        print("[Evolink] Debug:", Config.SkillDebugMode)
    end
    if autoBattleThread then autoBattleThread = nil end
    autoBattleThread = task.spawn(function()
        while autoBattleEnabled do
            local battleData = getCurrentBattleData()
            if battleData then
                local success = executeBestSkillsForAllPets()
                if success then task.wait(interval) else task.wait(0.2) end
            else
                task.wait(1)
            end
        end
        if Config.SkillDebugMode then print("[Evolink] Auto-battle loop ended") end
    end)
    return autoBattleThread
end

local function stopAutoBattle()
    autoBattleEnabled = false
    autoBattleThread = nil
    if Config.SkillDebugMode then print("[Evolink] Auto-battle stopped") end
end

local function MainLoop()
    while Running do
        task.wait(0.3)

        if not Config.HuntingEnabled and not Config.EncounterEnabled then
            if FastBattleState.enabled then RemoveFastBattle() end
            continue
        end

        if IsInBattle() then
            if not Config.HuntingEnabled then
                if FastBattleState.enabled then RemoveFastBattle() end
                continue
            end

            if Config.FastBattle and not FastBattleState.enabled then
                ApplyFastBattle()
            end

            if not autoBattleEnabled then
                startAutoBattle()
            end

            local catchActive = IsCatchWindowActive()
            if catchActive and not WasInCatchWindow then
                WasInCatchWindow = true
                UpdatePityCacheFromUI()
                SessionStats.encounters = SessionStats.encounters + 1
            end
            if catchActive then UpdatePityCacheFromUI() end

            if not catchActive then
                if PendingLog then print(PendingLog); PendingLog = nil end
                LastAction = nil
                continue
            end

            if LastAction and (tick() - LastActionTime) < 1.5 then continue end

            local targetLabel = BuildTargetLabel()
            local shiny = IsCurrentTargetShiny()
            local action, param, methodName, isGoalCatch = DecideAction()
            local method = methodName or BALL_NAMES[param] or (action == "flee" and "FLEE" or "WAIT")

            if action == "catch" and param then
                PerformCatch(param)
                SessionStats.catches = SessionStats.catches + 1
                if shiny == true then
                    SessionStats.shinyEncounters = SessionStats.shinyEncounters + 1
                    SessionStats.shinyCaught = SessionStats.shinyCaught + 1
                end

                if isGoalCatch and Config.StopOnCatch then
                    SessionStats.goalCatches = SessionStats.goalCatches + 1
                    print("[Evolink] GOAL TARGET CAUGHT! (" .. method .. ") Stopping farm.")
                    print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
                        SessionStats.encounters, SessionStats.catches, SessionStats.goalCatches, SessionStats.flees, SessionStats.shinyCaught))
                    Running = false
                    RemoveFastBattle()
                    stopAutoBattle()
                    return
                end

                if Config.NextChainEnabled then
                    local shouldContinue = AdvanceChain()
                    if not shouldContinue then
                        print("[Evolink] Chain ended. Stopping farm.")
                        print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
                            SessionStats.encounters, SessionStats.catches, SessionStats.goalCatches, SessionStats.flees, SessionStats.shinyCaught))
                        Running = false
                        RemoveFastBattle()
                        stopAutoBattle()
                        return
                    end
                end

                LastAction = action
                LastActionTime = tick()
                task.wait(1.2)
                local prisStr, shinyStr = GetDisplayPityStrings("catch")
                local goalTag = isGoalCatch and " [GOAL]" or " [PITY]"
                PendingLog = string.format("[Evolink] CATCH%s | Target: %s | Method: %s | PrisPity: %s | ShinyPity: %s",
                    goalTag, targetLabel, method, prisStr, shinyStr)
                task.wait(0.5)

            elseif action == "flee" then
                LeaveBattle()
                SessionStats.flees = SessionStats.flees + 1
                LastAction = action
                LastActionTime = tick()
                local prisStr, shinyStr = GetDisplayPityStrings("flee")
                PendingLog = string.format("[Evolink] FLEE | Target: %s | Method: FLEE | PrisPity: %s | ShinyPity: %s",
                    targetLabel, prisStr, shinyStr)
                task.wait(2.5)

            elseif action == "wait" then
                task.wait(0.5)
            end

        else
            WasInCatchWindow = false
            ClearPityCache()
            if PendingLog then print(PendingLog); PendingLog = nil end
            if Config.FastBattle and FastBattleState.enabled then RemoveFastBattle() end
            if autoBattleEnabled then stopAutoBattle() end

            if not Config.EncounterEnabled then continue end

            if (tick() - LastEncounterAttempt) >= Config.EncounterCooldown then
                LastEncounterAttempt = tick()
                local foundCreatures = FindTargetCreatures()
                if #foundCreatures > 0 then
                    for _, creatureId in ipairs(foundCreatures) do
                        FireEncounter(creatureId)
                        print("[Evolink] Fired with creature ID:", creatureId)
                        break
                    end
                else
                    if SessionStats.encounters == 0 and (tick() - LastEncounterAttempt) < 2 then
                        warn("[Evolink] No creatures found for target IDs:", table.concat(GetCurrentTargets() or {}, ", "))
                    end
                end
            end
        end
    end
end

function Evolink.new(userConfig)
    local self = setmetatable({}, Evolink)
    if type(userConfig) == "table" then
        for k, v in pairs(userConfig) do
            if Config[k] ~= nil then
                Config[k] = v
            end
        end
    end
    BuildTargetChain()
    UpdateBallInventory()
    return self
end

function Evolink:SetConfig(key, value)
    if Config[key] ~= nil then
        Config[key] = value
        if key:find("EncounterTarget") then
            BuildTargetChain()
        end
        return true
    end
    return false
end

function Evolink:GetConfig(key)
    return Config[key]
end

function Evolink:GetAllConfig()
    local copy = {}
    for k, v in pairs(Config) do
        copy[k] = v
    end
    return copy
end

function Evolink:Start()
    if Running then
        print("[Evolink] Already running")
        return
    end
    Running = true
    print("[Evolink] Started")
    task.spawn(function()
        local success, err = pcall(MainLoop)
        if not success then
            warn("[Evolink] Crashed: " .. tostring(err))
            warn("[Evolink] Stack: " .. tostring(debug.traceback()))
        end
    end)
end

function Evolink:Stop()
    Running = false
    RemoveFastBattle()
    stopAutoBattle()
    print("[Evolink] Stopped.")
    print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
        SessionStats.encounters, SessionStats.catches, SessionStats.goalCatches, SessionStats.flees, SessionStats.shinyCaught))
end

function Evolink:Restart()
    self:Stop()
    task.wait(0.5)
    self:Start()
end

function Evolink:IsRunning()
    return Running
end

function Evolink:ToggleFastBattle()
    local state = ToggleFastBattle()
    print("[Evolink] FastBattle:", state and "ENABLED" or "DISABLED")
    return state
end

function Evolink:SetFastBattle(enabled)
    if enabled then ApplyFastBattle() else RemoveFastBattle() end
    return FastBattleState.enabled
end

function Evolink:ToggleHunting()
    Config.HuntingEnabled = not Config.HuntingEnabled
    return Config.HuntingEnabled
end

function Evolink:ToggleEncounter()
    Config.EncounterEnabled = not Config.EncounterEnabled
    return Config.EncounterEnabled
end

function Evolink:SetHuntMode(mode)
    if mode ~= "Both" and mode ~= "ShinyOnly" and mode ~= "PrismaticOnly" and mode ~= "PrismaticShiny" then
        warn("[Evolink] Invalid hunt mode. Use: Both, ShinyOnly, PrismaticOnly, PrismaticShiny")
        return false
    end
    Config.HuntMode = mode
    return true
end

function Evolink:SetEncounterTarget(targetList)
    if type(targetList) ~= "table" then
        if type(targetList) == "number" then targetList = {targetList}
        else warn("[Evolink] SetEncounterTarget requires a table of numbers or a single number") return false end
    end
    Config.EncounterTarget = targetList
    BuildTargetChain()
    CurrentChainIndex = 1
    return true
end

function Evolink:AddTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] AddTarget requires a number") return false end
    local targets = GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group") return false end
    for _, id in ipairs(targets) do
        if id == configId then print("[Evolink] Target " .. configId .. " already in current group") return false end
    end
    table.insert(targets, configId)
    return true
end

function Evolink:RemoveTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] RemoveTarget requires a number") return false end
    local targets = GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group") return false end
    for i, id in ipairs(targets) do
        if id == configId then
            table.remove(targets, i)
            return true
        end
    end
    return false
end

function Evolink:ListTargets()
    return GetCurrentTargets()
end

function Evolink:GetTargetChain()
    local chain = {}
    for i, group in ipairs(TargetChain) do
        chain[i] = {group = group, current = (i == CurrentChainIndex)}
    end
    return chain
end

function Evolink:AdvanceChain()
    return AdvanceChain()
end

function Evolink:ResetChain()
    CurrentChainIndex = 1
    return true
end

function Evolink:SetFallbackChain(chain)
    if type(chain) ~= "table" then warn("[Evolink] SetFallbackChain requires a table of ball names") return false end
    Config.FallbackChain = chain
    return true
end

function Evolink:SetBallForScenario(scenario, ballName)
    local validScenarios = {
        NonShiny_NoPity = true, NonShiny_PityMax = true,
        Shiny_NoPity = true, Shiny_PityMax = true,
    }
    if not validScenarios[scenario] then
        warn("[Evolink] Invalid scenario")
        return false
    end
    if not BALLS[ballName] then
        warn("[Evolink] Invalid ball name")
        return false
    end
    Config[scenario] = ballName
    return true
end

function Evolink:GetSessionStats()
    return {
        encounters = SessionStats.encounters,
        catches = SessionStats.catches,
        goalCatches = SessionStats.goalCatches,
        flees = SessionStats.flees,
        shinyEncounters = SessionStats.shinyEncounters,
        shinyCaught = SessionStats.shinyCaught,
    }
end

function Evolink:ResetSessionStats()
    SessionStats = {encounters = 0, catches = 0, flees = 0, shinyEncounters = 0, shinyCaught = 0, goalCatches = 0}
    return true
end

function Evolink:GetStatus()
    return {
        running = Running,
        huntingEnabled = Config.HuntingEnabled,
        encounterEnabled = Config.EncounterEnabled,
        huntMode = Config.HuntMode,
        fastBattle = FastBattleState.enabled,
        autoBattle = autoBattleEnabled,
        currentChainIndex = CurrentChainIndex,
        currentTargets = GetCurrentTargets(),
        ballInventory = UpdateBallInventory(),
    }
end

function Evolink:PrintConfig()
    print("[Evolink] Current Configuration:")
    for k, v in pairs(Config) do
        if type(v) == "table" then
            print("  " .. k .. ": " .. table.concat(v, ", "))
        else
            print("  " .. k .. ": " .. tostring(v))
        end
    end
end

function Evolink:SetSkillSettings(settings)
    if type(settings) ~= "table" then warn("[Evolink] SetSkillSettings requires a table") return false end
    if settings.healThreshold ~= nil then Config.SkillHealThreshold = type(settings.healThreshold) == "number" and settings.healThreshold or Config.SkillHealThreshold end
    if settings.preferKillOrder ~= nil then Config.SkillPreferKillOrder = settings.preferKillOrder == true end
    if settings.allowMultiTarget ~= nil then Config.SkillAllowMultiTarget = settings.allowMultiTarget == true end
    if settings.debugMode ~= nil then Config.SkillDebugMode = settings.debugMode == true end
    if settings.fastMode ~= nil then Config.SkillFastMode = settings.fastMode == true end
    if settings.interval ~= nil then Config.SkillInterval = type(settings.interval) == "number" and settings.interval or Config.SkillInterval end
    return true
end

function Evolink:GetSkillSettings()
    return {
        healThreshold = Config.SkillHealThreshold,
        preferKillOrder = Config.SkillPreferKillOrder,
        allowMultiTarget = Config.SkillAllowMultiTarget,
        debugMode = Config.SkillDebugMode,
        fastMode = Config.SkillFastMode,
        interval = Config.SkillInterval,
    }
end

return Evolink
