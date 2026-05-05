--[[
    DreadPlagueTracker_Config.lua
    Settings panel using AceGUI for reliable rendering in Midnight.
    Opens via /dpt slash command.
]]

local AceGUI = LibStub("AceGUI-3.0")
local configWindow = nil

-- ============================================================
-- SOUND CATALOG: verified IDs from Blizzard's SOUNDKIT table
-- Each entry's id uses SOUNDKIT constants when available for patch safety
-- ============================================================
local SOUND_CHOICES = {
    { id = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,                    name = "Raid Warning" },
    { id = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960,                     name = "Ready Check" },
    { id = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 18019,          name = "Alarm Clock" },
    { id = SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_DEFEATED or 50111,          name = "Boss Defeated" },
    { id = SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 3175,             name = "Auction Bell" },
    { id = SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE or 880,                 name = "Player Invite" },
    { id = SOUNDKIT and SOUNDKIT.LEVEL_UP or 888,                         name = "Level Up" },
    { id = SOUNDKIT and SOUNDKIT.MAP_PING or 3337,                        name = "Map Ping" },
    { id = SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE or 8455,               name = "PvP Ready" },
    { id = SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or 39517,        name = "Legendary Toast" },
}

function DPT_GetSoundChoices()
    return SOUND_CHOICES
end

function DPT_PlaySoundChoice(idx)
    local choice = SOUND_CHOICES[idx]
    if choice then PlaySound(choice.id, "Master") end
end

-- ============================================================
-- HELPER: section heading
-- ============================================================
local function AddHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    container:AddChild(heading)
end

-- ============================================================
-- HELPER: checkbox
-- ============================================================
local function AddCheckbox(container, label, getVal, setVal)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(label)
    cb:SetValue(getVal())
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(_, _, val)
        setVal(val)
        DPT.ApplyLayout()
    end)
    container:AddChild(cb)
end

-- ============================================================
-- HELPER: slider
-- ============================================================
local function AddSlider(container, label, minVal, maxVal, step, getVal, setVal)
    local sl = AceGUI:Create("Slider")
    sl:SetLabel(label)
    sl:SetSliderValues(minVal, maxVal, step)
    sl:SetValue(getVal())
    sl:SetFullWidth(true)
    sl:SetCallback("OnValueChanged", function(_, _, val)
        setVal(val)
        DPT.ApplyLayout()
    end)
    container:AddChild(sl)
end

-- ============================================================
-- HELPER: color picker
-- ============================================================
local function AddColorPicker(container, label, getColor, setColor)
    local cp = AceGUI:Create("ColorPicker")
    cp:SetLabel(label)
    local c = getColor()
    cp:SetColor(c.r, c.g, c.b, c.a)
    cp:SetHasAlpha(true)
    cp:SetRelativeWidth(0.5)
    cp:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        setColor({ r=r, g=g, b=b, a=a })
        DPT.ApplyLayout()
    end)
    container:AddChild(cp)
end

