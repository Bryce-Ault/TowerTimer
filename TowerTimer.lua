-- TowerTimer.lua - BG start sound notification

local addonName, TowerTimer = ...
_G["TowerTimer"] = TowerTimer

local function PrintLocal(msg)
    print("|cFF00FF00TowerTimer|r: " .. msg)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")

frame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...

    if event == "ADDON_LOADED" and arg1 == addonName then
        PrintLocal("Loaded.")

    elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        if arg1:find("has begun") then
            PlaySound(8174, "Master") -- PVP flag capture (short alert)
            PrintLocal("Battleground started!")
        end
    end
end)
