--[[
    DreadPlagueTracker.lua
    Core tracking logic for Dread Plague (spell ID 1240996) on Unholy Death Knight.
    Scans all available units every 0.25s and displays a movable icon or bar frame
    showing whether Dread Plague is active, on whom, and how long remains.
]]

-- Binding header globals must be set before Bindings.xml is processed by
-- the keybinding UI. Set them at file-load time, not inside any function.
_G.BINDING_HEADER_DREADPLAGUETRACKER = "DreadPlagueTracker"
_G.BINDING_NAME_DREADPLAGUETRACKER_REPORT = "Report Issue (mark log)"

-- ============================================================
-- CONSTANTS
-- ============================================================
local ADDON_NAME        = "DreadPlagueTracker"
local DREAD_PLAGUE_ID   = 1240996
local UNHOLY_SPEC_ID    = 252          -- Unholy DK spec ID
local SCAN_INTERVAL     = 0.25         -- seconds between unit scans
local FLASH_MIN_ALPHA   = 0.2
local FLASH_MAX_ALPHA   = 1.0

-- Dread Plague can only be on ONE target at a time, but you may have switched
-- targets since applying it. Scan all visible units to find it wherever it is.
local SCAN_UNITS = { "target", "focus" }
for i = 1, 40 do
    table.insert(SCAN_UNITS, "nameplate" .. i)
end

-- ============================================================
-- DEBUG LOGGING
-- Writes to chat frame (if verbose is on) AND to a saved-variable
-- ring buffer for post-hoc analysis. Toggled via checkbox in config.
-- ============================================================
_G.DPT_DEBUG_LOG = false  -- legacy var kept for backwards compat

local MAX_LOG_ENTRIES = 1000

local function FindDPTChatFrame()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.name == "DPT" then
            return cf
        end
    end
    return DEFAULT_CHAT_FRAME
end

-- Forward declare; DreadPlagueTrackerLog is the SavedVariable
local function IsVerboseLogging()
    return _G.DPT_DEBUG_LOG or (DreadPlagueTrackerDB and DreadPlagueTrackerDB.verboseLogging)
end

local function dlog(...)
    if not IsVerboseLogging() then return end
    local args = {...}
    local parts = {}
    for i = 1, #args do
        parts[i] = tostring(args[i])
    end
    local text = table.concat(parts, " ")

    -- Write to chat window
    FindDPTChatFrame():AddMessage("|cff9900ff[DPT]|r " .. text)

    -- Write to saved variable ring buffer with timestamp
    if not DreadPlagueTrackerLog then
        _G.DreadPlagueTrackerLog = { entries = {} }
    end
    local log = DreadPlagueTrackerLog.entries
    local ts = date("%H:%M:%S") .. string.format(".%03d", math.floor((GetTime() % 1) * 1000))
    table.insert(log, ts .. "  " .. text)
    -- Ring buffer: drop oldest when over limit
    while #log > MAX_LOG_ENTRIES do
        table.remove(log, 1)
    end
end

local DEFAULTS = {
    -- Position
    x             = 0,
    y             = 200,

    -- Icon settings
    iconSize      = 44,

    -- Appearance
    showEnemyName   = true,     -- show the DREAD PLAGUE / MISSING label
    nameFontSize    = 14,
    bgOpacity       = 0.6,

    -- Colors (r, g, b, a)
    activeColor  = { r = 0.0, g = 0.85, b = 0.2,  a = 1.0 },
    missingColor = { r = 0.9, g = 0.1,  b = 0.1,  a = 1.0 },

    -- Behavior
    flashWhenMissing  = true,
    flashSpeed        = 1.5,     -- cycles per second
    showOutOfCombat   = false,   -- show frame outside of combat (for positioning)
    soundOnMissing    = true,    -- play sound when DP falls off
    soundChoice       = 1,       -- index into SOUND_CHOICES catalog

    -- Diagnostics
    verboseLogging    = false,   -- write detailed log to SavedVariable for analysis

    -- Minimap button
    minimapHide       = false,   -- hide minimap button
    minimapAngle      = 225,     -- position around minimap (degrees)
}

-- ============================================================
-- STATE
-- ============================================================
local db                = nil   -- saved variables table (populated on ADDON_LOADED)
local trackerFrame      = nil   -- the main display frame
local scanTicker        = nil   -- C_Timer ticker handle
local flashElapsed      = 0
local isFlashing        = false
local plagueWasActive   = false -- tracks previous state to detect transitions
local lastKnownState    = nil   -- "active" | "missing" | "hidden"

-- Current tracking data
local plagueData = {
    active     = false,
    unitName   = nil,
    expiration = nil,    -- GetTime() value when aura expires
    duration   = nil,    -- total duration of the aura
}

-- ============================================================
-- HELPERS
-- ============================================================

local function IsUnholySpec()
    local specID = GetSpecializationInfo(GetSpecialization())
    return specID == UNHOLY_SPEC_ID
end

local function IsDeathKnight()
    local _, class = UnitClass("player")
    return class == "DEATHKNIGHT"
end

local function ShouldShow()
    -- Only show while in Death Knight (any spec); Dread Plague is a DK-specific aura
    if not IsDeathKnight() then return false end
    -- Show if in combat, or if plague is actively tracked, or if showOutOfCombat is on
    if not InCombatLockdown() and not plagueData.active and not db.showOutOfCombat then
        return false
    end
    return true
end

local function GetColor(colorTable)
    return colorTable.r, colorTable.g, colorTable.b, colorTable.a
end

-- ============================================================
-- SCANNING
-- ============================================================

-- ============================================================
-- COMBAT LOG TRACKING
-- Track Dread Plague via CLEU. The only reliable untainted source
-- CLEU events fire when any aura is applied/removed/refreshed
-- ============================================================

local function ScanForDreadPlague()
    -- This is now a no-op. All tracking happens via CLEU events below
    -- We keep this function for compatibility with the ticker
end



-- ============================================================
-- FRAME BUILDING
-- ============================================================

local function BuildTrackerFrame()
    -- Main container
    local f = CreateFrame("Frame", "DPTFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local uiX = x - GetScreenWidth()  / 2
        local uiY = y - GetScreenHeight() / 2
        db.x = uiX
        db.y = uiY
    end)

    -- Background texture
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, db.bgOpacity)

    -- Icon texture (used in both modes; hidden in bar mode if showIconOnBar=false)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(C_Spell.GetSpellTexture(DREAD_PLAGUE_ID) or "Interface\\Icons\\Spell_Shadow_UnholyFrenzy")

    -- Status bar (bar mode)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(1)

    -- Bar background
    f.barBg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.barBg:SetAllPoints(f.bar)
    f.barBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Timer text
    f.timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.timerText:SetTextColor(1, 1, 1, 1)

    -- Enemy name text
    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.nameText:SetTextColor(1, 1, 1, 1)

    -- Status border/highlight (colored outline indicating active vs missing)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    -- We'll color this texture via vertex color
    f.border:SetAllPoints(f)
    f.border:SetAlpha(0)  -- hidden by default; we use bg color instead

    f:Hide()
    return f
