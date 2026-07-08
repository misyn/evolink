local Evolink = {}
Evolink.__index = Evolink

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BattleRemote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")
local ReqEnterPetBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqEnterPetBattle")
local ReqOperateBattle = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Battle"):WaitForChild("ReqOperateBattle")

local BattleCatchPetWindowController = nil
local BagService = nil
local PetConfig = nil
local ShinyPetLotteryStorage = nil
local ShinyPetLotteryService = nil
local ErrorCode = nil
local BattleDataGetModule = nil
local ElementModule = nil
local ElementConst = nil
local ConfigDataManager = nil
local ConfigConst = nil

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

local SKILL_TARGET = {
    SINGLE = 1, SELF = 2, ALL = 3, RANDOM = 4,
    ADJACENT = 5, TEAM = 6, ENEMY_TEAM = 7,
}

local EFFECTIVENESS_MULTIPLIER = {}
local EFFECTIVENESS_NAMES = {}
local EFFECTIVENESS_PRIORITY = {}

local VALID_RESPONSES = {[0] = true, [20000] = true}

local MOVE_DISABLED_CODES = {}
for i = 20001, 20030 do
    MOVE_DISABLED_CODES[i] = true
end

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

    self.TargetChain = {}
    self.CurrentChainIndex = 1
    self.BallInventory = {}
    self.PityCache = {
        prismaticCurrent = nil, prismaticMax = nil,
        shinyCurrent = nil, shinyMax = nil,
        lastUpdated = 0,
    }

    self.Running = true
    self.LastAction = nil
    self.LastActionTime = 0
    self.PendingLog = nil
    self.WasInCatchWindow = false
    self.LastEncounterAttempt = 0

    self.SessionStats = {
        encounters = 0, catches = 0, flees = 0,
        shinyEncounters = 0, shinyCaught = 0, goalCatches = 0,
    }

    self.FastBattleState = {
        enabled = false, originalGetSpeed = nil,
        originalIsEnabled = nil, hooked = false
    }

    self.autoBattleEnabled = false
    self.autoBattleThread = nil
    self.mainLoopThread = nil

    self:_LoadModules()
    self:_BuildTargetChain()
    self:_UpdateBallInventory()

    return self
end

function Evolink:_LoadModules()
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
    end)
    pcall(function()
        BattleDataGetModule = require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("MainBattleWindow"):WaitForChild("BattleDataGetModule"))
    end)
    pcall(function()
        ElementModule = require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("Element"):WaitForChild("ElementModule"))
    end)
    pcall(function()
        ElementConst = require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("Element"):WaitForChild("Basic"):WaitForChild("ElementConst"))
    end)
    pcall(function()
        ConfigDataManager = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Config"):WaitForChild("ConfigDataManager"))
    end)
    pcall(function()
        ConfigConst = require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Config"):WaitForChild("ConfigConst"))
    end)

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
end

function Evolink:_BuildTargetChain()
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

function Evolink:_GetCurrentTargets()
    if self.CurrentChainIndex <= #self.TargetChain then
        return self.TargetChain[self.CurrentChainIndex]
    end
    if self.Config.LoopAfterChainEnd and #self.TargetChain > 0 then
        self.CurrentChainIndex = 1
        return self.TargetChain[1]
    end
    return nil
end

function Evolink:_AdvanceChain()
    if not self.Config.NextChainEnabled then return false end
    self.CurrentChainIndex = self.CurrentChainIndex + 1
    if self.CurrentChainIndex > #self.TargetChain then
        if self.Config.LoopAfterChainEnd then
            self.CurrentChainIndex = 1
            print("[Evolink] Chain complete. Looping back to target group 1.")
            return true
        else
            print("[Evolink] Chain complete. No more targets. Stopping.")
            return false
        end
    end
    print("[Evolink] Advanced to target group " .. self.CurrentChainIndex .. ": " .. table.concat(self:_GetCurrentTargets() or {}, ", "))
    return true
end

function Evolink:_UpdateBallInventory()
    self.BallInventory = {}
    for name, itemId in pairs(BALLS) do
        if UNLIMITED_BALLS[name] then
            self.BallInventory[name] = math.huge
        else
            local count = 0
            pcall(function()
                if BagService and BagService.getItemNumById then
                    count = BagService.getItemNumById(itemId)
                end
            end)
            self.BallInventory[name] = (typeof(count) == "number" and count > 0) and count or 0
        end
    end
    return self.BallInventory
end

function Evolink:_HasBall(ballName)
    return (self.BallInventory[ballName] or 0) > 0
end

function Evolink:_GetAvailableBall(preferredBallName)
    local startIndex = 1
    for i, name in ipairs(self.Config.FallbackChain) do
        if name == preferredBallName then startIndex = i; break end
    end
    for i = startIndex, #self.Config.FallbackChain do
        local ballName = self.Config.FallbackChain[i]
        if self:_HasBall(ballName) then return ballName, BALLS[ballName] end
    end
    return nil, nil
end

function Evolink:_IsInBattle()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("MainBattleWindow")
    return window and window.Enabled == true
end

