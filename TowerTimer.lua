-- TowerTimer.lua - AV tower assault countdown announcements in /s

local addonName, TowerTimer = ...
_G["TowerTimer"] = TowerTimer

-- =============================================================================
-- Constants
-- =============================================================================

local AV_INSTANCE_ID = 30
local KORRAK_INSTANCE_ID = 2197
local TOWER_CAPTURE_TIME = 240 -- 4 minutes
local ANNOUNCE_INTERVAL = 60   -- announce every 60 seconds

local TOWER_NAMES = {
    -- Alliance Bunkers
    "Dun Baldar North Bunker",
    "Dun Baldar South Bunker",
    "Icewing Bunker",
    "Stonehearth Bunker",
    -- Horde Towers
    "Tower Point",
    "Iceblood Tower",
    "East Frostwolf Tower",
    "West Frostwolf Tower",
}

-- =============================================================================
-- State
-- =============================================================================

local isInAV = false
-- activeTimers[towerName] = { remaining = seconds, nextAnnounce = seconds }
local activeTimers = {}

-- =============================================================================
-- Helpers
-- =============================================================================

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function Announce(msg)
    SendChatMessage("[TowerTimer] " .. msg, "SAY")
end

local function PrintLocal(msg)
    print("|cFF00FF00TowerTimer|r: " .. msg)
end

-- Find which tower a BG system message is about
local function FindTowerInMessage(msg)
    for _, name in ipairs(TOWER_NAMES) do
        if msg:find(name) then
            return name
        end
    end
    return nil
end

local function CheckIsInAV()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID == AV_INSTANCE_ID or instanceID == KORRAK_INSTANCE_ID
end

local function ClearAllTimers()
    wipe(activeTimers)
end

-- =============================================================================
-- BG Message Handling
-- =============================================================================

local function OnBGMessage(msg)
    if not isInAV then return end

    local tower = FindTowerInMessage(msg)
    if not tower then return end

    if msg:find("assaulted") or msg:find("claims") then
        -- Tower assaulted - start countdown
        activeTimers[tower] = {
            remaining = TOWER_CAPTURE_TIME,
            nextAnnounce = TOWER_CAPTURE_TIME, -- announce immediately
        }
        PrintLocal(tower .. " assaulted! Timer started (4:00).")
        Announce(tower .. " caps in " .. FormatTime(TOWER_CAPTURE_TIME))

    elseif msg:find("defended") then
        -- Tower defended - cancel timer
        if activeTimers[tower] then
            activeTimers[tower] = nil
            PrintLocal(tower .. " defended. Timer cancelled.")
        end

    elseif msg:find("destroyed") or msg:find("taken") then
        -- Tower destroyed/captured - remove timer
        if activeTimers[tower] then
            activeTimers[tower] = nil
            PrintLocal(tower .. " captured/destroyed.")
        end
    end
end

-- =============================================================================
-- Timer Update (OnUpdate)
-- =============================================================================

local updateFrame = CreateFrame("Frame")
updateFrame:Hide() -- hidden = OnUpdate won't fire until we show it

updateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not isInAV then return end

    local hasTimers = false
    for tower, timer in pairs(activeTimers) do
        hasTimers = true
        timer.remaining = timer.remaining - elapsed
        timer.nextAnnounce = timer.nextAnnounce - elapsed

        if timer.remaining <= 0 then
            -- Timer expired (should coincide with destroyed message, but clean up)
            activeTimers[tower] = nil
        elseif timer.nextAnnounce <= 0 then
            -- Time to announce
            local remaining = math.floor(timer.remaining)
            Announce(tower .. " caps in " .. FormatTime(remaining))
            timer.nextAnnounce = ANNOUNCE_INTERVAL
        end
    end

    if not hasTimers then
        self:Hide() -- stop OnUpdate when no timers active
    end
end)

-- =============================================================================
-- Event Frame
-- =============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")

frame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...

    if event == "ADDON_LOADED" and arg1 == addonName then
        PrintLocal("Loaded. Will announce tower timers in /s while in AV.")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local wasInAV = isInAV
        isInAV = CheckIsInAV()
        if isInAV and not wasInAV then
            PrintLocal("Alterac Valley detected. Tower timers active.")
        elseif not isInAV and wasInAV then
            ClearAllTimers()
            updateFrame:Hide()
            PrintLocal("Left AV. Timers cleared.")
        end

    elseif event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
        or event == "CHAT_MSG_BG_SYSTEM_HORDE"
        or event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        OnBGMessage(arg1)
        -- Make sure the update frame is running if we have timers
        if next(activeTimers) then
            updateFrame:Show()
        end
    end
end)