end

-- ============================================================
-- LAYOUT APPLICATION
-- ============================================================

local function ApplyLayout()
    if not trackerFrame then return end
    local f = trackerFrame
    local iconTex = C_Spell.GetSpellTexture(DREAD_PLAGUE_ID) or "Interface\\Icons\\Spell_Shadow_UnholyFrenzy"
    f.icon:SetTexture(iconTex)

    -- Icon mode only (bar mode removed; no reliable timer due to Midnight taint)
    local sz = db.iconSize
    f:SetSize(sz + 4, sz + 4 + (db.showEnemyName and (db.nameFontSize + 6) or 0))

    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    f.icon:SetSize(sz, sz)
    f.icon:Show()

    f.bar:Hide()
    f.barBg:Hide()
    f.timerText:Hide()

    -- Label below icon
    if db.showEnemyName then
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("TOP", f.icon, "BOTTOM", 0, -2)
        f.nameText:SetFont(STANDARD_TEXT_FONT, db.nameFontSize, "OUTLINE")
        f.nameText:Show()
    else
        f.nameText:Hide()
    end

    -- Background covers entire frame
    f.bg:SetColorTexture(0, 0, 0, db.bgOpacity)

    -- Reposition frame from saved coords
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
end

-- ============================================================
-- VISUAL UPDATE
-- ============================================================

-- Sound options: file paths for alert sounds
local SOUND_OPTIONS = {
    [1] = "Interface\AddOns\DreadPlagueTracker\Sounds\alarm.ogg",  -- custom if available
    [2] = 8959,   -- SOUNDKIT.RAID_WARNING (built-in)
    [3] = 1194,   -- SOUNDKIT.IG_QUEST_LIST_OPEN (bell)
}

-- Sound catalog. Verified IDs from Blizzard's SOUNDKIT table
-- Using SOUNDKIT.* constants where available for patch-safety
local SOUND_IDS = {
    SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
    SOUNDKIT and SOUNDKIT.READY_CHECK  or 8960,
    SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 18019,
    SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_DEFEATED or 50111,
    SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 3175,
    SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE or 880,
    SOUNDKIT and SOUNDKIT.LEVEL_UP or 888,
    SOUNDKIT and SOUNDKIT.MAP_PING or 3337,
    SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE or 8455,
    SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or 39517,
}

local function PlayMissingSound()
    if not db or not db.soundOnMissing then return end
    local sound = SOUND_IDS[db.soundChoice or 1]
    if sound then PlaySound(sound, "Master") end
end

local function ClearPlagueData()
    if plagueData.active then
        PlayMissingSound()
    end
    plagueData.active     = false
    plagueData.unitName   = nil
    plagueData.expiration = nil
    plagueData.trackingStart = nil
    plagueData.duration   = nil
    dreadPlagueInstanceID = nil
    dreadPlagueUnitGUID   = nil
    vpInstanceID          = nil
    jumpPendingUntil      = 0
    lastSeenTime          = 0
    lastRemovalUnit       = nil
    visibleInstanceIDs    = {}
    if pendingClearTimer then pendingClearTimer:Cancel(); pendingClearTimer = nil end
end

local function UpdateDisplay(elapsed)
    if not trackerFrame then return end
    local f = trackerFrame

    -- Visibility
    if not ShouldShow() then
        f:Hide()
        isFlashing = false
        plagueWasActive = false
        return
    end
    f:Show()

    local isActive = plagueData.active

    plagueWasActive = isActive

    if isActive then
        -- ACTIVE STATE: solid active color, show label
        isFlashing = false
        flashElapsed = 0
        local r, g, b, a = GetColor(db.activeColor)
        f.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, db.bgOpacity)
        f.icon:SetVertexColor(r, g, b)

        if f.timerText then f.timerText:SetText("") end

        if db.showEnemyName and f.nameText then
            f.nameText:SetText("DREAD PLAGUE")
            f.nameText:SetTextColor(1, 1, 1, 1)
        end

        f:SetAlpha(1.0)

    else
        -- MISSING STATE: missing color, flashing in combat
        local r, g, b, a = GetColor(db.missingColor)
        f.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, db.bgOpacity)
        f.icon:SetVertexColor(r, g, b)

        if f.timerText then f.timerText:SetText("") end

        if db.showEnemyName and f.nameText then
            f.nameText:SetText("MISSING")
            f.nameText:SetTextColor(r, g, b, 1)
        end

        -- Flashing when missing in combat
        if db.flashWhenMissing and InCombatLockdown() then
            isFlashing = true
            flashElapsed = flashElapsed + elapsed
            local cycle = math.pi * 2 * db.flashSpeed * flashElapsed
            local alpha = FLASH_MIN_ALPHA + (FLASH_MAX_ALPHA - FLASH_MIN_ALPHA) * ((math.sin(cycle) + 1) / 2)
            f:SetAlpha(alpha)
        else
            isFlashing = false
            flashElapsed = 0
            f:SetAlpha(1.0)
        end
    end
end

-- ============================================================
-- TICKER & EVENTS
-- ============================================================

local function StartScanning()
    if scanTicker then return end
    scanTicker = C_Timer.NewTicker(SCAN_INTERVAL, function()
        ScanForDreadPlague()
    end)
end

local function StopScanning()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
    -- Do NOT clear plagueData here. UNIT_AURA removal events handle that
    -- Plague may still be ticking on a target even after leaving combat
end

-- Track the auraInstanceID of Dread Plague
-- We find it by name (name is not tainted) via GetAuraDataByAuraInstanceID
local DREAD_PLAGUE_NAME = "Dread Plague"
local dreadPlagueInstanceID = nil  -- the auraInstanceID once we find it

local function CheckAuraByInstanceID(unitId, instanceID)
    local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unitId, instanceID)
    if data and data.name == DREAD_PLAGUE_NAME then
        return data
    end
    return nil
end

local function ScanUnitForDreadPlague(unitId)
    -- Scan by index, use name (not spellId) to identify Dread Plague
    -- Use pcall to handle tainted name fields
    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(unitId, i, "HARMFUL")
        if not data then break end
        local ok, isMatch = pcall(function()
            return data.name == DREAD_PLAGUE_NAME
        end)
        if ok and isMatch then
            return data
        end
        i = i + 1
    end
    return nil
end

