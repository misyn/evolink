-- Evolink Module - Part 1: Module Structure & Config Management
-- OOP Wrapper for AutoCatch + Battle Automation

local Evolink = {}
Evolink.__index = Evolink

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BattleRemote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")
local ReqEnterPetBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqEnterPetBattle")

local BattleCatchPetWindowController = nil
local BagService = nil
local PetConfig = nil
local ShinyPetLotteryStorage = nil
local ShinyPetLotteryService = nil
local ErrorCode = nil
local SUCCEEDED = 0

local Core = ReplicatedStorage:WaitForChild("Core")
local Script = ReplicatedStorage:WaitForChild("Script")
local Config = Core:WaitForChild("Config")
local ConfigDataManager = nil
local ConfigConst = nil
local BattleDataGetModule = nil
local ElementModule = nil
local ElementConst = nil
local ReqOperateBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")

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

local UNLIMITED_BALLS = {Common = true, SoftCatch = true}

local EFFECTIVENESS_MULTIPLIER = {}
local EFFECTIVENESS_NAMES = {}
local EFFECTIVENESS_PRIORITY = {}
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

function Evolink.new()
    local self = setmetatable({}, Evolink)

    self.Config = {
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

    self.Running = false
    self.LastAction = nil
    self.LastActionTime = 0
    self.PendingLog = nil
    self.WasInCatchWindow = false
    self.LastEncounterAttempt = 0
    self.CurrentChainIndex = 1
    self.TargetChain = {}
    self.BallInventory = {}
    self.PityCache = {
        prismaticCurrent = nil, prismaticMax = nil,
        shinyCurrent = nil, shinyMax = nil,
        lastUpdated = 0,
    }
    self.FastBattleState = {
        enabled = false, originalGetSpeed = nil, originalIsEnabled = nil, hooked = false
    }
    self.AutoBattleState = {
        enabled = false, thread = nil
    }
    self.SessionStats = {
        encounters = 0, catches = 0, flees = 0,
        shinyEncounters = 0, shinyCaught = 0, goalCatches = 0,
    }
    self.MainThread = nil

    self:InitModules()
    self:BuildTargetChain()
    self:UpdateBallInventory()

    return self
end

function Evolink:InitModules()
    pcall(function()
        BattleCatchPetWindowController = require(ReplicatedStorage.Controller.BattleCatchPetWindowController)
    end)
    pcall(function()
        BagService = require(ReplicatedStorage.Script.Bag.BagService)
    end)
    pcall(function()
        PetConfig = require(game:GetService("ReplicatedStorage").Config.PetConfig)
    end)
    pcall(function()
        ShinyPetLotteryStorage = require(ReplicatedStorage:WaitForChild("Storage"):WaitForChild("ShinyPetLotteryStorage"))
    end)
    pcall(function()
        ShinyPetLotteryService = require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("ShinyPetLottery"):WaitForChild("ShinyPetLotteryService"))
    end)
    pcall(function()
        ErrorCode = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Tools"):WaitForChild("ErrorCode"))
        SUCCEEDED = ErrorCode.SUCCEEDED or 0
    end)
    pcall(function()
        ConfigDataManager = require(Config:WaitForChild("ConfigDataManager"))
    end)
    pcall(function()
        ConfigConst = require(Config:WaitForChild("ConfigConst"))
    end)
    pcall(function()
        BattleDataGetModule = require(Script:WaitForChild("MainBattleWindow"):WaitForChild("BattleDataGetModule"))
    end)
    pcall(function()
        ElementModule = require(Script:WaitForChild("Element"):WaitForChild("ElementModule"))
    end)
    pcall(function()
        ElementConst = require(Script:WaitForChild("Element"):WaitForChild("Basic"):WaitForChild("ElementConst"))
        if ElementConst and ElementConst.ElementEffect then
            EFFECTIVENESS_MULTIPLIER = {
                [ElementConst.ElementEffect.EXTREMELY] = 4.0,
                [ElementConst.ElementEffect.SUPER] = 4.0,
                [ElementConst.ElementEffect.STRONG] = 2.0,
                [ElementConst.ElementEffect.NORMAL] = 1.0,
                [ElementConst.ElementEffect.WEAK] = 0.5,
                [ElementConst.ElementEffect.NOTHING] = 0.0,
            }
            EFFECTIVENESS_NAMES = {
                [ElementConst.ElementEffect.EXTREMELY] = "EXTREMELY",
                [ElementConst.ElementEffect.SUPER] = "SUPER",
                [ElementConst.ElementEffect.STRONG] = "STRONG",
                [ElementConst.ElementEffect.NORMAL] = "NORMAL",
                [ElementConst.ElementEffect.WEAK] = "WEAK",
                [ElementConst.ElementEffect.NOTHING] = "NOTHING",
            }
            EFFECTIVENESS_PRIORITY = {
                [ElementConst.ElementEffect.EXTREMELY] = 6,
                [ElementConst.ElementEffect.SUPER] = 5,
                [ElementConst.ElementEffect.STRONG] = 4,
                [ElementConst.ElementEffect.NORMAL] = 3,
                [ElementConst.ElementEffect.WEAK] = 2,
                [ElementConst.ElementEffect.NOTHING] = 1,
            }
        end
    end)
end

function Evolink:BuildTargetChain()
    self.TargetChain = {}
    local function addIfValid(t)
        if type(t) == "table" and #t > 0 then
            table.insert(self.TargetChain, t)
        end
    end
    addIfValid(self.Config.EncounterTarget)
    addIfValid(self.Config.EncounterTarget2)
    addIfValid(self.Config.EncounterTarget3)
    addIfValid(self.Config.EncounterTarget4)
    addIfValid(self.Config.EncounterTarget5)