function Evolink:_IsCatchWindowActive()
    local window = PlayerGui:FindFirstChild("UIPrefabs") and PlayerGui.UIPrefabs:FindFirstChild("BattleCatchPetWindow")
    return window and window.Enabled == true
end

function Evolink:_UpdatePityCacheFromUI()
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

function Evolink:_GetDisplayPityStrings(actionType)
    local prisCurrent, prisMax = self.PityCache.prismaticCurrent, self.PityCache.prismaticMax
    local shinyCurrent, shinyMax = self.PityCache.shinyCurrent, self.PityCache.shinyMax

    if shinyCurrent and shinyMax then shinyCurrent = shinyCurrent + 1 end
    if actionType == "catch" and prisCurrent and prisMax then prisCurrent = prisCurrent + 1 end

    local prisStr = (prisCurrent and prisMax) and (prisCurrent .. "/" .. prisMax) or "??/??"
    local shinyStr = (shinyCurrent and shinyMax) and (shinyCurrent .. "/" .. shinyMax) or "??/??"
    return prisStr, shinyStr
end

function Evolink:_ClearPityCache()
    self.PityCache.prismaticCurrent = nil; self.PityCache.prismaticMax = nil
    self.PityCache.shinyCurrent = nil; self.PityCache.shinyMax = nil
    self.PityCache.lastUpdated = 0
end

function Evolink:_GetTargetPetId()
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

function Evolink:_GetPrismaticPityFromModule()
    local petId = self:_GetTargetPetId()
    if not petId then return nil, nil end
    local SUCCEEDED = ErrorCode and ErrorCode.SUCCEEDED or 0
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

function Evolink:_GetShinyPityFromModule()
    local petId = self:_GetTargetPetId()
    if not petId then return nil, nil end
    local SUCCEEDED = ErrorCode and ErrorCode.SUCCEEDED or 0
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

function Evolink:_GetPrismaticPity()
    local current, max = self:_GetPrismaticPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if self.PityCache.prismaticCurrent and self.PityCache.prismaticMax then
        return self.PityCache.prismaticCurrent, self.PityCache.prismaticMax
    end
    return nil, nil
end

function Evolink:_GetShinyPity()
    local current, max = self:_GetShinyPityFromModule()
    if current ~= nil and max ~= nil then return current, max end
    if self.PityCache.shinyCurrent and self.PityCache.shinyMax then
        return self.PityCache.shinyCurrent, self.PityCache.shinyMax
    end
    return nil, nil
end

function Evolink:_IsPityMaxed()
    local current, max = self:_GetPrismaticPity()
    if type(current) ~= "number" or type(max) ~= "number" then return nil end
    return current >= (max - 1)
end

function Evolink:_IsCurrentTargetShiny()
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

function Evolink:_IsCurrentTargetColorful()
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

function Evolink:_GetPetNameFromConfig(petId)
    if not PetConfig or not petId then return nil end
    local petData = PetConfig[petId]
    if petData and typeof(petData) == "table" and petData.name then
        return tostring(petData.name)
    end
    return nil
end

function Evolink:_GetTargetModel()
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
                local configName = self:_GetPetNameFromConfig(petId)
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

function Evolink:_BuildTargetLabel()
    local model = self:_GetTargetModel()
    local shiny = self:_IsCurrentTargetShiny()
    local colorful = self:_IsCurrentTargetColorful()
    local tags = {}
    if shiny == true then table.insert(tags, "Shiny")
    elseif shiny == false then table.insert(tags, "Unshiny")
    else table.insert(tags, "?Shiny") end
    if colorful == true then table.insert(tags, "Prismatic")
    elseif colorful == false then table.insert(tags, "Unprismatic")
    else table.insert(tags, "?Prismatic") end
    return tostring(model) .. " (" .. table.concat(tags, "/") .. ")"
end

function Evolink:_LeaveBattle()
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{ actionType = 8 }}))
    end)
    return success
end

function Evolink:_PerformCatch(itemId)
    local success = pcall(function()
        BattleRemote:InvokeServer(unpack({{
            sourcePos = 1, targetPos = 1,
            actionType = 5, itemId = itemId
        }}))
    end)
    return success
end

function Evolink:_DoCatch(preferredBall)
    local ballName, ballId = self:_GetAvailableBall(preferredBall)
    if not ballId then
        if self.Config.UseSoftCatch then
            return "catch", BALLS.SoftCatch, "SoftCatch", false
        end
        return "wait", nil, nil, false
    end
    return "catch", ballId, ballName, true
end