-- UNIT_AURA tracking using deferred C_Timer.After(0) to break taint chain
-- auraInstanceID is always readable; we collect instance IDs from the event
-- then defer a clean-context scan to read the actual aura data

-- Track removals via UNIT_AURA (auraInstanceID is always untainted)
-- Track additions via an independent ticker that scans target directly
-- The ticker runs outside any event context so data is never tainted

local VIRULENT_PLAGUE_ID = 191587  -- we need to distinguish VP from DP
local knownInstanceIDs = {}        -- all known harmful aura instance IDs on target
local TRUSTED_UNITS = { target = true, focus = true }

-- In Midnight, ALL aura data fields except auraInstanceID are tainted.
-- Strategy: collect all auraInstanceIDs on target after Outbreak is cast.
-- We identify Dread Plague's instanceID by tracking WHICH new instanceID
-- appeared that is NOT Virulent Plague (191587).
-- We do this by storing known VP instance IDs and the "other" one is DP.

local OUTBREAK_SPELL_ID  = 77575
-- Spells that extend plague duration:
-- Epidemic/Death Coil/Graveyard/Necrotic Coil = +1s each
-- Putrefy (Blightburst) = +4s (reduced during Forbidden Knowledge)
-- We track the last cast to know the extension amount
local EPIDEMIC_SPELL_ID       = 207317   -- Epidemic
local DEATH_COIL_SPELL_ID     = 47541    -- Death Coil
local PUTREFY_SPELL_ID        = 1247378  -- Putrefy (Midnight confirmed)
local GRAVEYARD_SPELL_ID      = 383269   -- Graveyard (FK replacement for Epidemic, confirmed)
local NECROTIC_COIL_SPELL_ID  = 1242174  -- Necrotic Coil (FK replacement for Death Coil, confirmed)

local lastCastExtensionAmount = 1  -- default 1s, updated on spell cast

-- Read all current harmful aura instance IDs on a unit (instanceID always readable)
local function GetAllInstanceIDs(unitId)
    local ids = {}
    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(unitId, i, "HARMFUL")
        if not data then break end
        ids[data.auraInstanceID] = true
        i = i + 1
    end
    return ids
end

-- After Outbreak, scan target and find the new DP instance ID
-- We do this by comparing instance IDs before/after
-- Since we can't read spellId, we find the instance ID at index 2
-- which is always Dread Plague after Outbreak on a fresh target
local vpInstanceID        = nil  -- VP's current instance ID (to exclude from DP scan)
local dreadPlagueUnitGUID = nil  -- GUID of unit currently carrying DP

-- Collect ALL harmful aura instance IDs on a unit (auraInstanceID always safe)
local function GetAllHarmfulInstanceIDs(unitId)
    local ids = {}
    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(unitId, i, "HARMFUL")
        if not data then break end
        ids[data.auraInstanceID] = true
        i = i + 1
    end
    return ids
end

-- Search a unit's harmful auras for one matching the Dread Plague spellId.
-- Returns the auraInstanceID if found, or nil. Under Midnight's taint regime,
-- aura.spellId returns a "secret number" that can be read but throws on
-- comparison. Every access AND every comparison must be pcall-wrapped.
-- If the comparison throws, we just skip that aura entry.
local function FindDPInstanceOnUnit(unitId)
    local found = nil
    pcall(function()
        local i = 1
        while i < 50 do  -- safety cap to prevent infinite loop
            local data = C_UnitAuras.GetAuraDataByIndex(unitId, i, "HARMFUL")
            if not data then break end
            -- Wrap the full read-AND-compare in one pcall so we catch both
            -- access-side taint throws and comparison-side taint throws.
            local matched = false
            pcall(function()
                if data.spellId == DREAD_PLAGUE_ID then
                    matched = true
                end
            end)
            if matched then
                local instID = nil
                pcall(function() instID = data.auraInstanceID end)
                if instID then
                    found = instID
                    return
                end
            end
            i = i + 1
        end
    end)
    return found
end

local outbreakCastTime       = 0      -- timestamp of last Outbreak cast
local OUTBREAK_DETECT_WINDOW = 3.0    -- only detect DP within 3s of Outbreak
local dpApplyCastTime        = 0      -- timestamp of any spell that could apply DP
local DP_APPLY_WINDOW        = 3.0    -- passive detection only within this window
local jumpPendingUntil       = 0      -- timestamp; if GetTime() < this, DP is jumping
local JUMP_GRACE_WINDOW      = 1.0    -- seconds to wait for DP to jump after target death
local pendingClearTimer      = nil    -- C_Timer handle for deferred clear
local lastRemovalUnit        = nil    -- unitId where DP was last removed (reject same-unit jumps)

-- Timer tracking: use expiration timestamp set at detection time
-- Extended by spell cast events (Epidemic +1.5s, Putrefy +4s, etc.)
-- This is the most reliable approach given Midnight API restrictions