end

function Evolink:GetCurrentTargets()
    if self.CurrentChainIndex <= #self.TargetChain then
        return self.TargetChain[self.CurrentChainIndex]
    end
    if self.Config.LoopAfterChainEnd and #self.TargetChain > 0 then
        self.CurrentChainIndex = 1
        return self.TargetChain[1]
    end
    return nil
end

function Evolink:AdvanceChain()
    if not self.Config.NextChainEnabled then return false end
    self.CurrentChainIndex = self.CurrentChainIndex + 1
    if self.CurrentChainIndex > #self.TargetChain then
        if self.Config.LoopAfterChainEnd then
            self.CurrentChainIndex = 1
            return true
        else
            return false
        end
    end
    return true
end

function Evolink:UpdateBallInventory()
    self.BallInventory = {}
    for name, itemId in pairs(BALLS) do
        if UNLIMITED_BALLS[name] then
            self.BallInventory[name] = math.huge
        else
            local count = 0
            pcall(function()
                count = BagService.getItemNumById(itemId)
            end)
            self.BallInventory[name] = (typeof(count) == "number" and count > 0) and count or 0
        end
    end
    return self.BallInventory
end

function Evolink:HasBall(ballName)
    return (self.BallInventory[ballName] or 0) > 0
end

function Evolink:GetAvailableBall(preferredBallName)
    local startIndex = 1
    for i, name in ipairs(self.Config.FallbackChain) do
        if name == preferredBallName then startIndex = i break end
    end
    for i = startIndex, #self.Config.FallbackChain do
        local ballName = self.Config.FallbackChain[i]
        if self:HasBall(ballName) then return ballName, BALLS[ballName] end
    end
    return nil, nil
end

function Evolink:IsInBattle()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("MainBattleWindow")
    return window and window.Enabled == true
end

function Evolink:IsCatchWindowActive()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("BattleCatchPetWindow")
    return window and window.Enabled == true
end

function Evolink:GetTargetPetId()
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

function Evolink:UpdatePityCacheFromUI()
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
                    self.PityCache.prismaticCurrent = tonumber(current)
                    self.PityCache.prismaticMax = tonumber(max)
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
                    self.PityCache.shinyCurrent = tonumber(current)
                    self.PityCache.shinyMax = tonumber(max)
                    break
                end
            end
        end
        self.PityCache.lastUpdated = tick()
    end
end

function Evolink:GetDisplayPityStrings(actionType)
    local prisCurrent, prisMax = self.PityCache.prismaticCurrent, self.PityCache.prismaticMax
    local shinyCurrent, shinyMax = self.PityCache.shinyCurrent, self.PityCache.shinyMax
    if shinyCurrent and shinyMax then shinyCurrent = shinyCurrent + 1 end
    if actionType == "catch" and prisCurrent and prisMax then prisCurrent = prisCurrent + 1 end
    local prisStr = (prisCurrent and prisMax) and (prisCurrent .. "/" .. prisMax) or "??/??"
    local shinyStr = (shinyCurrent and shinyMax) and (shinyCurrent .. "/" .. shinyMax) or "??/??"
    return prisStr, shinyStr
end

function Evolink:ClearPityCache()
    self.PityCache.prismaticCurrent = nil
    self.PityCache.prismaticMax = nil
    self.PityCache.shinyCurrent = nil
    self.PityCache.shinyMax = nil
    self.PityCache.lastUpdated = 0
end

function Evolink:GetPrismaticPityFromModule()
    local petId = self:GetTargetPetId()
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

function Evolink:GetShinyPityFromModule()
    local petId = self:GetTargetPetId()
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

function Evolink:GetPrismaticPity()
    local current, max = self:GetPrismaticPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if self.PityCache.prismaticCurrent and self.PityCache.prismaticMax then
        return self.PityCache.prismaticCurrent, self.PityCache.prismaticMax
    end
    return nil, nil
end

function Evolink:GetShinyPity()
    local current, max = self:GetShinyPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if self.PityCache.shinyCurrent and self.PityCache.shinyMax then
        return self.PityCache.shinyCurrent, self.PityCache.shinyMax
    end
    return nil, nil
end

function Evolink:IsPityMaxed()
    local current, max = self:GetPrismaticPity()
    if type(current) ~= "number" or type(max) ~= "number" then return nil end
    return current >= (max - 1)
end

function Evolink:IsCurrentTargetShiny()
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

function Evolink:IsCurrentTargetColorful()
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

function Evolink:GetPetNameFromConfig(petId)
    if not PetConfig or not petId then return nil end
    local petData = PetConfig[petId]
    if petData and typeof(petData) == "table" and petData.name then
        return tostring(petData.name)
    end
    return nil
end

function Evolink:GetTargetModel()
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
                local configName = self:GetPetNameFromConfig(petId)
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

function Evolink:BuildTargetLabel()
    local model = self:GetTargetModel()
    local shiny = self:IsCurrentTargetShiny()
    local colorful = self:IsCurrentTargetColorful()
    local tags = {}
    if shiny == true then table.insert(tags, "Shiny")
    elseif shiny == false then table.insert(tags, "Unshiny")
    else table.insert(tags, "?Shiny") end
    if colorful == true then table.insert(tags, "Prismatic")
    elseif colorful == false then table.insert(tags, "Unprismatic")
    else table.insert(tags, "?Prismatic") end
    return tostring(model) .. " (" .. table.concat(tags, "/") .. ")"
end

function Evolink:LeaveBattle()
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{ actionType = 8 }}))
    end)
    return success
