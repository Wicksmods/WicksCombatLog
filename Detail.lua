local ADDON, ns = ...

local Detail = {}
ns.Detail = Detail

local C_BG          = { 0.051, 0.039, 0.078, 0.97 }
local C_HEADER_BG   = { 0.090, 0.067, 0.141, 1 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.500, 0.460, 0.360, 1 }

local BRACKET  = 10
local HEADER_H = 22
local PANEL_W  = 320
local LINE_H   = 14

-- Subevent-suffix → field-name list (positions are relative to args[12+] for
-- SPELL_/RANGE_-prefixed events, or args[12+] for SWING_/ENVIRONMENTAL_ events).
-- Anything beyond the listed names falls back to "arg[N]".
local SUFFIX_FIELDS = {
    -- Generic spell suffix order: spellId, spellName, spellSchool, then ...
    DAMAGE              = { "spellId", "spellName", "spellSchool", "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" },
    DAMAGE_LANDED       = { "spellId", "spellName", "spellSchool", "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" },
    MISSED              = { "spellId", "spellName", "spellSchool", "missType", "isOffHand", "amountMissed" },
    HEAL                = { "spellId", "spellName", "spellSchool", "amount", "overhealing", "absorbed", "critical" },
    ENERGIZE            = { "spellId", "spellName", "spellSchool", "amount", "overEnergize", "powerType", "alternatePowerType" },
    DRAIN               = { "spellId", "spellName", "spellSchool", "amount", "powerType", "extraAmount" },
    LEECH               = { "spellId", "spellName", "spellSchool", "amount", "powerType", "extraAmount" },
    INTERRUPT           = { "spellId", "spellName", "spellSchool", "extraSpellId", "extraSpellName", "extraSchool" },
    DISPEL              = { "spellId", "spellName", "spellSchool", "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    DISPEL_FAILED       = { "spellId", "spellName", "spellSchool", "extraSpellId", "extraSpellName", "extraSchool" },
    STOLEN              = { "spellId", "spellName", "spellSchool", "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    AURA_APPLIED        = { "spellId", "spellName", "spellSchool", "auraType" },
    AURA_REMOVED        = { "spellId", "spellName", "spellSchool", "auraType" },
    AURA_REFRESH        = { "spellId", "spellName", "spellSchool", "auraType" },
    AURA_APPLIED_DOSE   = { "spellId", "spellName", "spellSchool", "auraType", "amount" },
    AURA_REMOVED_DOSE   = { "spellId", "spellName", "spellSchool", "auraType", "amount" },
    AURA_BROKEN         = { "spellId", "spellName", "spellSchool", "auraType" },
    AURA_BROKEN_SPELL   = { "spellId", "spellName", "spellSchool", "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    CAST_START          = { "spellId", "spellName", "spellSchool" },
    CAST_SUCCESS        = { "spellId", "spellName", "spellSchool" },
    CAST_FAILED         = { "spellId", "spellName", "spellSchool", "failedType" },
    INSTAKILL           = { "spellId", "spellName", "spellSchool" },
    DURABILITY_DAMAGE   = { "spellId", "spellName", "spellSchool" },
    DURABILITY_DAMAGE_ALL = { "spellId", "spellName", "spellSchool" },
}

-- Subevent-specific fields with no SPELL_ prefix.
local STANDALONE_FIELDS = {
    SWING_DAMAGE         = { "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" },
    SWING_DAMAGE_LANDED  = { "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" },
    SWING_MISSED         = { "missType", "isOffHand", "amountMissed" },
    ENVIRONMENTAL_DAMAGE = { "environmentalType", "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" },
    ENCHANT_APPLIED      = { "spellName", "itemID", "itemName" },
    ENCHANT_REMOVED      = { "spellName", "itemID", "itemName" },
    PARTY_KILL           = {},
    UNIT_DIED            = {},
    UNIT_DESTROYED       = {},
    UNIT_DISSIPATES      = {},
}

local function suffixFor(sub)
    local fields = STANDALONE_FIELDS[sub]
    if fields then return fields end
    -- Strip SPELL_/SPELL_PERIODIC_/SPELL_BUILDING_/RANGE_ prefix and look up
    -- the remainder in SUFFIX_FIELDS.
    local rem = sub:match("^SPELL_PERIODIC_(.+)$")
              or sub:match("^SPELL_BUILDING_(.+)$")
              or sub:match("^SPELL_(.+)$")
              or sub:match("^RANGE_(.+)$")
    if rem and SUFFIX_FIELDS[rem] then return SUFFIX_FIELDS[rem] end
    return nil
end

local function formatValue(v)
    if v == nil then return "|cff706a55nil|r" end
    local t = type(v)
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        -- Heuristic: large integers that look like flags render also in hex.
        if math.floor(v) == v and v >= 0x100 then
            return string.format("%d  |cff706a55(0x%X)|r", v, v)
        end
        return tostring(v)
    end
    return tostring(v)
end

local panel
local lines = {}
local titleFs
local subtitleFs

local function newTex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function addBorder(f)
    local top = newTex(f, "BORDER", C_BORDER); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
    local bot = newTex(f, "BORDER", C_BORDER); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local lf  = newTex(f, "BORDER", C_BORDER); lf:SetPoint("TOPLEFT");     lf:SetPoint("BOTTOMLEFT");   lf:SetWidth(1)
    local rt  = newTex(f, "BORDER", C_BORDER); rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT");  rt:SetWidth(1)
end

local function addCornerAccents(parent)
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local h = parent:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(unpack(C_GREEN))
        h:SetPoint(point, parent, point, 0, 0)
        h:SetSize(BRACKET, 2)
        local v = parent:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(unpack(C_GREEN))
        v:SetPoint(point, parent, point, 0, 0)
        v:SetSize(2, BRACKET)
    end
end

local function ensurePanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "WicksCombatLogDetail", UIParent)
    panel:SetSize(PANEL_W, 440)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel:SetFrameStrata("MEDIUM")

    -- Anchor to the main frame's right edge if it exists, otherwise CENTER.
    local mainFrame = _G.WicksCombatLogFrame
    if mainFrame then
        panel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 4, 0)
        panel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMRIGHT", 4, 0)
    else
        panel:SetPoint("CENTER")
    end

    local bg = newTex(panel, "BACKGROUND", C_BG); bg:SetAllPoints()
    addBorder(panel)

    -- Header
    local header = newTex(panel, "ARTWORK", C_HEADER_BG)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(HEADER_H)
    local hSep = newTex(panel, "ARTWORK", C_BORDER)
    hSep:SetPoint("TOPLEFT", 1, -HEADER_H - 1); hSep:SetPoint("TOPRIGHT", -1, -HEADER_H - 1); hSep:SetHeight(1)

    titleFs = panel:CreateFontString(nil, "OVERLAY")
    titleFs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    titleFs:SetTextColor(unpack(C_TEXT_NORMAL))
    titleFs:SetPoint("LEFT", panel, "TOPLEFT", 10, -HEADER_H / 2)
    titleFs:SetText("Event Detail")

    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(HEADER_H - 4, HEADER_H - 4)
    closeBtn:SetPoint("RIGHT", panel, "TOPRIGHT", -4, -HEADER_H / 2)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    closeText:SetTextColor(unpack(C_TEXT_NORMAL))
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(unpack(C_GREEN)) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(unpack(C_TEXT_NORMAL)) end)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Subtitle row (event id + subevent)
    subtitleFs = panel:CreateFontString(nil, "OVERLAY")
    subtitleFs:SetFont("Fonts\\ARIALN.TTF", 11, "")
    subtitleFs:SetTextColor(unpack(C_GREEN))
    subtitleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEADER_H - 6)

    addCornerAccents(panel)
    return panel
