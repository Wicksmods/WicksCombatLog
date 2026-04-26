local ADDON, ns = ...

local UI = {}
ns.UI = UI

-- Wick brand palette — see memory/reference_wick_brand_style.md
-- Fel #4FC778 · Void #0D0A14 · Shadow #171124 · Border #383058 · Text #D4C8A1
local C_BG          = { 0.051, 0.039, 0.078, 0.97 }
local C_HEADER_BG   = { 0.090, 0.067, 0.141, 1 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.500, 0.460, 0.360, 1 }
local C_ROW_ALT     = { 0.090, 0.067, 0.141, 0.45 }

local BRACKET    = 10
local HEADER_H   = 32
local FILTER_H   = 28
local STATUS_H   = 16
local ROW_H      = 16
local PAD        = 6
local SLIDER_W   = 14
local DEFAULT_W, DEFAULT_H = 760, 440
local MIN_W, MIN_H         = 540, 260

local FAMILIES = { "damage", "heal", "aura", "cast", "misc" }
local FAMILY_LABELS = { damage = "Damage", heal = "Heal", aura = "Aura", cast = "Cast", misc = "Misc" }
local SOURCES = { "anyone", "mine", "pet", "hostile", "target" }
local SOURCE_LABELS = { anyone = "Anyone", mine = "Mine", pet = "My Pet", hostile = "Hostile", target = "Target" }

local frame
local listArea
local rows = {}
local slider
local sliderOffset = 0
local statusText
local pauseBtn
local familyBtns = {}
local sourceBtn
local searchBox
local UI_dirty = true
local cachedFiltered     -- last computed filtered list (newest-first)
local cachedAtCount = -1

local function newTex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function addBorder(f)
    local top   = newTex(f, "BORDER", C_BORDER); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
    local bot   = newTex(f, "BORDER", C_BORDER); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local lf    = newTex(f, "BORDER", C_BORDER); lf:SetPoint("TOPLEFT");     lf:SetPoint("BOTTOMLEFT");   lf:SetWidth(1)
    local rt    = newTex(f, "BORDER", C_BORDER); rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT");  rt:SetWidth(1)
end

local function addCornerAccents(parent, resizeButton)
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local host = (point == "BOTTOMRIGHT") and resizeButton or parent
        local h = host:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(unpack(C_GREEN))
        h:SetPoint(point, host, point, 0, 0)
        h:SetSize(BRACKET, 2)
        local v = host:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(unpack(C_GREEN))
        v:SetPoint(point, host, point, 0, 0)
        v:SetSize(2, BRACKET)
    end
end

local function formatTimestamp(ts)
    if not ts then return "--:--:--.---" end
    local secs = math.floor(ts)
    local ms   = math.floor((ts - secs) * 1000)
    return string.format("%s.%03d", date("%H:%M:%S", secs), ms)
end

local function displayName(name)
    if not name or name == "" then return "—" end
    return name:match("^([^-]+)") or name
end

-- Per-GUID class cache. GetPlayerInfoByGUID returns nil for players the
-- client hasn't seen yet; we re-attempt on misses but stick with the first
-- successful lookup forever after.
local classCache       = {}
local TYPE_PLAYER_BIT  = COMBATLOG_OBJECT_TYPE_PLAYER     or 0x00000400
local REACT_HOSTILE_UI = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local HOSTILE_HEX      = "ffe05050"  -- desaturated red for non-player hostiles

local function classOf(guid)
    if not guid then return nil end
    local cached = classCache[guid]
    if cached then return cached end
    local _, class = GetPlayerInfoByGUID(guid)
    if class then classCache[guid] = class end
    return class
end

local function colorActor(name, guid, flags)
    local stripped = displayName(name)
    if not flags then return stripped end
    -- Player → class color.
    if bit.band(flags, TYPE_PLAYER_BIT) ~= 0 then
        local class = classOf(guid)
        if class then
            local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if cc then
                return string.format("|cff%02x%02x%02x%s|r",
                    cc.r * 255, cc.g * 255, cc.b * 255, stripped)
            end
        end
    end
    -- Non-player hostile → red.
    if bit.band(flags, REACT_HOSTILE_UI) ~= 0 then
        return "|c" .. HOSTILE_HEX .. stripped .. "|r"
    end
    return stripped
end

local function formatAmount(n)
    if not n then return "" end
    if n >= 1000000 then return string.format("%.1fM", n / 1e6) end
    if n >= 10000   then return string.format("%.1fk", n / 1e3) end
    return tostring(n)