end

function Evolink:PerformCatch(itemId)
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{
            sourcePos = 1, targetPos = 1,
            actionType = 5, itemId = itemId
        }}))
    end)
    return success
end

function Evolink:DoCatch(preferredBall)
    local ballName, ballId = self:GetAvailableBall(preferredBall)
    if not ballId then
        if self.Config.UseSoftCatch then
            return "catch", BALLS.SoftCatch, "SoftCatch", false
        end
        return "wait", nil, nil, false
    end
    return "catch", ballId, ballName, true
end

function Evolink:DecideAction()
    if not self:IsCatchWindowActive() then return "wait", nil, nil, false end
    self:UpdateBallInventory()
    local shiny = self:IsCurrentTargetShiny()
    local pityMaxed = self:IsPityMaxed()
    local mode = self.Config.HuntMode
    if pityMaxed == nil then return "wait", nil, nil, false end
    if shiny == nil then shiny = false end

    if mode == "PrismaticShiny" then
        if shiny == true and pityMaxed == true then return self:DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "ShinyOnly" then
        if shiny == true and pityMaxed == true then return self:DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "PrismaticOnly" then
        if shiny == true and pityMaxed == true then return self:DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return self:DoCatch(self.Config.NonShiny_PityMax) end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "Both" then
        if shiny == true and pityMaxed == true then return self:DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then
            if self.Config.FleeNonShinyAtPityMax then return "flee", nil, nil, false end
            return self:DoCatch(self.Config.NonShiny_PityMax)
        end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:DoCatch(self.Config.NonShiny_NoPity)
        end
    end
    return "wait", nil, nil, false
end

function Evolink:GetCreatureModelCache()
    local ok, cache = pcall(function()
        return Workspace:WaitForChild("RuntimeCache"):WaitForChild("RuntimeCacheServer"):WaitForChild("CreatureModelCache")
    end)
    if ok then return cache end
    return nil
end

function Evolink:FindTargetCreatures()
    local cache = self:GetCreatureModelCache()
    if not cache then return {} end
    local targets = self:GetCurrentTargets()
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

function Evolink:FireEncounter(creatureId)
    if not creatureId then return false end
    local ok = pcall(function() ReqEnterPetBattle:FireServer(creatureId) end)
    return ok
end

function Evolink:GetControllerManager()
    local core = ReplicatedStorage:FindFirstChild("Core")
    if not core then return nil end
    local controller = core:FindFirstChild("Controller")
    if not controller then return nil end
    local cm = controller:FindFirstChild("ControllerManager")
    if not cm then return nil end
    return require(cm)
end

function Evolink:GetMainBattleController()
    local cm = self:GetControllerManager()
    if not cm then return nil end
    return cm.getController("MainBattleWindowController")
end

function Evolink:ApplyFastBattle()
    local controller = self:GetMainBattleController()
    if not controller then return false end
    if self.FastBattleState.hooked then return true end
    self.FastBattleState.originalGetSpeed = controller.getBattlePlaybackSpeed
    self.FastBattleState.originalIsEnabled = controller.isBattleSpeedEnabled
    controller.getBattlePlaybackSpeed = function(...)
        local BattleService = nil
        pcall(function()
            local Script = ReplicatedStorage:WaitForChild("Script")
            local Battle = Script:WaitForChild("Battle")
            BattleService = require(Battle:WaitForChild("BattleService"))
        end)
        if BattleService and BattleService.getCurrentBattle() then return 25 end
        return self.FastBattleState.originalGetSpeed(...)
    end
    controller.isBattleSpeedEnabled = function(...)
        local BattleService = nil
        pcall(function()
            local Script = ReplicatedStorage:WaitForChild("Script")
            local Battle = Script:WaitForChild("Battle")
            BattleService = require(Battle:WaitForChild("BattleService"))
        end)
        if BattleService and BattleService.getCurrentBattle() then return true end
        return self.FastBattleState.originalIsEnabled(...)
    end
    self.FastBattleState.hooked = true
    self.FastBattleState.enabled = true
    return true
end

function Evolink:RemoveFastBattle()
    if not self.FastBattleState.hooked then return end
    local controller = self:GetMainBattleController()
    if controller then
        if self.FastBattleState.originalGetSpeed then controller.getBattlePlaybackSpeed = self.FastBattleState.originalGetSpeed end
        if self.FastBattleState.originalIsEnabled then controller.isBattleSpeedEnabled = self.FastBattleState.originalIsEnabled end
    end
    self.FastBattleState.hooked = false
    self.FastBattleState.enabled = false
end

function Evolink:ToggleFastBattle()
    if self.FastBattleState.enabled then self:RemoveFastBattle() else self:ApplyFastBattle() end
    return self.FastBattleState.enabled
end

function Evolink:getCurrentBattleData()
    local BattleService = nil
    pcall(function()
        BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    end)
    if BattleService then
        local battle = BattleService.getCurrentBattle()
        if battle and typeof(battle) == "table" then return battle end
    end
    local ControllerManager = nil
    pcall(function()
        ControllerManager = require(Core:WaitForChild("Controller"):WaitForChild("ControllerManager"))
    end)
    if ControllerManager then
        local mainController = ControllerManager.getController("MainBattleWindowController")
        if mainController and mainController.getBattleDataCache then
            return mainController.getBattleDataCache()
        end
    end
    return nil
end

function Evolink:getAllLocalPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    if not BattleDataGetModule then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.selfPets then return {} end
    return activePets.selfPets
end

function Evolink:getAllEnemyPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    if not BattleDataGetModule then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.enemyPets then return {} end
    return activePets.enemyPets
