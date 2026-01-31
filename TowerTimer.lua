-- TowerTimer.lua - AV tower assault countdown announcements + UI bars

local addonName, TowerTimer = ...
_G["TowerTimer"] = TowerTimer

-- =============================================================================
-- Constants
-- =============================================================================

local AV_INSTANCE_ID = 30
local KORRAK_INSTANCE_ID = 2197
local TOWER_CAPTURE_TIME = 240 -- 4 minutes
local ANNOUNCE_INTERVAL = 30   -- announce every 30 seconds

local BAR_WIDTH = 150
local BAR_HEIGHT = 16
local BAR_SPACING = 2
local BAR_FONT_SIZE = 10

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

-- Short display names for the compact bars
local SHORT_NAMES = {
    ["Dun Baldar North Bunker"] = "DB North",
    ["Dun Baldar South Bunker"] = "DB South",
    ["Icewing Bunker"]          = "Icewing",
    ["Stonehearth Bunker"]      = "Stonehearth",
    ["Tower Point"]             = "Tower Point",
    ["Iceblood Tower"]          = "Iceblood",
    ["East Frostwolf Tower"]    = "E Frostwolf",
    ["West Frostwolf Tower"]    = "W Frostwolf",
}

-- =============================================================================
-- State
-- =============================================================================

local isInAV = false
-- activeTimers[towerName] = { remaining = seconds, nextAnnounce = seconds, bar = frame }
local activeTimers = {}
local barPool = {}       -- recycled bar frames
local activeBars = {}    -- ordered list of tower names with active bars

-- =============================================================================
-- Helpers
-- =============================================================================

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function Announce(msg)
    SendChatMessage("[TowerTimer] " .. msg, "PARTY")
end

local function PrintLocal(msg)
    print("|cFF00FF00TowerTimer|r: " .. msg)
end

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

-- Returns r, g, b based on remaining time
local function GetBarColor(remaining)
    if remaining > 120 then
        -- Green to Yellow (240→120)
        local pct = (remaining - 120) / 120 -- 1.0 at 240, 0.0 at 120
        return 1 - pct, 1, 0
    else
        -- Yellow to Red (120→0)
        local pct = remaining / 120 -- 1.0 at 120, 0.0 at 0
        return 1, pct, 0
    end
end

-- =============================================================================
-- UI Bar Container
-- =============================================================================

local container = CreateFrame("Frame", "TowerTimerContainer", UIParent)
container:SetSize(BAR_WIDTH, 1)
container:SetPoint("LEFT", UIParent, "LEFT", 10, 0)
container:Hide()

-- =============================================================================
-- Bar Creation / Pooling
-- =============================================================================

local function CreateBarFrame()
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, TOWER_CAPTURE_TIME)

    -- Dark background behind the bar
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- Tower name (left)
    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameText:SetFont(nameText:GetFont(), BAR_FONT_SIZE, "OUTLINE")
    nameText:SetJustifyH("LEFT")
    bar.nameText = nameText

    -- Countdown (right)
    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    timeText:SetFont(timeText:GetFont(), BAR_FONT_SIZE, "OUTLINE")
    timeText:SetJustifyH("RIGHT")
    bar.timeText = timeText

    return bar
end

local function AcquireBar()
    local bar = table.remove(barPool)
    if not bar then
        bar = CreateBarFrame()
    end
    bar:Show()
    return bar
end

local function ReleaseBar(bar)
    bar:Hide()
    bar:ClearAllPoints()
    table.insert(barPool, bar)
end

-- =============================================================================
-- Bar Layout
-- =============================================================================

local function RepositionBars()
    for i, towerName in ipairs(activeBars) do
        local timer = activeTimers[towerName]
        if timer and timer.bar then
            timer.bar:ClearAllPoints()
            timer.bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((i - 1) * (BAR_HEIGHT + BAR_SPACING)))
        end
    end
    -- Resize container to fit
    local count = #activeBars
    if count > 0 then
        container:SetHeight(count * BAR_HEIGHT + (count - 1) * BAR_SPACING)
        container:Show()
    else
        container:Hide()
    end
end