end

-- A small clickable text button that toggles a fel-green "active" tint.
local function makeToggleBtn(parent, label, isActive, onClick)
    local btn = CreateFrame("Button", nil, parent)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    fs:SetText(label)
    fs:SetPoint("CENTER")
    btn.text = fs
    btn:SetSize(fs:GetStringWidth() + 14, FILTER_H - 10)
    local function paint(active)
        if active then
            fs:SetTextColor(unpack(C_GREEN))
        else
            fs:SetTextColor(unpack(C_TEXT_DIM))
        end
    end
    btn.SetActive = function(_, v) btn.active = v; paint(v) end
    btn:SetScript("OnClick", function() onClick(btn) end)
    btn:SetScript("OnEnter", function() if not btn.active then fs:SetTextColor(unpack(C_TEXT_NORMAL)) end end)
    btn:SetScript("OnLeave", function() paint(btn.active) end)
    btn:SetActive(isActive)
    return btn
end

-- One row in the event list. Columns: timestamp, subevent, src→dst, spell, amount.
local function makeRow(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    local stripe = newTex(row, "BACKGROUND", C_ROW_ALT)
    stripe:SetAllPoints()
    stripe:Hide()
    row.stripe = stripe

    local hover = newTex(row, "BACKGROUND")
    hover:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.12)
    hover:SetAllPoints()
    hover:Hide()
    row.hover = hover

    local function fs(width, justify)
        local t = row:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\ARIALN.TTF", 11, "")
        t:SetTextColor(unpack(C_TEXT_NORMAL))
        if width then t:SetWidth(width) end
        t:SetWordWrap(false)
        t:SetJustifyH(justify or "LEFT")
        return t
    end

    row.ts     = fs(nil, "LEFT")
    row.sub    = fs(nil, "LEFT")
    row.srcDst = fs(nil, "LEFT")
    row.spell  = fs(nil, "LEFT")
    row.amount = fs(nil, "RIGHT")

    row.ts:SetPoint("LEFT", 4, 0)
    row.sub:SetPoint("LEFT", row.ts, "RIGHT", 4, 0)
    row.amount:SetPoint("RIGHT", -4, 0)
    row.spell:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
    row.srcDst:SetPoint("LEFT", row.sub, "RIGHT", 4, 0)
    row.srcDst:SetPoint("RIGHT", row.spell, "LEFT", -4, 0)

    -- Proportional column widths: ts/sub/spell/amount each get a percentage
    -- of the row's content width, and srcDst absorbs whatever's left via its
    -- dual LEFT+RIGHT anchors. Re-applied on every row resize so dragging
    -- the panel narrower shrinks every column together.
    local function layout(self)
        local w = self:GetWidth() - 20   -- 4px pad each side + four 4px gaps
        if w <= 60 then return end
        self.ts:SetWidth(w * 0.11)
        self.sub:SetWidth(w * 0.14)
        self.spell:SetWidth(w * 0.22)
        self.amount:SetWidth(w * 0.08)
    end
    row:SetScript("OnSizeChanged", layout)
    layout(row)

    row:SetScript("OnEnter", function() row.hover:Show() end)
    row:SetScript("OnLeave", function() row.hover:Hide() end)
    row:SetScript("OnClick", function()
        if row.eventId and ns.Detail then ns.Detail:Show(row.eventId) end
    end)

    return row
end