end

function Evolink:getKillOrderTargets(battleData)
    local BattleService = nil
    pcall(function()
        BattleService = require(Script:WaitForChild("Battle"):WaitForChild("BattleService"))
    end)
    if not BattleService then return nil end
    local success, result = pcall(function() return BattleService.getSequenceKillOrder(battleData) end)
    if success and typeof(result) == "table" and #result > 0 then return result end
    return nil
end

function Evolink:getOrderedTarget(battleData)
    local killOrder = self:getKillOrderTargets(battleData)
    if not killOrder then return nil end
    for _, targetInfo in ipairs(killOrder) do
        if typeof(targetInfo) == "table" and typeof(targetInfo.uid) == "string" then
            if targetInfo.aliveState == 1 then
                local allEnemies = self:getAllEnemyPets(battleData)
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

function Evolink:getPrimaryTarget(battleData)
    if self.Config.SkillPreferKillOrder then
        local orderedTarget = self:getOrderedTarget(battleData)
        if orderedTarget then return orderedTarget end
    end
    local allEnemies = self:getAllEnemyPets(battleData)
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            return enemy
        end
    end
    return allEnemies[1]
end

function Evolink:getPetElementIdList(configId)
    local t = {}
    if typeof(configId) ~= "number" then return t end
    if not ConfigDataManager then return t end
    local petConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, configId)
    if typeof(petConfig) ~= "table" then return t end
    if typeof(petConfig.elements) ~= "table" then return t end
    for _, v in ipairs(petConfig.elements) do
        if typeof(v) == "number" then table.insert(t, v) end
    end
    return t
end

function Evolink:calculateSkillEffectiveness(skillConfig, targetElementIdList)
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

function Evolink:calculateAoeEffectiveness(skillConfig, battleData)
    if typeof(skillConfig) ~= "table" then return nil, 0, 0 end
    local allEnemies = self:getAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, 0, 0 end
    local totalEstPower, totalMultiplier, bestEffect, bestPriority, aliveCount = 0, 0, ElementConst.ElementEffect.NORMAL, 1, 0
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            aliveCount = aliveCount + 1
            local elements = self:getPetElementIdList(enemy.configId)
            local effect, mult, estPower = self:calculateSkillEffectiveness(skillConfig, elements)
            totalEstPower = totalEstPower + estPower
            totalMultiplier = totalMultiplier + mult
            local priority = EFFECTIVENESS_MULTIPLIER[effect] or 1
            if priority > bestPriority then bestPriority = priority; bestEffect = effect end
        end
    end
    if aliveCount == 0 then return nil, 0, 0 end
    return bestEffect, totalMultiplier / aliveCount, math.floor(totalEstPower / aliveCount)
end

function Evolink:findBestTargetForSkill(battleData, skillConfig)
    if typeof(skillConfig) ~= "table" then return nil, nil, nil, nil, 0, 0 end
    local allEnemies = self:getAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, nil, nil, nil, 0, 0 end
    local bestEnemy, bestScore, bestPos, bestCampId, bestEffect, bestMultiplier, bestEstPower = nil, -99999, nil, nil, ElementConst.ElementEffect.NORMAL, 1.0, 0
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil, nil, nil, 0, 0 end
    local enemyCamp = nil
    if battleData.camp1 and battleData.camp1.campId == enemyCampId then enemyCamp = battleData.camp1
    elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then enemyCamp = battleData.camp2 end
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            local elements = self:getPetElementIdList(enemy.configId)
            local effect, multiplier, estPower = self:calculateSkillEffectiveness(skillConfig, elements)
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

function Evolink:needsHealing(pet)
    if typeof(pet) ~= "table" then return false end
    local currHp, maxHp = pet.currHp or 0, pet.maxHp or 1
    if maxHp <= 0 then return false end
    return (currHp / maxHp) < self.Config.SkillHealThreshold
end

function Evolink:scoreSkill(skillData, battleData, currentEnergy)
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
        if not self.Config.SkillAllowMultiTarget then return -9999, nil, 0, false, false, 0, nil, nil, nil end
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = self:findBestTargetForSkill(battleData, skillConfig)
        local _, _, aoeAvgPower = self:calculateAoeEffectiveness(skillConfig, battleData)
        targetCount = #self:getAllEnemyPets(battleData)
        estimatedPower = aoeAvgPower
    elseif targetType == SKILL_TARGET.SELF or targetType == SKILL_TARGET.TEAM then
        return -100, nil, 0, true, false, 0, nil, nil, nil
    else
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = self:findBestTargetForSkill(battleData, skillConfig)
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

function Evolink:getAllScoredSkillsForPet(battleData, pet)
    if not pet then return {} end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return {} end
    local trainer = BattleDataGetModule.getLocalPlayerTrainer(battleData)
    local currentEnergy = (trainer and typeof(trainer.energy) == "number") and trainer.energy or 0
    local scoredSkills = {}
    for i = 1, 4 do
        local skillData = skills[i]
        local score, effect, estPower, canUse, isHeal, targetCount, bestEnemy, bestPos, bestCampId = self:scoreSkill(skillData, battleData, currentEnergy)
        if isHeal and self:needsHealing(pet) then score = 10000 end
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

function Evolink:getSourcePosForPet(battleData, pet)
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

