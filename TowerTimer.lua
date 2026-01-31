-- TowerTimer.lua - Minimal: just detect if we're in Alterac Valley

local addonName, TowerTimer = ...
_G["TowerTimer"] = TowerTimer

local AV_INSTANCE_ID = 30
local KORRAK_INSTANCE_ID = 2197

local isInAV = false

local function PrintLocal(msg)
    print("|cFF00FF00TowerTimer|r: " .. msg)
end

local function CheckIsInAV()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID == AV_INSTANCE_ID or instanceID == KORRAK_INSTANCE_ID
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

frame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...

    if event == "ADDON_LOADED" and arg1 == addonName then
        PrintLocal("Loaded.")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local wasInAV = isInAV
        isInAV = CheckIsInAV()
        if isInAV and not wasInAV then
            PrintLocal("Alterac Valley detected!")
        elseif not isInAV and wasInAV then
            PrintLocal("Left Alterac Valley.")
        end
    end
end)