-- ============================================================
-- HELPER: sound dropdown using native Blizzard UIDropDownMenu
-- Wrapped in a Label widget so AceGUI can place it in the layout
-- ============================================================
local function AddSoundDropdown(container, getVal, setVal)
    -- Label above the dropdown
    local label = AceGUI:Create("Label")
    label:SetText("Sound Choice")
    label:SetFullWidth(true)
    container:AddChild(label)

    -- Use a SimpleGroup as a host for the dropdown frame
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetHeight(32)
    group:SetLayout("Fill")
    container:AddChild(group)

    -- Create a dropdown inside the group's frame
    local dd = CreateFrame("Frame", "DPTSoundDropdown" .. tostring(GetTime()), group.frame, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", group.frame, "LEFT", -10, -2)

    local function OnClick(self, arg1)
        setVal(arg1)
        UIDropDownMenu_SetSelectedID(dd, arg1)
        DPT_PlaySoundChoice(arg1)
    end

    UIDropDownMenu_Initialize(dd, function(self)
        for i, choice in ipairs(SOUND_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice.name
            info.arg1 = i
            info.func = OnClick
            info.checked = (i == getVal())
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetWidth(dd, 180)
    UIDropDownMenu_SetSelectedID(dd, getVal() or 1)
end

-- ============================================================
-- HELPER: display mode radio (using checkboxes as toggles)
-- ============================================================
local function AddModeSelector(container, getVal, setVal)
    local iconCb = AceGUI:Create("CheckBox")
    iconCb:SetLabel("Icon Mode")
    iconCb:SetRelativeWidth(0.5)

    local function Refresh()
        iconCb:SetValue(true)  -- only mode supported now
    end

    iconCb:SetCallback("OnValueChanged", function()
        setVal("icon")
        Refresh()
        DPT.ApplyLayout()
    end)

    Refresh()
    container:AddChild(iconCb)
end

-- ============================================================
-- BUILD CONFIG WINDOW
-- ============================================================
local function BuildConfig()
    local db = DPT.GetDB()

    local win = AceGUI:Create("Frame")
    win:SetTitle("DreadPlagueTracker Settings")
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DreadPlagueTracker", "Version") or "?"
    win:SetStatusText("v" .. version .. " | Created by Tuukka - Burning Legion")
    win:SetWidth(460)
    win:SetHeight(620)
    win:SetLayout("Fill")
    win:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        configWindow = nil
    end)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    win:AddChild(scroll)

    -- ---- ICON SETTINGS ----
    AddHeading(scroll, "Icon Settings")
    AddSlider(scroll, "Icon Size", 24, 64, 2,
        function() return db.iconSize end,
        function(v) db.iconSize = v end)

    -- ---- APPEARANCE ----
    AddHeading(scroll, "Appearance")
    AddCheckbox(scroll, "Show Label Text",
        function() return db.showEnemyName end,
        function(v) db.showEnemyName = v end)
    AddSlider(scroll, "Background Opacity", 0, 100, 5,
        function() return math.floor(db.bgOpacity * 100) end,
        function(v) db.bgOpacity = v / 100 end)

    -- ---- COLORS ----
    AddHeading(scroll, "Colors")
    AddColorPicker(scroll, "Active Color",
        function() return db.activeColor end,
        function(c) db.activeColor.r=c.r; db.activeColor.g=c.g; db.activeColor.b=c.b; db.activeColor.a=c.a end)
    AddColorPicker(scroll, "Missing Color",
        function() return db.missingColor end,
        function(c) db.missingColor.r=c.r; db.missingColor.g=c.g; db.missingColor.b=c.b; db.missingColor.a=c.a end)

    -- ---- BEHAVIOR ----
    AddHeading(scroll, "Behavior")
    AddCheckbox(scroll, "Flash When Missing (in combat)",
        function() return db.flashWhenMissing end,
        function(v) db.flashWhenMissing = v end)
    AddSlider(scroll, "Flash Speed", 1, 10, 1,
        function() return math.floor(db.flashSpeed * 2) end,
        function(v) db.flashSpeed = v / 2 end)
    AddCheckbox(scroll, "Play Sound When Missing",
        function() return db.soundOnMissing end,
        function(v) db.soundOnMissing = v end)
    AddSoundDropdown(scroll,
        function() return db.soundChoice or 1 end,
        function(v) db.soundChoice = v end)
    AddCheckbox(scroll, "Show Out of Combat (for positioning)",
        function() return db.showOutOfCombat end,
        function(v) db.showOutOfCombat = v; DPT.RefreshState() end)

    -- ---- MINIMAP ----
    AddHeading(scroll, "Minimap")
    AddCheckbox(scroll, "Show Minimap Button",
        function() return not db.minimapHide end,
        function(v)
            db.minimapHide = not v
            if DPT_UpdateMinimapButton then DPT_UpdateMinimapButton() end
        end)

    -- ---- DIAGNOSTICS ----
    AddHeading(scroll, "Diagnostics")
    AddCheckbox(scroll, "Verbose Logging (for bug reports)",
        function() return db.verboseLogging end,
        function(v)
            db.verboseLogging = v
            _G.DPT_DEBUG_LOG = v  -- keep legacy flag in sync
        end)

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("View / Export Log")
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        if DPT_ShowLogExport then DPT_ShowLogExport() end
    end)
    scroll:AddChild(exportBtn)

    local clearLogBtn = AceGUI:Create("Button")
    clearLogBtn:SetText("Clear Log")
    clearLogBtn:SetFullWidth(true)
    clearLogBtn:SetCallback("OnClick", function()
        _G.DreadPlagueTrackerLog = { entries = {} }
        print("|cff9900ff[DreadPlagueTracker]|r Log cleared.")
    end)
    scroll:AddChild(clearLogBtn)

    -- ---- RESET POSITION ----
    AddHeading(scroll, "Position")
    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText("Reset Tracker Position")
    resetBtn:SetFullWidth(true)
    resetBtn:SetCallback("OnClick", function()
        DPT.ResetPosition()
        print("|cff9900ff[DreadPlagueTracker]|r Position reset.")
    end)
    scroll:AddChild(resetBtn)

    configWindow = win
end

-- ============================================================
-- PUBLIC OPEN FUNCTION
-- ============================================================
function DPT_OpenConfig()
    if configWindow then
        configWindow:Hide()
        AceGUI:Release(configWindow)
        configWindow = nil
        return
    end
    BuildConfig()
end
