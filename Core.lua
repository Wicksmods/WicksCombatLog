local ADDON, ns = ...

ns.MAX_BUFFER = 5000
ns.events     = {}     -- ring buffer of event records, indexed by ((id-1) % MAX_BUFFER) + 1
ns.eventCount = 0      -- monotonic count of all events ever captured
ns.paused     = false

-- Persisted filter state (defaults; overwritten from WCLSettings on PLAYER_LOGIN).
ns.filters = {
    families   = { damage = true, heal = true, aura = true, cast = true, misc = true },
    source     = "anyone",  -- "mine" | "pet" | "target" | "anyone"
    spellMatch = "",        -- case-insensitive substring against spellName
}

-- Subevent → family classification. The list is intentionally short — anything
-- that isn't damage/heal/aura/cast lands in "misc".
local function classifyFamily(sub)
    if sub:find("_DAMAGE") or sub == "ENVIRONMENTAL_DAMAGE" then return "damage" end
    if sub:find("_HEAL")   then return "heal"   end
    if sub:find("_AURA_")  then return "aura"   end
    if sub:find("_CAST_")  then return "cast"   end
    return "misc"
end

local AFFIL_MINE    = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
local TYPE_PET      = COMBATLOG_OBJECT_TYPE_PET         or 0x00001000
local REACT_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040

local function sourceMatches(filter, ev)
    if filter == "anyone" then return true end
    local sf = ev.sourceFlags or 0
    if filter == "mine" then
        return bit.band(sf, AFFIL_MINE) ~= 0
    elseif filter == "pet" then
        return bit.band(sf, AFFIL_MINE) ~= 0 and bit.band(sf, TYPE_PET) ~= 0
    elseif filter == "hostile" then
        return bit.band(sf, REACT_HOSTILE) ~= 0
    elseif filter == "target" then
        local tg = UnitGUID("target")
        return tg and (ev.sourceGUID == tg or ev.destGUID == tg)
    end
    return true
end

function ns.PassesFilters(ev)
    local f = ns.filters
    if not f.families[ev.family] then return false end
    if not sourceMatches(f.source, ev) then return false end
    if f.spellMatch and f.spellMatch ~= "" then
        local hay = (ev.spellName or ""):lower()
        if not hay:find(f.spellMatch:lower(), 1, true) then return false end
    end
    return true
end

-- Pack a single CLEU event into a record. Stores all raw args verbatim for the
-- Detail panel; pulls out timestamp / source / dest / spell / amount eagerly so
-- the row renderer doesn't re-parse on every frame.
local function captureEvent()
    if ns.paused then return end
    local args = { CombatLogGetCurrentEventInfo() }
    local sub  = args[2]

    local ev = {
        ts              = args[1],
        sub             = sub,
        hideCaster      = args[3],
        sourceGUID      = args[4],
        sourceName      = args[5],
        sourceFlags     = args[6],
        sourceRaidFlags = args[7],
        destGUID        = args[8],
        destName        = args[9],
        destFlags       = args[10],
        destRaidFlags   = args[11],
        args            = args,
    }
    ev.family = classifyFamily(sub)

    -- Eager-extract spell + amount fields so row rendering stays cheap.
    local prefix = sub:sub(1, 5)
    if prefix == "SPELL" or prefix == "RANGE" then
        ev.spellId     = args[12]
        ev.spellName   = args[13]
        ev.spellSchool = args[14]
        if sub:find("_DAMAGE") or sub:find("_HEAL") or sub:find("_ENERGIZE")
           or sub:find("_DRAIN") or sub:find("_LEECH") then
            ev.amount = args[15]
        end
    elseif sub == "SWING_DAMAGE" then
        ev.amount = args[12]
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        ev.envType = args[12]
        ev.amount  = args[13]
    end

    ns.eventCount = ns.eventCount + 1
    ev.id = ns.eventCount
    local idx = ((ns.eventCount - 1) % ns.MAX_BUFFER) + 1
    ns.events[idx] = ev

    if ns.UI and ns.UI.OnEventCaptured then ns.UI.OnEventCaptured() end
end

-- Walk events newest-first. Callback returning false halts iteration.
function ns.IterEventsNewest(callback)
    local n = math.min(ns.eventCount, ns.MAX_BUFFER)
    for i = 0, n - 1 do
        local logicalIdx = ns.eventCount - i
        local idx = ((logicalIdx - 1) % ns.MAX_BUFFER) + 1
        local ev = ns.events[idx]
        if ev then
            if callback(ev) == false then return end
        end
    end
end

function ns.GetEventById(id)
    if not id or id < 1 or id > ns.eventCount then return nil end
    if ns.eventCount - id >= ns.MAX_BUFFER then return nil end
    local idx = ((id - 1) % ns.MAX_BUFFER) + 1
    return ns.events[idx]
end

function ns.ClearBuffer()
    wipe(ns.events)
    ns.eventCount = 0
    if ns.UI and ns.UI.OnBufferCleared then ns.UI.OnBufferCleared() end
    if ns.Detail and ns.Detail.OnBufferCleared then ns.Detail.OnBufferCleared() end
end

function ns.SetPaused(p)
    ns.paused = p and true or false
    if ns.UI and ns.UI.OnPauseChanged then ns.UI.OnPauseChanged() end
end

function ns.TogglePaused()
    ns.SetPaused(not ns.paused)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function(_, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        captureEvent()
    elseif event == "PLAYER_LOGIN" then
        WCLSettings = WCLSettings or {}
        if WCLSettings.filters then
            -- Merge persisted filters; preserve defaults for any missing fields.
            for k, v in pairs(WCLSettings.filters) do ns.filters[k] = v end
        end
    end
end)

SLASH_WICKSCOMBATLOG1 = "/wcl"
SlashCmdList.WICKSCOMBATLOG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        if ns.UI then ns.UI:ResetPosition() end
    elseif msg == "clear" then
        ns.ClearBuffer()
        print("|cff4FC778Wick's Combat Log|r buffer cleared.")
    elseif msg == "pause" then
        ns.SetPaused(true)
        print("|cff4FC778Wick's Combat Log|r paused.")
    elseif msg == "resume" then
        ns.SetPaused(false)
        print("|cff4FC778Wick's Combat Log|r resumed.")
    else
        if ns.UI then ns.UI:Toggle() end
    end
end