function Evolink:getTargetInfo(battleData, skillConfig, precomputedTarget)
    if not battleData then return nil, nil end
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil end
    if precomputedTarget and precomputedTarget.bestPos and precomputedTarget.bestCampId then
        return precomputedTarget.bestCampId, precomputedTarget.bestPos
    end
    local targetType = skillConfig and skillConfig.targetType or 1
    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if self.Config.SkillPreferKillOrder then
            local orderedTarget = self:getOrderedTarget(battleData)
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
        local _, bestPos, bestCampId = self:findBestTargetForSkill(battleData, skillConfig)
        if bestPos then return bestCampId or enemyCampId, bestPos end
        return enemyCampId, 1
    end
    if self.Config.SkillPreferKillOrder then
        local orderedTarget = self:getOrderedTarget(battleData)
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

function Evolink:getSkillIdFromPet(pet, index)
    if not pet then return nil end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return nil end
    local skillData = skills[index]
    if typeof(skillData) ~= "table" then return nil end
    return skillData.id
end

function Evolink:executeSkillForPet(battleData, pet, skillIndex, precomputedTarget)
    if not pet or not skillIndex then return false, nil end
    local skillId = self:getSkillIdFromPet(pet, skillIndex)
    if not skillId then return false, nil end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId)
    local targetCampId, targetPos = self:getTargetInfo(battleData, skillConfig, precomputedTarget)
    if not targetCampId or not targetPos then return false, nil end
    local sourcePos = self:getSourcePosForPet(battleData, pet)
    local args = {{
        skillType = skillConfig and skillConfig.skillType or 1,
        targetPos = targetPos, sourcePos = sourcePos,
        actionType = 1, targetCampId = targetCampId, skillId = skillId
    }}
    local success, result = pcall(function() return ReqOperateBattle:InvokeServer(unpack(args)) end)
    if success then
        if VALID_RESPONSES[result] == true then return true, result
        else return false, result end
    else
        return false, nil
    end
end

function Evolink:executeBestSkillsForAllPets()
    local battleData = self:getCurrentBattleData()
    if not battleData then return false end
    local allPets = self:getAllLocalPets(battleData)
    if #allPets == 0 then return false end
    local allMoves = {}
    for petIndex, pet in ipairs(allPets) do
        if typeof(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then
            local scoredSkills = self:getAllScoredSkillsForPet(battleData, pet)
            local petName = "Unknown"
            if pet.configId then
                local petConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, pet.configId)
                petName = petConfig and petConfig.name or "Unknown"
            end
            local sourcePos = self:getSourcePosForPet(battleData, pet)
            if #scoredSkills > 0 then
                table.insert(allMoves, {
                    pet = pet, scoredSkills = scoredSkills, currentSkillIndex = 1,
                    sourcePos = sourcePos, petName = petName, bestScore = scoredSkills[1].score
                })
            end
        end
    end
    if #allMoves == 0 then return false end
    table.sort(allMoves, function(a, b) return a.bestScore > b.bestScore end)
    local anySuccess = false
    for _, move in ipairs(allMoves) do
        local pet = move.pet
        local scoredSkills = move.scoredSkills
        local skillTried, success, resultCode = 0, false, nil
        for i, sk in ipairs(scoredSkills) do
            skillTried = skillTried + 1
            success, resultCode = self:executeSkillForPet(battleData, pet, sk.index, sk)
            if success then
                anySuccess = true
                if not self.Config.SkillFastMode then task.wait(0.2) end
                break
            else
                if resultCode == 27811 then break end
                if resultCode and MOVE_DISABLED_CODES[resultCode] then
                else
                    break
                end
            end
        end
        battleData = self:getCurrentBattleData()
        if not battleData then break end
    end
    return anySuccess
end

function Evolink:startAutoBattle(interval)
    interval = interval or self.Config.SkillInterval
    self.AutoBattleState.enabled = true
    if self.AutoBattleState.thread then self.AutoBattleState.thread = nil end
    self.AutoBattleState.thread = task.spawn(function()
        while self.AutoBattleState.enabled do
            local battleData = self:getCurrentBattleData()
            if battleData then
                local success = self:executeBestSkillsForAllPets()
                if success then task.wait(interval) else task.wait(0.2) end
            else
                task.wait(1)
            end
        end
    end)
    return self.AutoBattleState.thread
end

function Evolink:stopAutoBattle()
    self.AutoBattleState.enabled = false
    self.AutoBattleState.thread = nil
end