function Evolink:_DecideAction()
    if not self:_IsCatchWindowActive() then return "wait", nil, nil, false end
    self:_UpdateBallInventory()
    local shiny = self:_IsCurrentTargetShiny()
    local pityMaxed = self:_IsPityMaxed()
    local mode = self.Config.HuntMode
    if pityMaxed == nil then return "wait", nil, nil, false end
    if shiny == nil then shiny = false end

    if mode == "PrismaticShiny" then
        if shiny == true and pityMaxed == true then return self:_DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:_DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "ShinyOnly" then
        if shiny == true and pityMaxed == true then return self:_DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:_DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return "flee", nil, nil, false end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:_DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "PrismaticOnly" then
        if shiny == true and pityMaxed == true then return self:_DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:_DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then return self:_DoCatch(self.Config.NonShiny_PityMax) end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:_DoCatch(self.Config.NonShiny_NoPity)
        end
    end

    if mode == "Both" then
        if shiny == true and pityMaxed == true then return self:_DoCatch(self.Config.Shiny_PityMax) end
        if shiny == true and pityMaxed == false then
            if self.Config.FleeFromShiny then return "flee", nil, nil, false end
            return self:_DoCatch(self.Config.Shiny_NoPity)
        end
        if shiny == false and pityMaxed == true then
            if self.Config.FleeNonShinyAtPityMax then return "flee", nil, nil, false end
            return self:_DoCatch(self.Config.NonShiny_PityMax)
        end
        if shiny == false and pityMaxed == false then
            if self.Config.UseSoftCatch then return "catch", BALLS.SoftCatch, "SoftCatch", false end
            return self:_DoCatch(self.Config.NonShiny_NoPity)
        end
    end
    return "wait", nil, nil, false
end

function Evolink:_GetCreatureModelCache()
    local ok, cache = pcall(function()
        return Workspace:WaitForChild("RuntimeCache"):WaitForChild("RuntimeCacheServer"):WaitForChild("CreatureModelCache")
    end)
    if ok then return cache end
    return nil
end

function Evolink:_FindTargetCreatures()
    local cache = self:_GetCreatureModelCache()
    if not cache then return {} end
    local targets = self:_GetCurrentTargets()
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

function Evolink:_FireEncounter(creatureId)
    if not creatureId then return false end
    local ok = pcall(function() ReqEnterPetBattle:FireServer(creatureId) end)
    return ok
end

function Evolink:_GetControllerManager()
    local core = ReplicatedStorage:FindFirstChild("Core")
    if not core then return nil end
    local controller = core:FindFirstChild("Controller")
    if not controller then return nil end
    local cm = controller:FindFirstChild("ControllerManager")
    if not cm then return nil end
    return require(cm)
end

function Evolink:_GetMainBattleController()
    local cm = self:_GetControllerManager()
    if not cm then return nil end
    return cm.getController("MainBattleWindowController")
end

function Evolink:_ApplyFastBattle()
    local controller = self:_GetMainBattleController()
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
    print("[Evolink] FastBattle Started")
    return true
end

function Evolink:_RemoveFastBattle()
    if not self.FastBattleState.hooked then return end
    local controller = self:_GetMainBattleController()
    if controller then
        if self.FastBattleState.originalGetSpeed then controller.getBattlePlaybackSpeed = self.FastBattleState.originalGetSpeed end
        if self.FastBattleState.originalIsEnabled then controller.isBattleSpeedEnabled = self.FastBattleState.originalIsEnabled end
    end
    self.FastBattleState.hooked = false
    self.FastBattleState.enabled = false
    print("[Evolink] FastBattle Ended")
end

function Evolink:_ToggleFastBattleInternal()
    if self.FastBattleState.enabled then self:_RemoveFastBattle() else self:_ApplyFastBattle() end
    return self.FastBattleState.enabled
end

function Evolink:_GetCurrentBattleData()
    local ok, BattleService = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("Battle"):WaitForChild("BattleService"))
    end)
    if ok and BattleService then
        local battle = BattleService.getCurrentBattle()
        if battle and typeof(battle) == "table" then return battle end
    end
    local ok2, ControllerManager = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Core"):WaitForChild("Controller"):WaitForChild("ControllerManager"))
    end)
    if ok2 and ControllerManager then
        local mainController = ControllerManager.getController("MainBattleWindowController")
        if mainController and mainController.getBattleDataCache then
            return mainController.getBattleDataCache()
        end
    end
    return nil
end

function Evolink:_GetAllLocalPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.selfPets then return {} end
    return activePets.selfPets
end

function Evolink:_GetAllEnemyPets(battleData)
    if not battleData or typeof(battleData) ~= "table" then return {} end
    local activePets = BattleDataGetModule.getActivePetsData(battleData)
    if not activePets or not activePets.enemyPets then return {} end
    return activePets.enemyPets
end

function Evolink:_GetKillOrderTargets(battleData)
    local ok, BattleService = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Script"):WaitForChild("Battle"):WaitForChild("BattleService"))
    end)
    if not ok or not BattleService then return nil end
    local success, result = pcall(function() return BattleService.getSequenceKillOrder(battleData) end)
    if success and typeof(result) == "table" and #result > 0 then return result end
    return nil
end

function Evolink:_GetOrderedTarget(battleData)
    local killOrder = self:_GetKillOrderTargets(battleData)
    if not killOrder then return nil end
    for _, targetInfo in ipairs(killOrder) do
        if typeof(targetInfo) == "table" and typeof(targetInfo.uid) == "string" then
            if targetInfo.aliveState == 1 then
                local allEnemies = self:_GetAllEnemyPets(battleData)
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

function Evolink:_GetPrimaryTarget(battleData)
    if self.Config.SkillPreferKillOrder then
        local orderedTarget = self:_GetOrderedTarget(battleData)
        if orderedTarget then return orderedTarget end
    end
    local allEnemies = self:_GetAllEnemyPets(battleData)
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            return enemy
        end
    end
    return allEnemies[1]