-- UpdateDurationObject used to try to read aura.expirationTime to sync our
-- tracked expiration against reality. Under Midnight's taint regime, while
-- expirationTime can be *read* (it's a number), any arithmetic/comparison
-- on it throws (it's a "secret number"). pcall can catch the throw, but
-- we still can't use the value for anything. So this function is now a
-- no-op kept only as a stub in case future API changes make it usable.
-- Our tracked expiration math (base 18s + extensions, capped at 24s) is
-- our sole source of truth.
local function UpdateDurationObject(unitId, instanceID)
    -- intentionally empty
end

-- Track when we last confirmed DP is visible somewhere
local lastSeenTime = 0
local LOST_SIGHT_TIMEOUT = 8.0  -- seconds of not seeing DP before treating as gone (generous; nameplates can flicker)

-- Set of harmful aura instance IDs currently visible on nearby units
-- Rebuilt each tick. Represents the current state, not history
-- An aura that appears in addedAuras but is NOT in this set is a genuinely
-- NEW aura (not just a propagation event from existing aura)
local visibleInstanceIDs = {}
local function RebuildVisibleIDs()
    local newSet = {}
    local unitsToCheck = {"target", "focus"}
    for i = 1, 40 do
        unitsToCheck[#unitsToCheck + 1] = "nameplate" .. i
    end
    for _, unitId in ipairs(unitsToCheck) do
        if UnitExists(unitId) then
            local ids = GetAllHarmfulInstanceIDs(unitId)
            for id in pairs(ids) do
                newSet[id] = true
            end
        end
    end
    visibleInstanceIDs = newSet
end

-- Ticker: verify DP presence by scanning all visible units for our instance ID
-- No GUID comparison (tainted in Midnight). Just match instance IDs.
-- We NEVER clear from the ticker. UNIT_AURA removal is the definitive signal.
-- Fully wrapped in pcall: if anything inside throws (likely taint), we DON'T
-- want the ticker to silently stop, since that leaves the tracker permanently stuck.
local scanTicker2 = C_Timer.NewTicker(0.2, function()
    local ok, err = pcall(function()
    if not db or not IsDeathKnight() then return end
    if not plagueData.active then return end
    if not dreadPlagueInstanceID then return end  -- jump pending, don't touch

    local unitsToCheck = {"target", "focus"}
    for i = 1, 40 do
        unitsToCheck[#unitsToCheck + 1] = "nameplate" .. i
    end

    local foundDP = false
    for _, unitId in ipairs(unitsToCheck) do
        if UnitExists(unitId) then
            local ids = GetAllHarmfulInstanceIDs(unitId)
            if ids[dreadPlagueInstanceID] then
                UpdateDurationObject(unitId, dreadPlagueInstanceID)
                lastSeenTime = GetTime()
                foundDP = true
                break
            end
        end
    end

    -- Rebuild set of currently visible aura IDs (not cumulative)
    RebuildVisibleIDs()

    -- Expiration backstop: DP has a hard 18s duration. If our expiration timestamp
    -- has passed by more than a few seconds, we're stuck on a phantom ID, clear.
    if plagueData.expiration and GetTime() > plagueData.expiration + 3 then
        dlog("EXPIRATION BACKSTOP: DP id=" .. tostring(dreadPlagueInstanceID) ..
             " past expiration by " .. string.format("%.1f", GetTime() - plagueData.expiration) .. "s, clearing")
        ClearPlagueData()
        return
    end

    -- Lost sight detection: if we haven't confirmed DP in several seconds,
    -- AND we're in combat, the mob may have died without firing UNIT_AURA removal
    if not foundDP and lastSeenTime > 0 and
       (GetTime() - lastSeenTime) > LOST_SIGHT_TIMEOUT and
       InCombatLockdown() then
        dlog("LOST SIGHT: DP id=" .. tostring(dreadPlagueInstanceID) .. " not seen in " .. LOST_SIGHT_TIMEOUT .. "s while in combat, entering jump-pending")
        jumpPendingUntil = GetTime() + JUMP_GRACE_WINDOW
        dreadPlagueInstanceID = nil
        lastSeenTime = 0
        if pendingClearTimer then pendingClearTimer:Cancel() end
        pendingClearTimer = C_Timer.NewTimer(JUMP_GRACE_WINDOW, function()
            pendingClearTimer = nil
            if plagueData.active and not dreadPlagueInstanceID then
                dlog("NO JUMP (lost sight): clearing")
                ClearPlagueData()
            end
        end)
    end

    -- Also clear if we're out of combat and DP hasn't been seen for a while
    -- (mobs died, combat ended, cleanup)
    if not foundDP and lastSeenTime > 0 and
       (GetTime() - lastSeenTime) > LOST_SIGHT_TIMEOUT * 2 and
       not InCombatLockdown() then
        dlog("LOST SIGHT (out of combat): clearing")
        ClearPlagueData()
    end
    end)  -- end pcall
    if not ok then
        dlog("TICKER ERROR: " .. tostring(err))
    end
end)

local auraFrame = CreateFrame("Frame")
auraFrame:RegisterEvent("UNIT_AURA")
auraFrame:SetScript("OnEvent", function(self, event, unitId, updateInfo)
    if not db or not IsDeathKnight() then return end

    -- Ignore events from units we don't care about (player, pets, party, etc.)
    -- Only care about target, focus, and nameplates
    local isRelevant = (unitId == "target" or unitId == "focus" or
                        (type(unitId) == "string" and unitId:sub(1, 9) == "nameplate"))
    if not isRelevant then return end

    -- Passive detection: DP may be applied by Putrefy (via Blightburst talent)
    -- or Soul Reaper triggered Putrefy, without an Outbreak cast.
    -- Only fires within DP_APPLY_WINDOW of a spell YOU cast that can apply DP,
    -- preventing us from picking up other players' debuffs.
    if not plagueData.active and not dreadPlagueInstanceID and
       (GetTime() - dpApplyCastTime) <= DP_APPLY_WINDOW and
       UnitExists(unitId) and UnitCanAttack("player", unitId) and
       updateInfo and updateInfo.addedAuras then

        local newIDs = {}
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.auraInstanceID then
                table.insert(newIDs, aura.auraInstanceID)
            end
        end

        -- 2-aura case: likely DP + VP from Outbreak or Blightburst
        -- 1-aura case: likely DP jump/reapply from Putrefy (VP already exists elsewhere)
        if #newIDs == 2 then
            table.sort(newIDs)
            dreadPlagueInstanceID = newIDs[1]
            vpInstanceID          = newIDs[2]
            dreadPlagueUnitGUID   = nil
            plagueData.active     = true
            plagueData.unitName   = "enemy"
            plagueData.duration   = 18
            plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
            plagueData.trackingStart = GetTime()
            lastSeenTime          = GetTime()
            dlog("PASSIVE DETECT (2-aura): DP=" .. newIDs[1] .. " VP=" .. newIDs[2] .. " on " .. unitId)
            return
        elseif #newIDs == 1 then
            -- Only accept if not already on another unit (which would mean VP spread)
            -- Skip target/focus to avoid alias confusion. Only check nameplates
            local function isOnOther(id)
                for i = 1, 40 do
                    local np = "nameplate" .. i
                    if np ~= unitId and UnitExists(np) then
                        local ids = GetAllHarmfulInstanceIDs(np)
                        if ids[id] then return true end
                    end
                end
                return false
            end
            local newID = newIDs[1]
            if not isOnOther(newID) then
                dreadPlagueInstanceID = newID
                vpInstanceID          = nil  -- don't know VP ID yet
                dreadPlagueUnitGUID   = nil
                plagueData.active     = true
                plagueData.unitName   = "enemy"
                plagueData.duration   = 18
                plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
                lastSeenTime          = GetTime()
                dlog("PASSIVE DETECT (1-aura): DP=" .. newID .. " on " .. unitId)
                return
            end
        end
    end

    -- Re-detection during jump-pending: handle Outbreak re-cast or DP jump
    --   (A) Outbreak re-cast: 2 auras added (DP+VP) - same pattern as initial detection
    --   (B) DP natural jump on target death: 1 aura added
    --   (C) Blightburst/Putrefy applied DP to new target: 1 aura added
    if plagueData.active and not dreadPlagueInstanceID and
       GetTime() < jumpPendingUntil and
       UnitExists(unitId) and UnitCanAttack("player", unitId) and
       updateInfo and updateInfo.addedAuras then

        local addedIDs = {}
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.auraInstanceID then
                table.insert(addedIDs, aura.auraInstanceID)
            end
        end

        -- Key insight: a freshly-applied DP should NOT be on any other unit yet
        -- We verify by checking if the ID is visible on any OTHER unit currently
        -- Skip target/focus since they are always aliases of nameplateN. Checking
        -- them would duplicate and GUID alias detection is unreliable under Midnight taint.
        RebuildVisibleIDs()

        local function isIDOnOtherUnit(id)
            for i = 1, 40 do
                local np = "nameplate" .. i
                if np ~= unitId and UnitExists(np) then
                    local ids = GetAllHarmfulInstanceIDs(np)
                    if ids[id] then return true end
                end
            end
            return false
        end

        -- Scenario A: Outbreak-style two auras (DP + VP together)
        if #addedIDs == 2 then
            local id1, id2 = addedIDs[1], addedIDs[2]
            -- Neither should be on another unit (a fresh Outbreak applies to just this unit)
            if not isIDOnOtherUnit(id1) and not isIDOnOtherUnit(id2) then
                table.sort(addedIDs)
                dreadPlagueInstanceID = addedIDs[1]
                vpInstanceID          = addedIDs[2]
                plagueData.unitName   = "enemy"
                plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
                plagueData.duration   = 18
                jumpPendingUntil      = 0
                lastSeenTime          = GetTime()
                lastRemovalUnit       = nil
                if pendingClearTimer then pendingClearTimer:Cancel(); pendingClearTimer = nil end
                dlog("RECAST/JUMP CAUGHT (2-aura): DP=" .. addedIDs[1] .. " VP=" .. addedIDs[2] .. " on " .. unitId)
                return
            else
                dlog("IGNORED 2-aura (already on other unit): " .. id1 .. "," .. id2)
            end

        -- Scenario B/C: single aura. Must not be VP, not already on another unit.
        elseif #addedIDs == 1 then
            local newID = addedIDs[1]
            local isVP = (newID == vpInstanceID)
            local onOther = false
            if not isVP then
                onOther = isIDOnOtherUnit(newID)
            end
            if not isVP and not onOther then
                dreadPlagueInstanceID = newID
                plagueData.unitName   = "enemy"
                plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
                plagueData.duration   = 18
                jumpPendingUntil      = 0
                lastSeenTime          = GetTime()
                lastRemovalUnit       = nil
                if pendingClearTimer then pendingClearTimer:Cancel(); pendingClearTimer = nil end
                dlog("JUMP CAUGHT (1-aura): new DP=" .. newID .. " on " .. unitId)
                return
            else
                dlog("IGNORED 1-aura: id=" .. newID .. " (VP=" .. tostring(isVP) .. " onOther=" .. tostring(onOther) .. ")")
            end
        end
    end

    -- Initial detection: only detect DP within the window after Outbreak is cast
    -- This prevents false positives from other debuffs applied on attack
    if not plagueData.active and unitId == "target" and
       UnitExists("target") and UnitCanAttack("player", "target") and
       updateInfo and updateInfo.addedAuras and
       (GetTime() - outbreakCastTime) <= OUTBREAK_DETECT_WINDOW then
        local addedIDs = {}
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.auraInstanceID then
                table.insert(addedIDs, aura.auraInstanceID)
            end
        end
        if #addedIDs >= 2 then
            table.sort(addedIDs)
            dreadPlagueInstanceID = addedIDs[1]
            vpInstanceID          = addedIDs[2]
            dreadPlagueUnitGUID   = nil
            plagueData.active     = true
            plagueData.unitName   = "enemy"
            plagueData.duration   = 18
            plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
            lastSeenTime          = GetTime()
            dlog("DETECTED: DP=" .. addedIDs[1] .. " VP=" .. addedIDs[2] .. " name=" .. tostring(plagueData.unitName))
            return
        elseif #addedIDs == 1 and addedIDs[1] ~= vpInstanceID then
            dreadPlagueInstanceID = addedIDs[1]
            dreadPlagueUnitGUID   = nil
            plagueData.active     = true
            plagueData.unitName   = "enemy"
            plagueData.duration   = 18
            plagueData.expiration = GetTime() + 18
            plagueData.trackingStart = GetTime()
            lastSeenTime          = GetTime()
            dlog("DETECTED (single): DP=" .. addedIDs[1] .. " name=" .. tostring(plagueData.unitName))
            return
        end
    end

    -- Track removals from ANY unit. auraInstanceID comparison is always safe
    if updateInfo and updateInfo.removedAuraInstanceIDs and plagueData.active and dreadPlagueInstanceID then
        local ok, err = pcall(function()
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            if instanceID == vpInstanceID then
                -- VP refreshed: find its new instanceID from addedAuras
                vpInstanceID = nil
                if updateInfo.addedAuras then
                    for _, added in ipairs(updateInfo.addedAuras) do
                        if added.auraInstanceID ~= dreadPlagueInstanceID then
                            vpInstanceID = added.auraInstanceID
                        end
                    end
                end
            elseif instanceID == dreadPlagueInstanceID then
                -- Instance IDs are globally unique. If our DP's ID is being
                -- removed, it IS our DP. No GUID comparison needed.
                -- Check if DP was simultaneously re-added (refresh/extension)
                local newDPInstanceID = nil
                if updateInfo.addedAuras then
                    for _, added in ipairs(updateInfo.addedAuras) do
                        if added.auraInstanceID ~= vpInstanceID then
                            newDPInstanceID = added.auraInstanceID
                        end
                    end
                end
                if newDPInstanceID then
                    dlog("DP REFRESHED: old=" .. tostring(instanceID) .. " new=" .. newDPInstanceID)
                    dreadPlagueInstanceID = newDPInstanceID
                    plagueData.expiration = GetTime() + (plagueData.duration or 18)
                    plagueData.trackingStart = GetTime()
                else
                    -- Try the spurious removal check, but handle taint errors.
                    -- If the check errors out (tainted GUID comparison), treat as NOT spurious.
                    -- This means we trust the removal event and move on.
                    -- Only check nameplates (not target/focus) to avoid alias duplication.
                    local checkOk, stillVisibleElsewhere, foundOnUnit = pcall(function()
                        local visible = false
                        local onUnit = nil
                        for npIdx = 1, 40 do
                            local np = "nameplate" .. npIdx
                            if np ~= unitId and UnitExists(np) then
                                local ids = GetAllHarmfulInstanceIDs(np)
                                if ids[instanceID] then
                                    visible = true
                                    onUnit = np
                                    break
                                end
                            end
                        end
                        return visible, onUnit
                    end)

                    if not checkOk then
                        -- Spurious check threw. Be conservative: treat as SPURIOUS
                        -- (don't clear). If DP is really gone, one of our other
                        -- layered backstops will catch it (EXPIRATION BACKSTOP,
                        -- LOST_SIGHT_TIMEOUT, or the next real removal event).
                        -- Trusting the removal here was causing false-red firings.
                        dlog("SPURIOUS CHECK failed (taint): treating as spurious, keeping DP")
                        stillVisibleElsewhere = true
                        foundOnUnit = "taint"
                    end

                    -- Expiration sanity check: DP can't live past its expiration.
                    -- NOTE: No SPURIOUS OVERRIDE here. Tracked expiration drifts when
                    -- we miss refreshes, so we can't use it to override the spurious
                    -- check. The EXPIRATION BACKSTOP in the ticker will catch phantom
                    -- IDs that truly need to clear, and the FALSE REMOVAL / DP
                    -- RE-IDENTIFIED final scans catch silent ID changes.

                    if stillVisibleElsewhere then
                        dlog("SPURIOUS REMOVAL: id=" .. tostring(instanceID) .. " still visible on " .. tostring(foundOnUnit) .. ", ignoring")
                    else
                        -- Log removal context: size of removal list helps distinguish
                        -- a mob death (big batch of removals) from a range-out event
                        -- (typically just one or a few IDs) or a natural expiration.
                        local removedCount = updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs or 0
                        dlog("DP REMOVED (pending jump check): id=" .. tostring(instanceID) ..
                             " unit=" .. tostring(unitId) ..
                             " batch=" .. removedCount ..
                             " trackedRemaining=" .. string.format("%.1f", (plagueData.expiration or GetTime()) - GetTime()) .. "s")

                        jumpPendingUntil = GetTime() + JUMP_GRACE_WINDOW
                        lastRemovalUnit = unitId
                        local preservedID = instanceID  -- capture for post-grace scan
                        dreadPlagueInstanceID = nil
                        if pendingClearTimer then pendingClearTimer:Cancel() end
                        pendingClearTimer = C_Timer.NewTimer(JUMP_GRACE_WINDOW, function()
                            pendingClearTimer = nil
                            local tOk, tErr = pcall(function()
                            if plagueData.active and not dreadPlagueInstanceID then
                                -- Final scan: the removal might have been a false signal
                                -- (esp. batch=1 cases). Two checks:
                                -- 1. Is our old ID still visible anywhere? (false removal)
                                -- 2. Is there a NEW DP aura (by spellId) on any nameplate? (silent re-issue)
                                for npIdx = 1, 40 do
                                    local np = "nameplate" .. npIdx
                                    if UnitExists(np) then
                                        local ids = GetAllHarmfulInstanceIDs(np)
                                        if ids[preservedID] then
                                            dlog("FALSE REMOVAL DETECTED: id=" .. preservedID ..
                                                 " still visible on " .. np .. " after grace window, rebinding")
                                            dreadPlagueInstanceID = preservedID
                                            lastSeenTime = GetTime()
                                            return
                                        end
                                    end
                                end
                                -- Old ID not found anywhere. Check for a NEW DP by spellId.
                                -- This catches the case where the game silently re-issues
                                -- the DP aura with a different instance ID on the same or
                                -- a different mob that still has DP.
                                for npIdx = 1, 40 do
                                    local np = "nameplate" .. npIdx
                                    if UnitExists(np) then
                                        local newID = FindDPInstanceOnUnit(np)
                                        if newID then
                                            dlog("DP RE-IDENTIFIED: new id=" .. newID ..
                                                 " on " .. np .. " (was id=" .. preservedID .. "), rebinding")
                                            dreadPlagueInstanceID = newID
                                            lastSeenTime = GetTime()
                                            plagueData.expiration = GetTime() + 18
                                            plagueData.trackingStart = GetTime()
                                            return
                                        end
                                    end
                                end
                                dlog("NO JUMP: clearing after grace window")
                                ClearPlagueData()
                            end
                            end)
                            if not tOk then
                                dlog("GRACE TIMER ERROR: " .. tostring(tErr) .. " safety clearing")
                                ClearPlagueData()
                            end
                        end)
                    end
                end
                return
            end
        end
        end)
        if not ok then
            dlog("REMOVAL HANDLER ERROR: " .. tostring(err))
        end
    end
    -- updatedAuraInstanceIDs: extensions handled via UNIT_SPELLCAST_SUCCEEDED
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)

    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialize saved variables
        if not DreadPlagueTrackerDB then
            DreadPlagueTrackerDB = CopyTable(DEFAULTS)
        else
            -- Merge any missing defaults into existing saved data
            for k, v in pairs(DEFAULTS) do
                if DreadPlagueTrackerDB[k] == nil then
                    DreadPlagueTrackerDB[k] = v
                end
            end
            -- Merge nested color tables
            for _, colorKey in ipairs({"activeColor", "missingColor"}) do
                if type(DEFAULTS[colorKey]) == "table" then
                    if type(DreadPlagueTrackerDB[colorKey]) ~= "table" then
                        DreadPlagueTrackerDB[colorKey] = CopyTable(DEFAULTS[colorKey])
                    else
                        for ck, cv in pairs(DEFAULTS[colorKey]) do
                            if DreadPlagueTrackerDB[colorKey][ck] == nil then
                                DreadPlagueTrackerDB[colorKey][ck] = cv
                            end
                        end
                    end
                end
            end
        end
        db = DreadPlagueTrackerDB

        -- Initialize log storage
        if not DreadPlagueTrackerLog then
            _G.DreadPlagueTrackerLog = { entries = {} }
        end

        -- Sync legacy global debug flag with saved setting
        _G.DPT_DEBUG_LOG = db.verboseLogging or false

        -- Build the frame
        trackerFrame = BuildTrackerFrame()
        ApplyLayout()

        -- Create minimap button
        DPT_UpdateMinimapButton()

        -- Use a separate dummy frame for OnUpdate so it fires even when
        -- trackerFrame is hidden (OnUpdate doesn't fire on hidden frames)
        local updateDriver = CreateFrame("Frame", nil, UIParent)
        updateDriver:SetScript("OnUpdate", function(self, elapsed)
            UpdateDisplay(elapsed)
        end)

        print("|cff9900ff[DreadPlagueTracker]|r Loaded. Type |cffffffff/dpt help|r for commands.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        if db and trackerFrame then
            ApplyLayout()
            if IsDeathKnight() then
                if InCombatLockdown() or db.showOutOfCombat then
                    StartScanning()
                    trackerFrame:Show()
                else
                    trackerFrame:Hide()
                end
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat: explicitly show frame
        if db and IsDeathKnight() then
            StartScanning()
            if trackerFrame then
                trackerFrame:Show()
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: stop the ticker but keep showing if plague is active
        StopScanning()
        if trackerFrame and not db.showOutOfCombat and not plagueData.active then
            trackerFrame:Hide()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellId = arg1, arg2, arg3
        if unit == "player" then
            -- Track casts of spells that can apply DP (for passive detection gating)
            if spellId == OUTBREAK_SPELL_ID then
                outbreakCastTime = GetTime()
                dpApplyCastTime  = GetTime()
            elseif spellId == PUTREFY_SPELL_ID then
                dpApplyCastTime = GetTime()  -- Putrefy+Blightburst can apply DP
            end
            -- Duration extensions (only apply when DP is actively tracked
            -- AND has been confirmed visible on a real unit recently).
            -- Without the recency check, we'd keep extending a phantom DP
            -- whose host mob died and never got refreshed by the game.
            if plagueData.active and plagueData.expiration and
               lastSeenTime > 0 and (GetTime() - lastSeenTime) < 3 then
                local extension = 0
                if spellId == PUTREFY_SPELL_ID then
                    extension = 4
                elseif spellId == DEATH_COIL_SPELL_ID or spellId == NECROTIC_COIL_SPELL_ID then
                    extension = 1
                elseif spellId == EPIDEMIC_SPELL_ID or spellId == GRAVEYARD_SPELL_ID then
                    extension = 1.5
                end
                if extension > 0 then
                    -- Cap: DP can't have more than 18 * 1.3 = ~24s remaining (Pandemic rule)
                    local cap = GetTime() + 24
                    plagueData.expiration = math.min(plagueData.expiration + extension, cap)
                    dlog("EXTENSION: +" .. string.format("%.1f", extension) .. "s (spell=" ..
                         spellId .. ") expires in " .. string.format("%.1f", plagueData.expiration - GetTime()) .. "s")
                end
            end
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if db then
            if IsDeathKnight() then
                if InCombatLockdown() or db.showOutOfCombat then
                    StartScanning()
                end
            else
                StopScanning()
                if trackerFrame then trackerFrame:Hide() end
            end
        end

    end
end)

-- ============================================================
-- MINIMAP BUTTON
-- Simple self-contained minimap button (no LibDBIcon dependency)
-- Left-click: open settings. Right-click: toggle verbose logging.
-- Drag with shift to reposition around minimap.
-- ============================================================
local minimapButton = nil

local function UpdateMinimapButtonPosition()
    if not minimapButton or not db then return end
    local angle = math.rad(db.minimapAngle or 225)
    local cos, sin = math.cos(angle), math.sin(angle)

    -- Detect if the minimap is round or square by checking its mask texture
    -- BasicMinimap and similar square-mask addons override GetMinimapShape
    local shape = "ROUND"
    if GetMinimapShape then
        shape = GetMinimapShape() or "ROUND"
    end

    local w, h = Minimap:GetWidth(), Minimap:GetHeight()
    local x, y

    if shape == "ROUND" then
        -- Circle: place on radius
        local radius = (w / 2) + 10
        x = cos * radius
        y = sin * radius
    else
        -- Square or other rect shape: clamp the ray from center to the rect edge
        -- Extend slightly outside the minimap (~10px) so the button sits on the border
        local halfW, halfH = (w / 2) + 10, (h / 2) + 10
        -- Scale the unit vector (cos, sin) so it hits the rectangle edge
        local scale
        if math.abs(cos) * halfH > math.abs(sin) * halfW then
            scale = halfW / math.abs(cos)
        else
            scale = halfH / math.abs(sin)
        end
        x = cos * scale
        y = sin * scale
    end

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if minimapButton then return end
    local btn = CreateFrame("Button", "DPTMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetSize(31, 31)
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    -- Background ring (standard minimap button look)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Icon texture (Dread Plague spell icon)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(C_Spell.GetSpellTexture(DREAD_PLAGUE_ID) or "Interface\\Icons\\Spell_Shadow_UnholyFrenzy")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DreadPlagueTracker")
        GameTooltip:AddLine("|cffffffffLeft-click|r: Open settings", 1, 1, 1)
        GameTooltip:AddLine("|cffffffffRight-click|r: Toggle verbose logging", 1, 1, 1)
        GameTooltip:AddLine("|cffffffffShift-drag|r: Reposition", 1, 1, 1)
        if db and db.verboseLogging then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Verbose logging: ON|r")
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Clicks
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            DPT_OpenConfig()
        elseif button == "RightButton" then
            if db then
                db.verboseLogging = not db.verboseLogging
                _G.DPT_DEBUG_LOG = db.verboseLogging
                print("|cff9900ff[DPT]|r Verbose logging: " .. (db.verboseLogging and "ON" or "OFF"))
            end
        end
    end)

    -- Drag to reposition around minimap edge
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.dragging = true
            self:SetScript("OnUpdate", function(s)
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                cx, cy = cx / scale, cy / scale
                local angle = math.deg(math.atan2(cy - my, cx - mx))
                if db then db.minimapAngle = angle end
                UpdateMinimapButtonPosition()
            end)
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton = btn
end

function DPT_UpdateMinimapButton()
    if not db then return end
    if db.minimapHide then
        if minimapButton then minimapButton:Hide() end
    else
        if not minimapButton then CreateMinimapButton() end
        UpdateMinimapButtonPosition()
        minimapButton:Show()
    end
end

-- ============================================================
-- LOG EXPORT WINDOW
-- A scrollable edit box showing the accumulated log so users
-- can copy-paste it for analysis.
-- ============================================================
local logExportFrame = nil
function DPT_ShowLogExport()
    if not DreadPlagueTrackerLog or not DreadPlagueTrackerLog.entries or #DreadPlagueTrackerLog.entries == 0 then
        if IsVerboseLogging() then
            print("|cff9900ff[DPT]|r Log is empty.")
        else
            print("|cff9900ff[DPT]|r Log is empty. Enable verbose logging first.")
        end
        return
    end

    if not logExportFrame then
        local f = CreateFrame("Frame", "DPTLogExportFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 500)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("DIALOG")

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -5)
        f.title:SetText("DreadPlagueTracker - Log Export (Ctrl+A, Ctrl+C to copy)")

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -30)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(640)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.editBox = edit

        local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clearBtn:SetSize(100, 22)
        clearBtn:SetPoint("BOTTOMLEFT", 10, 10)
        clearBtn:SetText("Clear Log")
        clearBtn:SetScript("OnClick", function()
            _G.DreadPlagueTrackerLog = { entries = {} }
            f.editBox:SetText("")
            print("|cff9900ff[DPT]|r Log cleared.")
        end)

        local markBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        markBtn:SetSize(100, 22)
        markBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
        markBtn:SetText("Mark Issue")
        markBtn:SetScript("OnClick", function()
            DPT_DropMarker("USER MARKER (button)")
            DPT_ShowLogExport()  -- refresh
        end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        logExportFrame = f
    end

    -- Populate with current log contents
    local text = table.concat(DreadPlagueTrackerLog.entries, "\n")
    logExportFrame.editBox:SetText(text)
    logExportFrame.editBox:HighlightText(0, 0)  -- deselect
    logExportFrame:Show()
end

-- ============================================================
-- ISSUE REPORTING (markers + keybinding)
-- ============================================================
-- Drop a marker line in the log. Triggered by /dpt mark, /dpt report, the
-- "Insert Marker" button in the export window, or the "Report Issue"
-- keybinding. Used to flag the moment when the tracker fires incorrectly
-- so the maintainer can see exactly which event was the false one.
function DPT_DropMarker(note)
    note = (note and note ~= "") and note or "USER MARKER"
    if not DreadPlagueTrackerLog then
        _G.DreadPlagueTrackerLog = { entries = {} }
    end
    local ts = date("%H:%M:%S") .. string.format(".%03d", math.floor((GetTime() % 1) * 1000))
    local line = ts .. "  ========== " .. note .. " =========="
    table.insert(DreadPlagueTrackerLog.entries, line)
    print("|cff9900ff[DPT]|r Issue marked. Type |cffffffff/dpt export|r after your run to share the log.")
end

-- Bindable key for "Report Issue" (header globals are set at the top of
-- this file so the keybinding UI shows them under a proper section).
function DPT_BindingReport()
    DPT_DropMarker("USER REPORT (keybind)")
end

-- ============================================================
-- SLASH COMMAND
-- ============================================================
SLASH_DPTDEBUGLOG1 = "/dptlog"
SlashCmdList["DPTDEBUGLOG"] = function()
    if db then
        db.verboseLogging = not db.verboseLogging
        _G.DPT_DEBUG_LOG = db.verboseLogging
        print("|cff9900ff[DPT]|r Verbose logging: " .. (db.verboseLogging and "ON" or "OFF"))
    else
        _G.DPT_DEBUG_LOG = not _G.DPT_DEBUG_LOG
        print("|cff9900ff[DPT]|r debug logging: " .. tostring(_G.DPT_DEBUG_LOG))
    end
end

SLASH_DPTDEBUG1 = "/dptdebug"
SlashCmdList["DPTDEBUG"] = function()
    print("|cff9900ff[DPT]|r GetAuraDuration exists: " .. tostring(C_UnitAuras.GetAuraDuration ~= nil))
    if dreadPlagueInstanceID then
        print("|cff9900ff[DPT]|r Tracking instanceID=" .. tostring(dreadPlagueInstanceID) .. " GUID=" .. tostring(dreadPlagueUnitGUID))
        if UnitExists("target") then
            local dur, exp = C_UnitAuras.GetAuraDuration("target", dreadPlagueInstanceID)
            print("|cff9900ff[DPT]|r target GetAuraDuration: dur=" .. tostring(dur) .. " exp=" .. tostring(exp))
        end
        for i = 1, 5 do
            local np = "nameplate"..i
            if UnitExists(np) and UnitGUID(np) == dreadPlagueUnitGUID then
                local dur, exp = C_UnitAuras.GetAuraDuration(np, dreadPlagueInstanceID)
                print("|cff9900ff[DPT]|r "..np.." GetAuraDuration: dur=" .. tostring(dur) .. " exp=" .. tostring(exp))
            end
        end
    else
        print("|cff9900ff[DPT]|r Not tracking any DP instance")
    end
    print("|cff9900ff[DPT]|r plagueData: active=" .. tostring(plagueData.active) .. " exp=" .. tostring(plagueData.expiration))
end

SLASH_DREADPLAGUETRACKER1 = "/dpt"
SlashCmdList["DREADPLAGUETRACKER"] = function(msg)
    msg = (msg or ""):lower():trim()
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "reset" then
        db.x = 0
        db.y = 200
        ApplyLayout()
        print("|cff9900ff[DreadPlagueTracker]|r Position reset.")

    elseif cmd == "mark" or cmd == "report" then
        -- Drop a marker in the log to flag this moment for later review.
        -- Used when the tracker fires incorrectly (e.g. shows missing while
        -- DP is still active on a mob). Pair with /dpt export to share the
        -- log so the maintainer can investigate.
        DPT_DropMarker(rest)

    elseif cmd == "export" then
        -- Show the log in a copyable edit box
        DPT_ShowLogExport()

    elseif cmd == "clear" then
        _G.DreadPlagueTrackerLog = { entries = {} }
        print("|cff9900ff[DPT]|r Log cleared.")

    elseif cmd == "log" then
        -- Toggle verbose logging without opening config
        db.verboseLogging = not db.verboseLogging
        _G.DPT_DEBUG_LOG = db.verboseLogging  -- keep legacy var in sync
        print("|cff9900ff[DPT]|r Verbose logging: " .. (db.verboseLogging and "ON" or "OFF"))

    elseif cmd == "help" or cmd == "?" then
        print("|cff9900ff[DreadPlagueTracker]|r Slash commands:")
        print("  |cffffffff/dpt|r - open settings")
        print("  |cffffffff/dpt reset|r - reset tracker position")
        print("  |cffffffff/dpt log|r - toggle verbose logging")
        print("  |cffffffff/dpt report|r - flag the current moment in the log (alias: /dpt mark)")
        print("  |cffffffff/dpt export|r - export log to share for issue reporting")
        print("  |cffffffff/dpt clear|r - clear the log")
        print("  |cffffffff/dpt help|r - show this help")
        print("|cff9900ffTip:|r Bind a key to 'Report Issue' in Esc -> Key Bindings -> AddOns -> DreadPlagueTracker.")

    else
        -- Open settings panel (defined in DreadPlagueTracker_Config.lua)
        DPT_OpenConfig()
    end
end

-- ============================================================
-- PUBLIC API (used by Config panel)
-- ============================================================
DPT = {}

function DPT.GetDB()
    return db
end

function DPT.ApplyLayout()
    ApplyLayout()
end

function DPT.ResetPosition()
    db.x = 0
    db.y = 200
    ApplyLayout()
end

function DPT.RefreshState()
    -- Called when settings change that affect visibility/scanning
    if not db then return end
    if db.showOutOfCombat and IsDeathKnight() then
        StartScanning()
        if trackerFrame then
            trackerFrame:Show()
        end
    elseif not InCombatLockdown() then
        StopScanning()
        if trackerFrame and not db.showOutOfCombat then
            trackerFrame:Hide()
        end
    end
    ApplyLayout()
end