function Evolink:MainLoop()
    while self.Running do
        task.wait(0.3)
        if not self.Config.HuntingEnabled and not self.Config.EncounterEnabled then
            if self.FastBattleState.enabled then self:RemoveFastBattle() end
            continue
        end
        if self:IsInBattle() then
            if not self.Config.HuntingEnabled then
                if self.FastBattleState.enabled then self:RemoveFastBattle() end
                continue
            end
            if self.Config.FastBattle and not self.FastBattleState.enabled then
                self:ApplyFastBattle()
            end
            if not self.AutoBattleState.enabled then
                self:startAutoBattle()
            end
            local catchActive = self:IsCatchWindowActive()
            if catchActive and not self.WasInCatchWindow then
                self.WasInCatchWindow = true
                self:UpdatePityCacheFromUI()
                self.SessionStats.encounters = self.SessionStats.encounters + 1
            end
            if catchActive then self:UpdatePityCacheFromUI() end
            if not catchActive then
                if self.PendingLog then print(self.PendingLog); self.PendingLog = nil end
                self.LastAction = nil
                continue
            end
            if self.LastAction and (tick() - self.LastActionTime) < 1.5 then continue end
            local targetLabel = self:BuildTargetLabel()
            local shiny = self:IsCurrentTargetShiny()
            local action, param, methodName, isGoalCatch = self:DecideAction()
            local method = methodName or BALL_NAMES[param] or (action == "flee" and "FLEE" or "WAIT")
            if action == "catch" and param then
                self:PerformCatch(param)
                self.SessionStats.catches = self.SessionStats.catches + 1
                if shiny == true then
                    self.SessionStats.shinyEncounters = self.SessionStats.shinyEncounters + 1
                    self.SessionStats.shinyCaught = self.SessionStats.shinyCaught + 1
                end
                if isGoalCatch and self.Config.StopOnCatch then
                    self.SessionStats.goalCatches = self.SessionStats.goalCatches + 1
                    print("[Evolink] GOAL TARGET CAUGHT! (" .. method .. ") Stopping farm.")
                    print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
                        self.SessionStats.encounters, self.SessionStats.catches, self.SessionStats.goalCatches, self.SessionStats.flees, self.SessionStats.shinyCaught))
                    self.Running = false
                    self:RemoveFastBattle()
                    self:stopAutoBattle()
                    return
                end
                if self.Config.NextChainEnabled then
                    local shouldContinue = self:AdvanceChain()
                    if not shouldContinue then
                        print("[Evolink] Chain ended. Stopping farm.")
                        print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
                            self.SessionStats.encounters, self.SessionStats.catches, self.SessionStats.goalCatches, self.SessionStats.flees, self.SessionStats.shinyCaught))
                        self.Running = false
                        self:RemoveFastBattle()
                        self:stopAutoBattle()
                        return
                    end
                end
                self.LastAction = action
                self.LastActionTime = tick()
                task.wait(1.2)
                local prisStr, shinyStr = self:GetDisplayPityStrings("catch")
                local goalTag = isGoalCatch and " [GOAL]" or " [PITY]"
                self.PendingLog = string.format("[Evolink] CATCH%s | Target: %s | Method: %s | PrisPity: %s | ShinyPity: %s",
                    goalTag, targetLabel, method, prisStr, shinyStr)
                task.wait(0.5)
            elseif action == "flee" then
                self:LeaveBattle()
                self.SessionStats.flees = self.SessionStats.flees + 1
                self.LastAction = action
                self.LastActionTime = tick()
                local prisStr, shinyStr = self:GetDisplayPityStrings("flee")
                self.PendingLog = string.format("[Evolink] FLEE | Target: %s | Method: FLEE | PrisPity: %s | ShinyPity: %s",
                    targetLabel, prisStr, shinyStr)
                task.wait(2.5)
            elseif action == "wait" then
                task.wait(0.5)
            end
        else
            self.WasInCatchWindow = false
            self:ClearPityCache()
            if self.PendingLog then print(self.PendingLog); self.PendingLog = nil end
            if self.Config.FastBattle and self.FastBattleState.enabled then self:RemoveFastBattle() end
            if self.AutoBattleState.enabled then self:stopAutoBattle() end
            if not self.Config.EncounterEnabled then continue end
            if (tick() - self.LastEncounterAttempt) >= self.Config.EncounterCooldown then
                self.LastEncounterAttempt = tick()
                local foundCreatures = self:FindTargetCreatures()
                if #foundCreatures > 0 then
                    for _, creatureId in ipairs(foundCreatures) do
                        self:FireEncounter(creatureId)
                        print("[Evolink] Encounter fired with creature ID:", creatureId)
                        break
                    end
                end
            end
        end
    end
end

function Evolink:Start()
    if self.Running then return end
    self.Running = true
    self.MainThread = task.spawn(function()
        local success, err = pcall(function() self:MainLoop() end)
        if not success then
            warn("[Evolink] Crashed: " .. tostring(err))
            warn("[Evolink] Stack: " .. tostring(debug.traceback()))
        end
    end)
end

function Evolink:Stop()
    self.Running = false
    self:RemoveFastBattle()
    self:stopAutoBattle()
    print("[Evolink] Stopped.")
    print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
        self.SessionStats.encounters, self.SessionStats.catches, self.SessionStats.goalCatches, self.SessionStats.flees, self.SessionStats.shinyCaught))
end

function Evolink:Restart()
    self.Running = true
    self.MainThread = task.spawn(function()
        local success, err = pcall(function() self:MainLoop() end)
        if not success then
            warn("[Evolink] Crashed: " .. tostring(err))
            warn("[Evolink] Stack: " .. tostring(debug.traceback()))
        end
    end)
end

function Evolink:SetConfig(key, value)
    if self.Config[key] == nil then
        warn("[Evolink] Invalid config key: " .. tostring(key))
        return
    end
    self.Config[key] = value
    if key:sub(1, 9) == "Encounter" and key ~= "EncounterCooldown" then
        self:BuildTargetChain()
        self.CurrentChainIndex = 1
    end
    print("[Evolink] Config set: " .. tostring(key) .. " = " .. tostring(value))
end

function Evolink:GetConfig(key)
    return self.Config[key]
end

function Evolink:ToggleHunting()
    self.Config.HuntingEnabled = not self.Config.HuntingEnabled
    print("[Evolink] HuntingEnabled: " .. tostring(self.Config.HuntingEnabled))
    return self.Config.HuntingEnabled
end

function Evolink:ToggleEncounter()
    self.Config.EncounterEnabled = not self.Config.EncounterEnabled
    print("[Evolink] EncounterEnabled: " .. tostring(self.Config.EncounterEnabled))
    return self.Config.EncounterEnabled
end

function Evolink:ToggleFastBattle()
    return self:ToggleFastBattle()
end

function Evolink:SetHuntMode(mode)
    if mode ~= "Both" and mode ~= "ShinyOnly" and mode ~= "PrismaticOnly" and mode ~= "PrismaticShiny" then
        warn("[Evolink] Invalid hunt mode. Use: Both, ShinyOnly, PrismaticOnly, PrismaticShiny")
        return
    end
    self.Config.HuntMode = mode
    print("[Evolink] HuntMode set to: " .. mode)