end

function Evolink:_GetPetElementIdList(configId)
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

function Evolink:_CalculateSkillEffectiveness(skillConfig, targetElementIdList)
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

function Evolink:_CalculateAoeEffectiveness(skillConfig, battleData)
    if typeof(skillConfig) ~= "table" then return nil, 0, 0 end
    local allEnemies = self:_GetAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, 0, 0 end
    local totalEstPower, totalMultiplier, bestEffect, bestPriority, aliveCount = 0, 0, ElementConst.ElementEffect.NORMAL, 1, 0
    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            aliveCount = aliveCount + 1
            local elements = self:_GetPetElementIdList(enemy.configId)
            local effect, mult, estPower = self:_CalculateSkillEffectiveness(skillConfig, elements)
            totalEstPower = totalEstPower + estPower
            totalMultiplier = totalMultiplier + mult
            local priority = EFFECTIVENESS_MULTIPLIER[effect] or 1
            if priority > bestPriority then bestPriority = priority; bestEffect = effect end
        end
    end
    if aliveCount == 0 then return nil, 0, 0 end
    return bestEffect, totalMultiplier / aliveCount, math.floor(totalEstPower / aliveCount)
end

function Evolink:_FindBestTargetForSkill(battleData, skillConfig)
    if typeof(skillConfig) ~= "table" then return nil, nil, nil, nil, 0, 0 end
    local allEnemies = self:_GetAllEnemyPets(battleData)
    if #allEnemies == 0 then return nil, nil, nil, nil, 0, 0 end
    local bestEnemy, bestScore, bestPos, bestCampId, bestEffect, bestMultiplier, bestEstPower = nil, -99999, nil, nil, ElementConst.ElementEffect.NORMAL, 1.0, 0
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil, nil, nil, 0, 0 end
    local enemyCamp = nil
    if battleData.camp1 and battleData.camp1.campId == enemyCampId then enemyCamp = battleData.camp1
    elseif battleData.camp2 and battleData.camp2.campId == enemyCampId then enemyCamp = battleData.camp2 end

    for _, enemy in ipairs(allEnemies) do
        if typeof(enemy) == "table" and BattleDataGetModule.isAliveBattlePet(enemy) then
            local elements = self:_GetPetElementIdList(enemy.configId)
            local effect, multiplier, estPower = self:_CalculateSkillEffectiveness(skillConfig, elements)
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

function Evolink:_NeedsHealing(pet)
    if typeof(pet) ~= "table" then return false end
    local currHp, maxHp = pet.currHp or 0, pet.maxHp or 1
    if maxHp <= 0 then return false end
    return (currHp / maxHp) < self.Config.SkillHealThreshold
end

function Evolink:_ScoreSkill(skillData, battleData, currentEnergy)
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
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = self:_FindBestTargetForSkill(battleData, skillConfig)
        local _, _, aoeAvgPower = self:_CalculateAoeEffectiveness(skillConfig, battleData)
        targetCount = #self:_GetAllEnemyPets(battleData)
        estimatedPower = aoeAvgPower
    elseif targetType == SKILL_TARGET.SELF or targetType == SKILL_TARGET.TEAM then
        return -100, nil, 0, true, false, 0, nil, nil, nil
    else
        bestTargetEnemy, bestTargetPos, bestTargetCampId, effect, multiplier, estimatedPower = self:_FindBestTargetForSkill(battleData, skillConfig)
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

function Evolink:_GetAllScoredSkillsForPet(battleData, pet)
    if not pet then return {} end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return {} end
    local trainer = BattleDataGetModule.getLocalPlayerTrainer(battleData)
    local currentEnergy = (trainer and typeof(trainer.energy) == "number") and trainer.energy or 0
    local scoredSkills = {}

    for i = 1, 4 do
        local skillData = skills[i]
        local score, effect, estPower, canUse, isHeal, targetCount, bestEnemy, bestPos, bestCampId = self:_ScoreSkill(skillData, battleData, currentEnergy)
        if isHeal and self:_NeedsHealing(pet) then score = 10000 end
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

function Evolink:_GetSourcePosForPet(battleData, pet)
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

function Evolink:_GetTargetInfo(battleData, skillConfig, precomputedTarget)
    if not battleData then return nil, nil end
    local enemyCampId = BattleDataGetModule.getEnemyCampId(battleData)
    if not enemyCampId then return nil, nil end
    if precomputedTarget and precomputedTarget.bestPos and precomputedTarget.bestCampId then
        return precomputedTarget.bestCampId, precomputedTarget.bestPos
    end
    local targetType = skillConfig and skillConfig.targetType or 1

    if targetType == SKILL_TARGET.ALL or targetType == SKILL_TARGET.ENEMY_TEAM then
        if self.Config.SkillPreferKillOrder then
            local orderedTarget = self:_GetOrderedTarget(battleData)
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
        local _, bestPos, bestCampId = self:_FindBestTargetForSkill(battleData, skillConfig)
        if bestPos then return bestCampId or enemyCampId, bestPos end
        return enemyCampId, 1
    end

    if self.Config.SkillPreferKillOrder then
        local orderedTarget = self:_GetOrderedTarget(battleData)
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