end

local function ensureLines(n)
    for i = 1, n do
        if not lines[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(PANEL_W - 16, LINE_H)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(HEADER_H + 28 + (i - 1) * LINE_H))

            local k = row:CreateFontString(nil, "OVERLAY")
            k:SetFont("Fonts\\ARIALN.TTF", 11, "")
            k:SetTextColor(unpack(C_TEXT_DIM))
            k:SetPoint("LEFT", 0, 0)
            k:SetWidth(120); k:SetJustifyH("LEFT"); k:SetWordWrap(false)
            row.key = k

            local v = row:CreateFontString(nil, "OVERLAY")
            v:SetFont("Fonts\\ARIALN.TTF", 11, "")
            v:SetTextColor(unpack(C_TEXT_NORMAL))
            v:SetPoint("LEFT", k, "RIGHT", 4, 0)
            v:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            v:SetJustifyH("LEFT"); v:SetWordWrap(false)
            row.value = v

            lines[i] = row
        end
    end
    for i = n + 1, #lines do lines[i]:Hide() end
end

-- Build the field list for an event: 11 base fields + variable suffix fields.
local function buildFields(ev)
    local out = {}
    local function add(key, val) out[#out + 1] = { key, val } end

    add("timestamp",       string.format("%.3f", ev.ts or 0))
    add("subevent",        ev.sub)
    add("hideCaster",      ev.hideCaster)
    add("sourceGUID",      ev.sourceGUID)
    add("sourceName",      ev.sourceName)
    add("sourceFlags",     ev.sourceFlags)
    add("sourceRaidFlags", ev.sourceRaidFlags)
    add("destGUID",        ev.destGUID)
    add("destName",        ev.destName)
    add("destFlags",       ev.destFlags)
    add("destRaidFlags",   ev.destRaidFlags)

    local args = ev.args or {}
    local names = suffixFor(ev.sub)
    if names then
        for i, name in ipairs(names) do
            add(name, args[11 + i])
        end
        -- Any remaining args beyond what the schema covers
        for i = 11 + #names + 1, #args do
            add(string.format("arg[%d]", i), args[i])
        end
    else
        -- Unknown subevent shape — dump the rest as numbered args.
        for i = 12, #args do
            add(string.format("arg[%d]", i), args[i])
        end
    end

    return out
end

function Detail:Show(eventId)
    ensurePanel()
    local ev = ns.GetEventById(eventId)
    if not ev then
        panel:Hide()
        return
    end

    titleFs:SetText(string.format("Event #%d", ev.id))
    subtitleFs:SetText(ev.sub or "")

    local fields = buildFields(ev)
    ensureLines(#fields)
    for i, kv in ipairs(fields) do
        local row = lines[i]
        row.key:SetText(kv[1])
        row.value:SetText(formatValue(kv[2]))
        row:Show()
    end

    -- Resize panel to fit the content (header + subtitle + lines + footer pad).
    local height = HEADER_H + 28 + (#fields * LINE_H) + 12
    panel:ClearAllPoints()
    local mainFrame = _G.WicksCombatLogFrame
    if mainFrame and mainFrame:IsShown() then
        panel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:SetSize(PANEL_W, height)

    panel:Show()
end

function Detail:Hide()
    if panel then panel:Hide() end
end

function Detail.OnBufferCleared()
    if panel then panel:Hide() end
end