end

function Evolink:SetEncounterTarget(targetList)
    if type(targetList) ~= "table" then
        if type(targetList) == "number" then targetList = {targetList}
        else warn("[Evolink] SetEncounterTarget requires a table of numbers or a single number") return end
    end
    self.Config.EncounterTarget = targetList
    self:BuildTargetChain()
    self.CurrentChainIndex = 1
    print("[Evolink] EncounterTarget set to: " .. table.concat(self.Config.EncounterTarget, ", "))
end

function Evolink:AddTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] AddTarget requires a number") return end
    local targets = self:GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group to add to") return end
    for _, id in ipairs(targets) do
        if id == configId then print("[Evolink] Target " .. configId .. " already in current group") return end
    end
    table.insert(targets, configId)
    print("[Evolink] Added target: " .. configId)
end

function Evolink:RemoveTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] RemoveTarget requires a number") return end
    local targets = self:GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group") return end
    for i, id in ipairs(targets) do
        if id == configId then
            table.remove(targets, i)
            print("[Evolink] Removed target: " .. configId)
            return
        end
    end
    print("[Evolink] Target not found: " .. configId)
end

function Evolink:ListTargets()
    print("[Evolink] Current target group (" .. self.CurrentChainIndex .. "): " .. table.concat(self:GetCurrentTargets() or {}, ", "))
    print("[Evolink] Chain groups:")
    for i, group in ipairs(self.TargetChain) do
        local marker = (i == self.CurrentChainIndex) and " <-- CURRENT" or ""
        print("  Group " .. i .. ": " .. table.concat(group, ", ") .. marker)
    end
    return self:GetCurrentTargets()
end

function Evolink:SetNextChainEnabled(enabled)
    self.Config.NextChainEnabled = enabled == true
    print("[Evolink] NextChainEnabled: " .. tostring(self.Config.NextChainEnabled))
end

function Evolink:SetLoopAfterChainEnd(enabled)
    self.Config.LoopAfterChainEnd = enabled == true
    print("[Evolink] LoopAfterChainEnd: " .. tostring(self.Config.LoopAfterChainEnd))
end

function Evolink:AdvanceTargetChain()
    local result = self:AdvanceChain()
    if result then print("[Evolink] Manually advanced to group " .. self.CurrentChainIndex)
    else print("[Evolink] Cannot advance chain further") end
    return result
end

function Evolink:ResetTargetChain()
    self.CurrentChainIndex = 1
    print("[Evolink] Chain reset to group 1: " .. table.concat(self:GetCurrentTargets() or {}, ", "))
end

function Evolink:SetChainTarget(groupNum, targetList)
    if type(groupNum) ~= "number" or groupNum < 1 or groupNum > 5 then
        warn("[Evolink] SetChainTarget requires groupNum 1-5")
        return
    end
    if type(targetList) ~= "table" then
        if type(targetList) == "number" then targetList = {targetList}
        else warn("[Evolink] SetChainTarget requires a table of numbers or a single number") return end
    end
    local key = "EncounterTarget"
    if groupNum > 1 then key = key .. groupNum end
    self.Config[key] = targetList
    self:BuildTargetChain()
    print("[Evolink] Set " .. key .. " to: " .. table.concat(targetList, ", "))
end

function Evolink:SetFallbackChain(chain)
    if type(chain) ~= "table" then warn("[Evolink] SetFallbackChain requires a table of ball names") return end
    self.Config.FallbackChain = chain
    print("[Evolink] FallbackChain set to: " .. table.concat(self.Config.FallbackChain, " -> "))
end

function Evolink:SetBallForScenario(scenario, ballName)
    local validScenarios = {
        NonShiny_NoPity = true, NonShiny_PityMax = true,
        Shiny_NoPity = true, Shiny_PityMax = true,
    }
    if not validScenarios[scenario] then
        warn("[Evolink] Invalid scenario. Use: NonShiny_NoPity, NonShiny_PityMax, Shiny_NoPity, Shiny_PityMax")
        return
    end
    if not BALLS[ballName] then
        warn("[Evolink] Invalid ball name. Use: SoftCatch, Common, Advanced, King, Prismatic")
        return
    end
    self.Config[scenario] = ballName
    print("[Evolink] " .. scenario .. " set to: " .. ballName)
end

function Evolink:SetFleeFromShiny(enabled)
    self.Config.FleeFromShiny = enabled == true
    print("[Evolink] FleeFromShiny: " .. tostring(self.Config.FleeFromShiny))
end

function Evolink:SetUseSoftCatch(enabled)
    self.Config.UseSoftCatch = enabled ~= false
    print("[Evolink] UseSoftCatch: " .. tostring(self.Config.UseSoftCatch))
end

function Evolink:SetFleeNonShinyAtPityMax(enabled)
    self.Config.FleeNonShinyAtPityMax = enabled ~= false
    print("[Evolink] FleeNonShinyAtPityMax: " .. tostring(self.Config.FleeNonShinyAtPityMax))
end

function Evolink:SetStopOnCatch(enabled)
    self.Config.StopOnCatch = enabled == true
    print("[Evolink] StopOnCatch: " .. tostring(self.Config.StopOnCatch))
end