function Evolink:_GetSkillIdFromPet(pet, index)
    if not pet then return nil end
    local skills = pet.skills
    if typeof(skills) ~= "table" then return nil end
    local skillData = skills[index]
    if typeof(skillData) ~= "table" then return nil end
    return skillData.id
end

function Evolink:_ExecuteSkillForPet(battleData, pet, skillIndex, precomputedTarget)
    if not pet or not skillIndex then return false, nil end
    local skillId = self:_GetSkillIdFromPet(pet, skillIndex)
    if not skillId then
        if self.Config.SkillDebugMode then warn("Could not get skill ID for pet") end
        return false, nil
    end
    local skillConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.SKILL, skillId)
    local targetCampId, targetPos = self:_GetTargetInfo(battleData, skillConfig, precomputedTarget)
    if not targetCampId or not targetPos then
        if self.Config.SkillDebugMode then warn("No valid target found") end
        return false, nil
    end
    local sourcePos = self:_GetSourcePosForPet(battleData, pet)
    local args = {{
        skillType = skillConfig and skillConfig.skillType or 1,
        targetPos = targetPos, sourcePos = sourcePos,
        actionType = 1, targetCampId = targetCampId, skillId = skillId
    }}
    local skillName = skillConfig and skillConfig.name or "Unknown"
    local targetTypeName = skillConfig and skillConfig.targetType or 1
    local isAoe = (targetTypeName == SKILL_TARGET.ALL or targetTypeName == SKILL_TARGET.ENEMY_TEAM)

    if self.Config.SkillDebugMode then
        print(string.format("[Auto-Skill] Pet %d (%s) uses %s (ID: %d) | Target: Camp %d Pos %d | AOE: %s",
            sourcePos, pet.name or "Pet", skillName, skillId, targetCampId, targetPos, tostring(isAoe)))
    end

    local success, result = pcall(function() return ReqOperateBattle:InvokeServer(unpack(args)) end)
    if success then
        if VALID_RESPONSES[result] == true then return true, result
        else return false, result end
    else
        if self.Config.SkillDebugMode then warn("[Auto-Skill] Invoke failed:", result) end
        return false, nil
    end
end