local function ensureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "WicksCombatLogFrame", UIParent)
    frame:SetSize(DEFAULT_W, DEFAULT_H)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H) end
    frame:EnableMouse(true)

    local bg = newTex(frame, "BACKGROUND", C_BG); bg:SetAllPoints()
    addBorder(frame)

    -- Header strip ---- canonical Wick suite spec ---------------------------
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)

    local headerBG = newTex(header, "BACKGROUND", C_HEADER_BG); headerBG:SetAllPoints()

    local headerLine = newTex(header, "BORDER")
    headerLine:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.35)
    headerLine:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  40, 0)
    headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -40, 0)
    headerLine:SetHeight(1)

    local headerBot = newTex(header, "BORDER", C_BORDER)
    headerBot:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
    headerBot:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBot:SetHeight(1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetText("|cff4FC778Wick's|r |cffD4C8A1Combat Log|r")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    local closeBG = newTex(closeBtn, "BACKGROUND", C_HEADER_BG); closeBG:SetAllPoints()
    addBorder(closeBtn)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
    closeX:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    closeX:SetText("✕")
    closeX:SetTextColor(unpack(C_TEXT_DIM))
    closeX:SetAllPoints()
    closeX:SetJustifyH("CENTER"); closeX:SetJustifyV("MIDDLE")
    closeBtn:SetScript("OnEnter", function() closeX:SetTextColor(1, 0.3, 0.3, 1) end)
    closeBtn:SetScript("OnLeave", function() closeX:SetTextColor(unpack(C_TEXT_DIM)) end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Drag is header-only (per canonical spec) — frame body stays clickable
    -- for row interactions and the resize grip.
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop",  function()
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        WCLSettings = WCLSettings or {}
        WCLSettings.pos = { p, rp, x, y }
        WCLSettings.size = { frame:GetWidth(), frame:GetHeight() }
    end)

    -- Filter bar ------------------------------------------------------------
    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", 1, -HEADER_H - 1)
    filterBar:SetPoint("TOPRIGHT", -1, -HEADER_H - 1)
    filterBar:SetHeight(FILTER_H)

    local fbBg = newTex(filterBar, "BACKGROUND", C_HEADER_BG); fbBg:SetAllPoints()
    local fbSep = newTex(filterBar, "ARTWORK", C_BORDER)
    fbSep:SetPoint("BOTTOMLEFT"); fbSep:SetPoint("BOTTOMRIGHT"); fbSep:SetHeight(1)

    -- Pause / resume button. Toggles ns.paused.
    pauseBtn = makeToggleBtn(filterBar, "▮▮ Pause", false, function(b)
        ns.TogglePaused()
    end)
    pauseBtn:SetPoint("LEFT", PAD, 0)

    -- Family checkboxes
    local prev = pauseBtn
    for _, fam in ipairs(FAMILIES) do
        local btn = makeToggleBtn(filterBar, FAMILY_LABELS[fam], ns.filters.families[fam], function(b)
            ns.filters.families[fam] = not ns.filters.families[fam]
            b:SetActive(ns.filters.families[fam])
            WCLSettings = WCLSettings or {}; WCLSettings.filters = ns.filters
            UI_dirty = true
        end)
        btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        familyBtns[fam] = btn
        prev = btn
    end

    -- Source filter (click cycles)
    local function sourceLabel() return "Source: " .. SOURCE_LABELS[ns.filters.source] end
    sourceBtn = CreateFrame("Button", nil, filterBar)
    local sFs = sourceBtn:CreateFontString(nil, "OVERLAY")
    sFs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    sFs:SetTextColor(unpack(C_TEXT_NORMAL))
    sFs:SetPoint("CENTER")
    sFs:SetText(sourceLabel())
    sourceBtn:SetSize(110, FILTER_H - 10)
    sourceBtn:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    sourceBtn:SetScript("OnClick", function()
        local idx = 1
        for i, s in ipairs(SOURCES) do if s == ns.filters.source then idx = i; break end end
        ns.filters.source = SOURCES[(idx % #SOURCES) + 1]
        sFs:SetText(sourceLabel())
        WCLSettings = WCLSettings or {}; WCLSettings.filters = ns.filters
        UI_dirty = true
    end)
    sourceBtn:SetScript("OnEnter", function() sFs:SetTextColor(unpack(C_GREEN)) end)
    sourceBtn:SetScript("OnLeave", function() sFs:SetTextColor(unpack(C_TEXT_NORMAL)) end)

    -- Clear button (right-aligned). Created before searchBox so the search
    -- box can flex into the space between the source button and Clear.
    local clearBtn = makeToggleBtn(filterBar, "Clear", false, function() ns.ClearBuffer() end)
    clearBtn:SetPoint("RIGHT", -PAD, 0)
    clearBtn.SetActive = function() end -- no toggle state

    -- Spell-name search — flexes to fill the gap between Source and Clear.
    searchBox = CreateFrame("EditBox", nil, filterBar)
    searchBox:SetPoint("LEFT", sourceBtn, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
    searchBox:SetHeight(FILTER_H - 12)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetTextColor(unpack(C_TEXT_NORMAL))
    searchBox:SetMaxLetters(40)
    local sbBg = newTex(searchBox, "BACKGROUND", C_BG); sbBg:SetAllPoints()
    addBorder(searchBox)
    searchBox:SetTextInsets(6, 6, 0, 0)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    placeholder:SetTextColor(unpack(C_TEXT_DIM))
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("spell name…")
    searchBox.placeholder = placeholder
    searchBox:SetScript("OnTextChanged", function(self)
        ns.filters.spellMatch = self:GetText() or ""
        placeholder:SetShown(self:GetText() == "")
        WCLSettings = WCLSettings or {}; WCLSettings.filters = ns.filters
        UI_dirty = true
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Status bar (bottom) ---------------------------------------------------
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetPoint("BOTTOMLEFT", 1, 1); statusBar:SetPoint("BOTTOMRIGHT", -1, 1); statusBar:SetHeight(STATUS_H)
    local stBg = newTex(statusBar, "BACKGROUND", C_HEADER_BG); stBg:SetAllPoints()
    local stSep = newTex(statusBar, "ARTWORK", C_BORDER)
    stSep:SetPoint("TOPLEFT"); stSep:SetPoint("TOPRIGHT"); stSep:SetHeight(1)
    statusText = statusBar:CreateFontString(nil, "OVERLAY")
    statusText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    statusText:SetTextColor(unpack(C_TEXT_DIM))
    statusText:SetPoint("LEFT", 8, 0)
    statusText:SetText("0 events")

    -- List area + slider ---------------------------------------------------
    listArea = CreateFrame("Frame", nil, frame)
    listArea:SetPoint("TOPLEFT", 1, -HEADER_H - FILTER_H - 1)
    listArea:SetPoint("BOTTOMRIGHT", -SLIDER_W - 1, STATUS_H + 1)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        sliderOffset = math.max(0, sliderOffset - delta * 3)
        slider:SetValue(sliderOffset)
        UI_dirty = true
    end)

    slider = CreateFrame("Slider", nil, frame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPRIGHT", -2, -HEADER_H - FILTER_H - 16)
    slider:SetPoint("BOTTOMRIGHT", -2, STATUS_H + 16)
    slider:SetWidth(SLIDER_W)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, v)
        sliderOffset = math.floor(v + 0.5)
        UI_dirty = true
    end)

    -- Resize grip (BOTTOMRIGHT) acts as Wick's BR L-bracket too.
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(BRACKET, BRACKET)
    resizeBtn:SetPoint("BOTTOMRIGHT")
    resizeBtn:EnableMouse(true)
    resizeBtn:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        WCLSettings = WCLSettings or {}
        WCLSettings.size = { frame:GetWidth(), frame:GetHeight() }
        UI_dirty = true
    end)

    addCornerAccents(frame, resizeBtn)

    if WCLSettings and WCLSettings.pos then
        local p, rp, x, y = unpack(WCLSettings.pos)
        frame:ClearAllPoints()
        frame:SetPoint(p, UIParent, rp, x, y)
    end
    if WCLSettings and WCLSettings.size then
        frame:SetSize(unpack(WCLSettings.size))
    end

    return frame
end

-- Recompute the filtered (newest-first) list. Cheap when nothing has changed
-- since the last call — uses ns.eventCount as a coarse cache key. Filter
-- toggles set UI_dirty + invalidate the cache by bumping cachedAtCount.
local function rebuildFiltered()
    cachedFiltered = {}
    local f = ns.filters
    ns.IterEventsNewest(function(ev)
        if ns.PassesFilters(ev) then
            cachedFiltered[#cachedFiltered + 1] = ev
        end
    end)
    cachedAtCount = ns.eventCount
end

local function visibleRowCount()
    local h = listArea:GetHeight()
    return math.max(1, math.floor(h / ROW_H))
end

local function ensureRows(n)
    for i = 1, n do
        if not rows[i] then
            local row = makeRow(listArea, i)
            row:SetPoint("TOPLEFT", 2, -(i - 1) * ROW_H)
            row:SetPoint("RIGHT", 0, 0)
            rows[i] = row
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

-- Subevent → compact display label. Keeps the canonical name available in the
-- Detail panel; the row column gets a quieter, scan-friendly version.
local SUBEVENT_PRETTY = {
    SPELL_DAMAGE              = "damage",
    SPELL_PERIODIC_DAMAGE     = "tick dmg",
    SPELL_BUILDING_DAMAGE     = "damage",
    RANGE_DAMAGE              = "ranged",
    SWING_DAMAGE              = "swing",
    SWING_DAMAGE_LANDED       = "swing",
    ENVIRONMENTAL_DAMAGE      = "envir.",
    SPELL_HEAL                = "heal",
    SPELL_PERIODIC_HEAL       = "tick heal",
    SPELL_MISSED              = "missed",
    SPELL_PERIODIC_MISSED     = "tick missed",
    SWING_MISSED              = "swing missed",
    RANGE_MISSED              = "ranged missed",
    SPELL_AURA_APPLIED        = "aura on",
    SPELL_AURA_REMOVED        = "aura off",
    SPELL_AURA_REFRESH        = "aura refresh",
    SPELL_AURA_APPLIED_DOSE   = "aura +stack",
    SPELL_AURA_REMOVED_DOSE   = "aura -stack",
    SPELL_AURA_BROKEN         = "aura broken",
    SPELL_AURA_BROKEN_SPELL   = "aura broken",
    SPELL_CAST_START          = "cast start",
    SPELL_CAST_SUCCESS        = "cast",
    SPELL_CAST_FAILED         = "cast failed",
    SPELL_INTERRUPT           = "interrupt",
    SPELL_DISPEL              = "dispel",
    SPELL_DISPEL_FAILED       = "dispel failed",
    SPELL_STOLEN              = "stolen",
    SPELL_INSTAKILL           = "instakill",
    SPELL_ENERGIZE            = "energize",
    SPELL_PERIODIC_ENERGIZE   = "tick energize",
    SPELL_DRAIN               = "drain",
    SPELL_LEECH               = "leech",
    SPELL_DURABILITY_DAMAGE   = "durability",
    SPELL_DURABILITY_DAMAGE_ALL = "durability all",
    UNIT_DIED                 = "died",
    UNIT_DESTROYED            = "destroyed",
    UNIT_DISSIPATES           = "dissipates",
    PARTY_KILL                = "killing blow",
    ENCHANT_APPLIED           = "enchant on",
    ENCHANT_REMOVED           = "enchant off",
}

local function prettifySubevent(sub)
    if not sub then return "" end
    return SUBEVENT_PRETTY[sub] or sub:lower():gsub("_", " ")
end

function UI:Refresh()
    ensureFrame()
    rebuildFiltered()
    local total = #cachedFiltered

    -- Slider range: 0 (newest at top) to total - visibleN (oldest visible).
    local visN = visibleRowCount()
    local maxOffset = math.max(0, total - visN)
    slider:SetMinMaxValues(0, maxOffset)
    if sliderOffset > maxOffset then sliderOffset = maxOffset; slider:SetValue(sliderOffset) end

    ensureRows(visN)

    for i = 1, visN do
        local row = rows[i]
        local ev = cachedFiltered[sliderOffset + i]
        if ev then
            row.eventId = ev.id
            row.stripe:SetShown(i % 2 == 0)
            row.ts:SetText(formatTimestamp(ev.ts))
            row.sub:SetText(prettifySubevent(ev.sub))
            row.sub:SetTextColor(unpack(C_TEXT_DIM))

            local sd = string.format("%s → %s",
                colorActor(ev.sourceName, ev.sourceGUID, ev.sourceFlags),
                colorActor(ev.destName,   ev.destGUID,   ev.destFlags))
            row.srcDst:SetText(sd)
            row.spell:SetText(ev.spellName or "")
            row.amount:SetText(formatAmount(ev.amount))
            row:Show()
        else
            row.eventId = nil
            row:Hide()
        end
    end

    statusText:SetText(string.format(
        "%d shown · %d buffered%s",
        total,
        math.min(ns.eventCount, ns.MAX_BUFFER),
        ns.paused and " · |cffff8866PAUSED|r" or ""
    ))
end

function UI:Toggle()
    ensureFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UI_dirty = true
        UI:Refresh()
    end
end

function UI:ResetPosition()
    ensureFrame()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:SetSize(DEFAULT_W, DEFAULT_H)
    WCLSettings = WCLSettings or {}
    WCLSettings.pos = nil
    WCLSettings.size = nil
end

function UI.OnEventCaptured()  UI_dirty = true end
function UI.OnBufferCleared()  sliderOffset = 0; cachedFiltered = nil; UI_dirty = true end
function UI.OnPauseChanged()
    if pauseBtn then
        pauseBtn:SetActive(ns.paused)
        pauseBtn.text:SetText(ns.paused and "▶ Resume" or "▮▮ Pause")
    end
    UI_dirty = true
end

-- Throttled refresh ticker. CLEU fires constantly; we cap UI updates at ~10/s.
local ticker = CreateFrame("Frame")
local accum = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + elapsed
    if accum < 0.1 then return end
    accum = 0
    if UI_dirty and frame and frame:IsShown() then
        UI_dirty = false
        UI:Refresh()
    end
end)