function Evolink:SetEncounterCooldown(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        warn("[Evolink] SetEncounterCooldown requires a positive number")
        return
    end
    self.Config.EncounterCooldown = seconds
    print("[Evolink] EncounterCooldown set to: " .. seconds .. " seconds")
end

function Evolink:SetSkillSettings(newSettings)
    if type(newSettings) ~= "table" then warn("[Evolink] SetSkillSettings requires a table") return end
    for k, v in pairs(newSettings) do
        if k == "healThreshold" then self.Config.SkillHealThreshold = type(v) == "number" and v or self.Config.SkillHealThreshold
        elseif k == "preferKillOrder" then self.Config.SkillPreferKillOrder = v == true
        elseif k == "allowMultiTarget" then self.Config.SkillAllowMultiTarget = v == true
        elseif k == "debugMode" then self.Config.SkillDebugMode = v == true
        elseif k == "fastMode" then self.Config.SkillFastMode = v == true
        elseif k == "interval" then self.Config.SkillInterval = type(v) == "number" and v or self.Config.SkillInterval
        end
    end
    print("[Evolink] Skill settings updated")
end

function Evolink:GetSkillSettings()
    return {
        healThreshold = self.Config.SkillHealThreshold,
        preferKillOrder = self.Config.SkillPreferKillOrder,
        allowMultiTarget = self.Config.SkillAllowMultiTarget,
        debugMode = self.Config.SkillDebugMode,
        fastMode = self.Config.SkillFastMode,
        interval = self.Config.SkillInterval,
    }
end

function Evolink:GetSessionStats()
    return {
        encounters = self.SessionStats.encounters,
        catches = self.SessionStats.catches,
        goalCatches = self.SessionStats.goalCatches,
        flees = self.SessionStats.flees,
        shinyEncounters = self.SessionStats.shinyEncounters,
        shinyCaught = self.SessionStats.shinyCaught,
    }
end

function Evolink:ResetSessionStats()
    self.SessionStats = {encounters = 0, catches = 0, flees = 0, shinyEncounters = 0, shinyCaught = 0, goalCatches = 0}
    print("[Evolink] Session stats reset.")
end

function Evolink:GetStatus()
    return {
        running = self.Running,
        huntingEnabled = self.Config.HuntingEnabled,
        encounterEnabled = self.Config.EncounterEnabled,
        huntMode = self.Config.HuntMode,
        fastBattle = self.FastBattleState.enabled,
        autoBattle = self.AutoBattleState.enabled,
        currentChainIndex = self.CurrentChainIndex,
        currentTargets = self:GetCurrentTargets(),
        ballInventory = self:UpdateBallInventory(),
    }
end

function Evolink:PrintConfig()
    print("")
    print("=" .. string.rep("=", 62))
    print("  Evolink Auto Catch + Battle Module")
    print("=" .. string.rep("=", 62))
    print("  HuntingEnabled:       " .. tostring(self.Config.HuntingEnabled))
    print("  EncounterEnabled:     " .. tostring(self.Config.EncounterEnabled))
    print("  EncounterCooldown:    " .. tostring(self.Config.EncounterCooldown))
    print("  HuntMode:             " .. tostring(self.Config.HuntMode))
    print("  FleeFromShiny:        " .. tostring(self.Config.FleeFromShiny))
    print("  UseSoftCatch:         " .. tostring(self.Config.UseSoftCatch))
    print("  FleeNonShiny@Max:     " .. tostring(self.Config.FleeNonShinyAtPityMax))
    print("  FastBattle:           " .. tostring(self.Config.FastBattle))
    print("  StopOnCatch:          " .. tostring(self.Config.StopOnCatch))
    print("  NextChain:            " .. tostring(self.Config.NextChainEnabled))
    print("  LoopAfterChain:       " .. tostring(self.Config.LoopAfterChainEnd))
    print("")
    print("  SkillHealThreshold:   " .. tostring(self.Config.SkillHealThreshold))
    print("  SkillPreferKillOrder: " .. tostring(self.Config.SkillPreferKillOrder))
    print("  SkillAllowMultiTarget:" .. tostring(self.Config.SkillAllowMultiTarget))
    print("  SkillDebugMode:       " .. tostring(self.Config.SkillDebugMode))
    print("  SkillFastMode:        " .. tostring(self.Config.SkillFastMode))
    print("  SkillInterval:        " .. tostring(self.Config.SkillInterval))
    print("")
    print("  Target Chain:")
    for i, group in ipairs(self.TargetChain) do
        print("    Group " .. i .. ": " .. table.concat(group, ", "))
    end
    print("")
    print("  Ball Inventory:")
    for _, ballName in ipairs(self.Config.FallbackChain) do
        local count = self.BallInventory[ballName] or 0
        if count == math.huge then print("    " .. ballName .. ": UNLIMITED")
        else print("    " .. ballName .. ": " .. count) end
    end
    print("    SoftCatch: UNLIMITED")
    print("")
    print("  Fallback Chain: " .. table.concat(self.Config.FallbackChain, " -> "))
    print("  Scenario Balls:")
    print("    NonShiny + NoPity:    " .. tostring(self.Config.NonShiny_NoPity))
    print("    NonShiny + PityMax:   " .. tostring(self.Config.NonShiny_PityMax))
    print("    Shiny + NoPity:       " .. tostring(self.Config.Shiny_NoPity))
    print("    Shiny + PityMax:      " .. tostring(self.Config.Shiny_PityMax))
    print("")
end

function Evolink:ExecuteBestSkills()
    return self:executeBestSkillsForAllPets()
end

function Evolink:StartAutoBattle()
    return self:startAutoBattle()
end

function Evolink:StopAutoBattle()
    return self:stopAutoBattle()
end

function Evolink:ApplyFastBattle()
    return self:ApplyFastBattle()
end

function Evolink:RemoveFastBattle()
    return self:RemoveFastBattle()
end

return Evolink