function Evolink:_ExecuteBestSkillsForAllPets()
    local battleData = self:_GetCurrentBattleData()
    if not battleData then
        if self.Config.SkillDebugMode then warn("No active battle found") end
        return false
    end
    local allPets = self:_GetAllLocalPets(battleData)
    if #allPets == 0 then
        if self.Config.SkillDebugMode then warn("No pets found") end
        return false
    end

    if self.Config.SkillDebugMode then print("
=== Evaluating ALL Pets ===") end
    local allMoves = {}

    for petIndex, pet in ipairs(allPets) do
        if typeof(pet) == "table" and BattleDataGetModule.isAliveBattlePet(pet) then
            local scoredSkills = self:_GetAllScoredSkillsForPet(battleData, pet)
            local petName = "Unknown"
            if pet.configId then
                local petConfig = ConfigDataManager.getConfig(ConfigConst.ConfigName.PET, pet.configId)
                petName = petConfig and petConfig.name or "Unknown"
            end
            local sourcePos = self:_GetSourcePosForPet(battleData, pet)
            if #scoredSkills > 0 then
                table.insert(allMoves, {
                    pet = pet, scoredSkills = scoredSkills, currentSkillIndex = 1,
                    sourcePos = sourcePos, petName = petName, bestScore = scoredSkills[1].score
                })
                if self.Config.SkillDebugMode then
                    print(string.format("  Pet [%d] %s (Pos: %d) | Best: Skill %d | Score: %d | Effect: %s | Target: Pos %d",
                        petIndex, petName, sourcePos, scoredSkills[1].index, scoredSkills[1].score,
                        scoredSkills[1].effect and EFFECTIVENESS_NAMES[scoredSkills[1].effect] or "nil",
                        scoredSkills[1].bestPos or 1))
                end
            end
        end
    end

    if self.Config.SkillDebugMode then print("===========================
") end
    if #allMoves == 0 then
        if self.Config.SkillDebugMode then warn("No valid moves for any pet") end
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
            if self.Config.SkillDebugMode then
                print(string.format("[Auto-Skill] Pet %d (%s) | Fallback [%d/%d] | Skill %d | Score: %d | Effect: %s",
                    move.sourcePos, move.petName, i, #scoredSkills, sk.index, sk.score,
                    sk.effect and EFFECTIVENESS_NAMES[sk.effect] or "nil"))
            end
            success, resultCode = self:_ExecuteSkillForPet(battleData, pet, sk.index, sk)
            if success then
                anySuccess = true
                if not self.Config.SkillFastMode then task.wait(0.2) end
                break
            else
                if resultCode == 27811 then break end
                if resultCode and MOVE_DISABLED_CODES[resultCode] then
                    if self.Config.SkillDebugMode then print(string.format("[Auto-Skill] Move disabled (code: %d), trying next fallback...", resultCode)) end
                else
                    if self.Config.SkillDebugMode then print(string.format("[Auto-Skill] Move failed (code: %s), stopping fallback chain.", tostring(resultCode))) end
                    break
                end
            end
        end

        if not success and skillTried >= #scoredSkills then
            if self.Config.SkillDebugMode then
                print(string.format("[Auto-Skill] All %d moves failed for Pet %d (%s)", #scoredSkills, move.sourcePos, move.petName))
            end
        end
        battleData = self:_GetCurrentBattleData()
        if not battleData then break end
    end
    return anySuccess
end

function Evolink:_StartAutoBattle(interval)
    interval = interval or self.Config.SkillInterval
    self.autoBattleEnabled = true
    if self.Config.SkillDebugMode then
        print("[Auto-Skill] Auto-battle started")
        print("[Auto-Skill] Interval:", interval)
        print("[Auto-Skill] FastMode:", self.Config.SkillFastMode)
        print("[Auto-Skill] Debug:", self.Config.SkillDebugMode)
    end
    if self.autoBattleThread then self.autoBattleThread = nil end
    self.autoBattleThread = task.spawn(function()
        while self.autoBattleEnabled do
            local battleData = self:_GetCurrentBattleData()
            if battleData then
                local success = self:_ExecuteBestSkillsForAllPets()
                if success then task.wait(interval) else task.wait(0.2) end
            else
                task.wait(1)
            end
        end
        if self.Config.SkillDebugMode then print("[Auto-Skill] Auto-battle loop ended") end
    end)
    return self.autoBattleThread
end

function Evolink:_StopAutoBattle()
    self.autoBattleEnabled = false
    self.autoBattleThread = nil
    if self.Config.SkillDebugMode then print("[Auto-Skill] Auto-battle stopped") end
end

function Evolink:_MainLoop()
    while self.Running do
        task.wait(0.3)

        if not self.Config.HuntingEnabled and not self.Config.EncounterEnabled then
            if self.FastBattleState.enabled then self:_RemoveFastBattle() end
            continue
        end

        if self:_IsInBattle() then
            if not self.Config.HuntingEnabled then
                if self.FastBattleState.enabled then self:_RemoveFastBattle() end
                continue
            end

            if self.Config.FastBattle and not self.FastBattleState.enabled then
                self:_ApplyFastBattle()
            end

            if not self.autoBattleEnabled then
                self:_StartAutoBattle()
            end

            local catchActive = self:_IsCatchWindowActive()
            if catchActive and not self.WasInCatchWindow then
                self.WasInCatchWindow = true
                self:_UpdatePityCacheFromUI()
                self.SessionStats.encounters = self.SessionStats.encounters + 1
            end
            if catchActive then self:_UpdatePityCacheFromUI() end

            if not catchActive then
                if self.PendingLog then print(self.PendingLog); self.PendingLog = nil end
                self.LastAction = nil
                continue
            end

            if self.LastAction and (tick() - self.LastActionTime) < 1.5 then continue end

            local targetLabel = self:_BuildTargetLabel()
            local shiny = self:_IsCurrentTargetShiny()
            local action, param, methodName, isGoalCatch = self:_DecideAction()
            local method = methodName or BALL_NAMES[param] or (action == "flee" and "FLEE" or "WAIT")

            if action == "catch" and param then
                self:_PerformCatch(param)
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
                    self:_RemoveFastBattle()
                    self:_StopAutoBattle()
                    return
                end

                if self.Config.NextChainEnabled then
                    local shouldContinue = self:_AdvanceChain()
                    if not shouldContinue then
                        print("[Evolink] Chain ended. Stopping farm.")
                        print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
                            self.SessionStats.encounters, self.SessionStats.catches, self.SessionStats.goalCatches, self.SessionStats.flees, self.SessionStats.shinyCaught))
                        self.Running = false
                        self:_RemoveFastBattle()
                        self:_StopAutoBattle()
                        return
                    end
                end

                self.LastAction = action
                self.LastActionTime = tick()
                task.wait(1.2)
                local prisStr, shinyStr = self:_GetDisplayPityStrings("catch")
                local goalTag = isGoalCatch and " [GOAL]" or " [PITY]"
                self.PendingLog = string.format("[Evolink] CATCH%s | Target: %s | Method: %s | PrisPity: %s | ShinyPity: %s",
                    goalTag, targetLabel, method, prisStr, shinyStr)
                task.wait(0.5)

            elseif action == "flee" then
                self:_LeaveBattle()
                self.SessionStats.flees = self.SessionStats.flees + 1
                self.LastAction = action
                self.LastActionTime = tick()
                local prisStr, shinyStr = self:_GetDisplayPityStrings("flee")
                self.PendingLog = string.format("[Evolink] FLEE | Target: %s | Method: FLEE | PrisPity: %s | ShinyPity: %s",
                    targetLabel, prisStr, shinyStr)
                task.wait(2.5)

            elseif action == "wait" then
                task.wait(0.5)
            end

        else
            self.WasInCatchWindow = false
            self:_ClearPityCache()
            if self.PendingLog then print(self.PendingLog); self.PendingLog = nil end
            if self.Config.FastBattle and self.FastBattleState.enabled then self:_RemoveFastBattle() end
            if self.autoBattleEnabled then self:_StopAutoBattle() end

            if not self.Config.EncounterEnabled then continue end

            if (tick() - self.LastEncounterAttempt) >= self.Config.EncounterCooldown then
                self.LastEncounterAttempt = tick()
                local foundCreatures = self:_FindTargetCreatures()
                if #foundCreatures > 0 then
                    for _, creatureId in ipairs(foundCreatures) do
                        self:_FireEncounter(creatureId)
                        print("[Evolink] Encounter fired with creature ID:", creatureId)
                        break
                    end
                else
                    if self.SessionStats.encounters == 0 and (tick() - self.LastEncounterAttempt) < 2 then
                        warn("[Evolink] No creatures found for target IDs:", table.concat(self:_GetCurrentTargets() or {}, ", "))
                    end
                end
            end
        end
    end
end

function Evolink:SetConfig(key, value)
    if self.Config[key] == nil then
        warn("[Evolink] Unknown config key:", key)
        return
    end
    self.Config[key] = value
    if key:find("EncounterTarget") then
        self:_BuildTargetChain()
        self.CurrentChainIndex = 1
    end
    print("[Evolink] Config[" .. key .. "] = " .. tostring(value))
end

function Evolink:GetConfig(key)
    return self.Config[key]
end

function Evolink:ToggleHunting()
    self.Config.HuntingEnabled = not self.Config.HuntingEnabled
    print("[Evolink] HuntingEnabled:", self.Config.HuntingEnabled and "ENABLED" or "DISABLED")
    return self.Config.HuntingEnabled
end

function Evolink:ToggleEncounter()
    self.Config.EncounterEnabled = not self.Config.EncounterEnabled
    print("[Evolink] EncounterEnabled:", self.Config.EncounterEnabled and "ENABLED" or "DISABLED")
    return self.Config.EncounterEnabled
end

function Evolink:ToggleFastBattle()
    self.Config.FastBattle = not self.Config.FastBattle
    if not self.Config.FastBattle and self.FastBattleState.enabled then
        self:_RemoveFastBattle()
    end
    print("[Evolink] FastBattle:", self.Config.FastBattle and "ENABLED" or "DISABLED")
    return self.Config.FastBattle
end

function Evolink:SetHuntMode(mode)
    if mode ~= "Both" and mode ~= "ShinyOnly" and mode ~= "PrismaticOnly" and mode ~= "PrismaticShiny" then
        warn("[Evolink] Invalid hunt mode. Use: Both, ShinyOnly, PrismaticOnly, PrismaticShiny")
        return
    end
    self.Config.HuntMode = mode
    print("[Evolink] HuntMode set to:", mode)
end

function Evolink:SetEncounterTarget(targetList)
    if type(targetList) ~= "table" then
        if type(targetList) == "number" then targetList = {targetList}
        else warn("[Evolink] SetEncounterTarget requires a table of numbers or a single number") return end
    end
    self.Config.EncounterTarget = targetList
    self:_BuildTargetChain()
    self.CurrentChainIndex = 1
    print("[Evolink] EncounterTarget set to:", table.concat(self.Config.EncounterTarget, ", "))
end

function Evolink:AddTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] AddTarget requires a number") return end
    local targets = self:_GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group to add to") return end
    for _, id in ipairs(targets) do
        if id == configId then print("[Evolink] Target " .. configId .. " already in current group") return end
    end
    table.insert(targets, configId)
    print("[Evolink] Added target:", configId)
    print("[Evolink] Current targets:", table.concat(self:_GetCurrentTargets() or {}, ", "))
end

function Evolink:RemoveTarget(configId)
    if type(configId) ~= "number" then warn("[Evolink] RemoveTarget requires a number") return end
    local targets = self:_GetCurrentTargets()
    if not targets then warn("[Evolink] No active target group") return end
    for i, id in ipairs(targets) do
        if id == configId then
            table.remove(targets, i)
            print("[Evolink] Removed target:", configId)
            print("[Evolink] Current targets:", table.concat(self:_GetCurrentTargets() or {}, ", "))
            return
        end
    end
    print("[Evolink] Target not found:", configId)
end

function Evolink:ListTargets()
    print("[Evolink] Current target group (" .. self.CurrentChainIndex .. "):", table.concat(self:_GetCurrentTargets() or {}, ", "))
    print("[Evolink] Chain groups:")
    for i, group in ipairs(self.TargetChain) do
        local marker = (i == self.CurrentChainIndex) and " <-- CURRENT" or ""
        print("  Group " .. i .. ": " .. table.concat(group, ", ") .. marker)
    end
    return self:_GetCurrentTargets()
end

function Evolink:SetNextChainEnabled(enabled)
    self.Config.NextChainEnabled = enabled == true
    print("[Evolink] NextChainEnabled:", self.Config.NextChainEnabled and "ENABLED" or "DISABLED")
end

function Evolink:SetLoopAfterChainEnd(enabled)
    self.Config.LoopAfterChainEnd = enabled == true
    print("[Evolink] LoopAfterChainEnd:", self.Config.LoopAfterChainEnd and "ENABLED" or "DISABLED")
end

function Evolink:AdvanceTargetChain()
    local result = self:_AdvanceChain()
    if result then print("[Evolink] Manually advanced to group " .. self.CurrentChainIndex)
    else print("[Evolink] Cannot advance chain further") end
    return result
end

function Evolink:ResetTargetChain()
    self.CurrentChainIndex = 1
    print("[Evolink] Chain reset to group 1:", table.concat(self:_GetCurrentTargets() or {}, ", "))
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
    self:_BuildTargetChain()
    print("[Evolink] Set " .. key .. " to:", table.concat(targetList, ", "))
end

function Evolink:SetFallbackChain(chain)
    if type(chain) ~= "table" then warn("[Evolink] SetFallbackChain requires a table of ball names") return end
    self.Config.FallbackChain = chain
    print("[Evolink] FallbackChain set to:", table.concat(self.Config.FallbackChain, " -> "))
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
    print("[Evolink] " .. scenario .. " set to:", ballName)
end

function Evolink:SetStopOnCatch(enabled)
    self.Config.StopOnCatch = enabled == true
    print("[Evolink] StopOnCatch:", self.Config.StopOnCatch and "ENABLED" or "DISABLED")
end

function Evolink:SetFleeFromShiny(enabled)
    self.Config.FleeFromShiny = enabled == true
    print("[Evolink] FleeFromShiny:", self.Config.FleeFromShiny and "ENABLED" or "DISABLED")
end

function Evolink:SetUseSoftCatch(enabled)
    self.Config.UseSoftCatch = enabled ~= false
    print("[Evolink] UseSoftCatch:", self.Config.UseSoftCatch and "ENABLED" or "DISABLED")
end

function Evolink:SetFleeNonShinyAtPityMax(enabled)
    self.Config.FleeNonShinyAtPityMax = enabled ~= false
    print("[Evolink] FleeNonShinyAtPityMax:", self.Config.FleeNonShinyAtPityMax and "ENABLED" or "DISABLED")
end

function Evolink:SetEncounterCooldown(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        warn("[Evolink] SetEncounterCooldown requires a positive number")
        return
    end
    self.Config.EncounterCooldown = seconds
    print("[Evolink] EncounterCooldown set to:", seconds, "seconds")
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
        autoBattle = self.autoBattleEnabled,
        currentChainIndex = self.CurrentChainIndex,
        currentTargets = self:_GetCurrentTargets(),
        ballInventory = self:_UpdateBallInventory(),
    }
end

function Evolink:PrintConfig()
    print("")
    print("=" .. string.rep("=", 62))
    print("  Evolink - Auto Catch + Battle Module")
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

function Evolink:Stop()
    self.Running = false
    self:_RemoveFastBattle()
    self:_StopAutoBattle()
    print("[Evolink] Stopped.")
    print(string.format("[Evolink] Session: %d encounters, %d catches (%d goal), %d flees, %d shiny caught",
        self.SessionStats.encounters, self.SessionStats.catches, self.SessionStats.goalCatches, self.SessionStats.flees, self.SessionStats.shinyCaught))
end

function Evolink:Restart()
    self.Running = true
    print("[Evolink] Restarting main loop...")
    if self.mainLoopThread then
        self.mainLoopThread = nil
    end
    self.mainLoopThread = task.spawn(function()
        local success, err = pcall(function() self:_MainLoop() end)
        if not success then
            warn("[Evolink] Crashed: " .. tostring(err))
            warn("[Evolink] Stack: " .. tostring(debug.traceback()))
        end
    end)
end

function Evolink:Start()
    if self.Running and self.mainLoopThread then
        print("[Evolink] Already running.")
        return
    end
    self.Running = true
    self:PrintConfig()
    self:_UpdateBallInventory()

    if self.Config.FastBattle then
        task.spawn(function()
            task.wait(3)
            self:_ApplyFastBattle()
        end)
    end

    self.mainLoopThread = task.spawn(function()
        local success, err = pcall(function() self:_MainLoop() end)
        if not success then
            warn("[Evolink] Crashed: " .. tostring(err))
            warn("[Evolink] Stack: " .. tostring(debug.traceback()))
        end
    end)
    print("[Evolink] Started.")
end

function Evolink:ExecuteBestSkills()
    return self:_ExecuteBestSkillsForAllPets()
end

function Evolink:StartAutoBattle()
    return self:_StartAutoBattle()
end

function Evolink:StopAutoBattle()
    self:_StopAutoBattle()
end

function Evolink:ToggleAutoBattle()
    if self.autoBattleEnabled then
        self:_StopAutoBattle()
        print("[Evolink] AutoBattle DISABLED")
    else
        self:_StartAutoBattle()
        print("[Evolink] AutoBattle ENABLED")
    end
    return self.autoBattleEnabled
end

function Evolink:SetAutoBattle(enabled)
    if enabled then
        if not self.autoBattleEnabled then
            self:_StartAutoBattle()
        end
        print("[Evolink] AutoBattle ENABLED")
    else
        if self.autoBattleEnabled then
            self:_StopAutoBattle()
        end
        print("[Evolink] AutoBattle DISABLED")
    end
    return self.autoBattleEnabled
end

return Evolink