-- =============================================================================
-- Bar Lifecycle
-- =============================================================================

local function CreateTimerBar(towerName)
    local bar = AcquireBar()
    bar.nameText:SetText(SHORT_NAMES[towerName] or towerName)
    bar.timeText:SetText(FormatTime(TOWER_CAPTURE_TIME))
    bar:SetValue(TOWER_CAPTURE_TIME)
    bar:SetStatusBarColor(0, 1, 0)
    return bar
end

local function RemoveTimerBar(towerName)
    local timer = activeTimers[towerName]
    if timer and timer.bar then
        ReleaseBar(timer.bar)
        timer.bar = nil
    end
    -- Remove from activeBars list
    for i, name in ipairs(activeBars) do
        if name == towerName then
            table.remove(activeBars, i)
            break
        end
    end
    RepositionBars()
end

-- =============================================================================
-- Clear All
-- =============================================================================

local function ClearAllTimers()
    for towerName, timer in pairs(activeTimers) do
        if timer.bar then
            ReleaseBar(timer.bar)
        end
    end
    wipe(activeTimers)
    wipe(activeBars)
    container:Hide()
end

-- =============================================================================
-- BG Message Handling
-- =============================================================================

local function OnBGMessage(msg)
    if not isInAV then return end

    local tower = FindTowerInMessage(msg)
    if not tower then return end

    if msg:find("assaulted") or msg:find("claims") then
        -- If tower already has a timer, remove old bar first
        if activeTimers[tower] then
            RemoveTimerBar(tower)
        end

        local bar = CreateTimerBar(tower)
        activeTimers[tower] = {
            remaining = TOWER_CAPTURE_TIME,
            nextAnnounce = TOWER_CAPTURE_TIME, -- triggers immediate announce
            bar = bar,
        }
        table.insert(activeBars, tower)
        RepositionBars()

        PrintLocal(tower .. " assaulted! Timer started (4:00).")
        Announce(tower .. " caps in " .. FormatTime(TOWER_CAPTURE_TIME))

    elseif msg:find("defended") then
        if activeTimers[tower] then
            PrintLocal(tower .. " defended. Timer cancelled.")
            RemoveTimerBar(tower)
            activeTimers[tower] = nil
        end

    elseif msg:find("destroyed") or msg:find("taken") then
        if activeTimers[tower] then
            PrintLocal(tower .. " captured/destroyed.")
            RemoveTimerBar(tower)
            activeTimers[tower] = nil
        end
    end
end

-- =============================================================================
-- Timer Update (OnUpdate)
-- =============================================================================

local updateFrame = CreateFrame("Frame")
updateFrame:Hide()

updateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not isInAV then return end

    local hasTimers = false
    for tower, timer in pairs(activeTimers) do
        hasTimers = true
        timer.remaining = timer.remaining - elapsed
        timer.nextAnnounce = timer.nextAnnounce - elapsed

        if timer.remaining <= 0 then
            RemoveTimerBar(tower)
            activeTimers[tower] = nil
        else
            -- Update bar visuals
            if timer.bar then
                timer.bar:SetValue(timer.remaining)
                timer.bar.timeText:SetText(FormatTime(math.floor(timer.remaining)))
                local r, g, b = GetBarColor(timer.remaining)
                timer.bar:SetStatusBarColor(r, g, b)
            end

            -- Party chat announcement
            if timer.nextAnnounce <= 0 then
                local remaining = math.floor(timer.remaining)
                Announce(tower .. " caps in " .. FormatTime(remaining))
                timer.nextAnnounce = ANNOUNCE_INTERVAL
            end
        end
    end

    if not hasTimers then
        self:Hide()
        container:Hide()
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
        PrintLocal("Loaded. Will announce tower timers in party chat while in AV.")

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

        -- Detect AV game start
        if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" and isInAV
            and (arg1:find("begun") or arg1:find("begin")) then
            PlaySound(8959, "Master") -- PVPFLAGCAPTUREDHORDE (loud raid-horn sound)
            PrintLocal("AV has started! GO GO GO!")
        end

        OnBGMessage(arg1)
        if next(activeTimers) then
            updateFrame:Show()
        end
    end
end)
