local C = Ext.Require("Vars.lua")
local Core = Ext.Require("Core.lua")
local Channels = Ext.Require("Channels.lua")
local ready, ticks, stopped = false, 0, false
local pending, warned = {}, {}
local wearers, revision = {}, 0
local pushSnapshot
local ZERO = "00000000-0000-0000-0000-000000000000"

local function log(s) print("[EvergrowthRing] " .. tostring(s)) end
local function warn(key, s)
    if not warned[key] then warned[key] = true; log("WARNING " .. s) end
end
local function guarded(label, f, ...)
    local ok, result = pcall(f, ...)
    if not ok then warn(label, label .. ": " .. tostring(result)) end
    return ok, result
end
local function uuid(value)
    if value == nil then return nil end
    local s = tostring(value):lower():match("([%x]+%-%x+%-%x+%-%x+%-%x+)$")
    if s and #s == 36 and s ~= ZERO then return s end
end
local function entity(value)
    local id = uuid(value)
    return id and Ext.Entity.Get(id) or nil
end
local function entityId(e)
    return e and e.Uuid and uuid(e.Uuid.EntityUuid) or nil
end
local function isRing(item)
    return uuid(Osi.GetTemplate(item)) == C.TemplateUUID
end
local function ringState(item)
    local e = assert(entity(item), "Ring instance is not loaded")
    local s = e.Vars[C.StateVar]
    if s == nil then s = Core.NewState(); e.Vars[C.StateVar] = s end
    local vars = Ext.Vars.GetModVariables(C.ModuleUUID)
    local known = vars.KnownRings or {}
    if not known[item] then known[item] = true; vars.KnownRings = known end
    return Core.CheckState(s), e
end
local function wornRings(character)
    local result, seen = {}, {}
    for _, slot in ipairs({"Ring", "Ring2"}) do
        local id = uuid(Osi.GetEquippedItem(character, slot))
        if id and not seen[id] and isRing(id) then
            -- Reject corrupt/unknown states instead of resetting someone's ring.
            ringState(id)
            seen[id] = true
            result[#result + 1] = id
        end
    end
    return result
end

local function partyRings(killer)
    local host = uuid(Osi.GetHostCharacter())
    -- Explicit 0/1 comparisons: 0 is truthy in Lua. Membership is queried at
    -- the death event, not inferred from stale wearer or recruitment records.
    if not host or Osi.IsPartyMember(killer, 1) ~= 1
        or Osi.IsInPartyWith(killer, host) ~= 1 then return {} end
    local result, seen = {}, {}
    for _, e in ipairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        local id = entityId(e)
        if id and Osi.IsSummon(id) == 0 and Osi.IsPartyMember(id, 1) == 1
            and Osi.IsInPartyWith(id, killer) == 1 then
            for _, item in ipairs(wornRings(id)) do
                if not seen[item] then
                    seen[item] = true
                    result[#result + 1] = {Item = item, Wearer = id}
                end
            end
        end
    end
    return result
end

local managedResources = {[C.SpellResource] = true, [C.PactResource] = true,
    [C.ActionResource] = true, [C.BonusActionResource] = true, [C.MovementResource] = true}
local function resourceEntries(e, callback)
    if not e.ActionResources then return end
    for resource, entries in pairs(e.ActionResources.Resources) do
        local id = tostring(resource):lower()
        if managedResources[id] then
            for _, entry in ipairs(entries) do
                callback(id .. ":" .. entry.Level, entry, id)
            end
        end
    end
end
local function snapshotResources(e)
    local caps = {[C.ActionResource .. ":0"] = 0, [C.BonusActionResource .. ":0"] = 0,
        [C.MovementResource .. ":0"] = 0}
    for level = 1, 9 do
        caps[C.SpellResource .. ":" .. level] = 0
        caps[C.PactResource .. ":" .. level] = 0
    end
    resourceEntries(e, function(key, entry) caps[key] = entry.Amount end)
    return caps
end
local function clampResources(e, caps)
    local changed = false
    resourceEntries(e, function(key, entry)
        -- Old v0.1 ledgers only contain spell slots. Never zero unrecorded
        -- action/movement resources when resuming one of those pending clamps.
        if caps[key] == nil then return end
        -- New maxima are replenished at the resource's native rest/turn boundary.
        local amount = math.max(0, math.min(entry.Amount, entry.MaxAmount, caps[key]))
        if amount ~= entry.Amount then entry.Amount = amount; changed = true end
    end)
    if changed then e:Replicate("ActionResources") end
end
local function pactLevels(e, old)
    if not C.IncludeExistingPactSlots then return {} end
    local previous = {}
    for _, level in ipairs((old and old.PactLevels) or {}) do previous[level] = true end
    local levels = {}
    resourceEntries(e, function(_, entry, resource)
        if resource == C.PactResource then
            -- Remove our previous contribution when detecting actual class slots.
            local own = previous[entry.Level] and (old.Level or 0) or 0
            if entry.MaxAmount - own > 0 then levels[#levels + 1] = entry.Level end
        end
    end)
    table.sort(levels)
    return levels
end

local function apply(character, total, ringLevels)
    local e = assert(entity(character), "Wearer is not loaded")
    local old = e.Vars[C.AppliedVar]
    if old then assert(old.Schema == 1, "Unsupported applied-boost ledger schema") end
    local pacts = pactLevels(e, old)
    local boosts = Core.Boosts(total, C.SpellSlotLevels, pacts, ringLevels)
    if (old and old.Boosts or "") == boosts then
        if old and old.Caps then pending[character] = pending[character] or 2 end
        return
    end
    local caps = snapshotResources(e)
    if old and old.Caps then
        for key, value in pairs(old.Caps) do caps[key] = math.min(caps[key] or value, value) end
    end
    if old and old.Boosts ~= "" then
        -- Exact string + unique source + exact cause: remove only this mod's boosts.
        Osi.RemoveBoosts(character, old.Boosts, 0, C.Source, character)
    end
    -- Ledger describes the actual partial state even if AddBoosts throws.
    e.Vars[C.AppliedVar] = {Schema = 1, Boosts = "", Level = 0, Caps = caps, PactLevels = {}}
    pending[character] = 2
    if boosts ~= "" then Osi.AddBoosts(character, boosts, C.Source, character) end
    e.Vars[C.AppliedVar] = {Schema = 1, Boosts = boosts, Level = total,
        Caps = caps, PactLevels = pacts}
    clampResources(e, caps)
end

local function reconcile(character)
    if not ready or stopped or not entity(character) then return end
    local total, levels = 0, {}
    for item, wearer in pairs(wearers) do
        if wearer == character then wearers[item] = nil end
    end
    for _, item in ipairs(wornRings(character)) do
        local n = ringState(item).Level
        total = total + n
        levels[#levels + 1] = n
        wearers[item] = character
    end
    apply(character, total, levels)
end
local function reconcileAll()
    for _, e in ipairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        local id = entityId(e)
        if id then guarded("reconcile:" .. id, reconcile, id) end
    end
end
local function queueReconcile(character)
    if not ready or stopped then return end
    local id = uuid(character)
    if id then Ext.OnNextTick(function()
        guarded("reconcile:" .. id, reconcile, id)
        if pushSnapshot then guarded("panelPush", pushSnapshot) end
    end) end
end

local function nameOf(id)
    if not id then return "" end
    local handle = Osi.GetDisplayName(id)
    if not handle then return id end
    return Ext.Loca.GetTranslatedString(handle, id)
end

local function snapshot()
    revision = revision + 1
    local result = {Revision = revision, Ready = ready, Rings = {},
        SlotLevels = C.SpellSlotLevels, PactSlotsEnabled = C.IncludeExistingPactSlots}
    if not ready then return result end
    local known = Ext.Vars.GetModVariables(C.ModuleUUID).KnownRings or {}
    for item in pairs(known) do
        local e = entity(item)
        if e and isRing(item) then
            local ok, view = guarded("panelItem:" .. item, function()
                local row = Core.View(item, ringState(item))
                local owner = uuid(Osi.GetDirectInventoryOwner(item))
                row.OwnerName = nameOf(owner)
                row.Wearer = wearers[item]
                row.Active = row.Wearer ~= nil and not stopped
                row.PactLevels = {}
                if row.Wearer then
                    row.OwnerName = nameOf(row.Wearer)
                    local wearer = entity(row.Wearer)
                    local ledger = wearer and wearer.Vars[C.AppliedVar]
                    row.PactLevels = ledger and ledger.PactLevels or {}
                    local levels = {}
                    for _, other in ipairs(wornRings(row.Wearer)) do
                        levels[#levels + 1] = ringState(other).Level
                    end
                    if not stopped then row.WearerTotal = Core.DerivedBonuses(levels) end
                end
                return row
            end)
            if ok then result.Rings[#result.Rings + 1] = view end
        end
    end
    table.sort(result.Rings, function(a, b) return a.Item < b.Item end)
    return result
end

pushSnapshot = function() Channels.Panel:Broadcast(snapshot()) end
Channels.Panel:SetRequestHandler(function()
    -- Read-only snapshots: clients cannot award XP, change levels, or apply boosts.
    return snapshot()
end)

local function levelUpVisual(character)
    if not C.PlayLevelUpEffect then return end
    Ext.OnNextTick(function()
        if entity(character) then
            guarded("levelUpEffect", Osi.PlayEffect, character, C.LevelUpEffect, "", 1.0)
        end
    end)
end

local function give(character)
    local id = assert(uuid(character), "No character available")
    assert(entity(id), "Recipient is not loaded")
    Osi.TemplateAddTo(C.TemplateUUID, id, 1, 1)
    log("Requested one NEW n=0 ring for " .. id)
end
local function autoGive()
    if not C.AutoGive or stopped then return end
    local vars = Ext.Vars.GetModVariables(C.ModuleUUID)
    if vars.DeliveryAttempted then return end
    local host = uuid(Osi.GetHostCharacter())
    if not host or not entity(host) then return end
    vars.DeliveryAttempted = true
    local ok = guarded("autoGive", give, host)
    if not ok then vars.DeliveryAttempted = false end
    -- Do not repeatedly spawn if the engine accepts a request but delivery fails.
    -- !er_give is the explicit recovery route.
end

local function kill(defender, owner, attacker)
    if not ready or stopped then return end
    local victim, direct = uuid(defender), uuid(attacker)
    if not victim or not direct then return end
    local dead = entity(victim)
    if not dead then warn("victim:" .. victim, "Victim unloaded; kill not credited: " .. victim); return end
    if dead.Vars[C.DeathVar] then return end
    -- Queries return 0/1; Lua treats 0 as true, so compare explicitly.
    if Osi.IsSummon(victim) ~= 0 then return end
    local source = entity(direct)
    local killer
    if Osi.IsSummon(direct) ~= 0 then
        if C.CreditSummonKills then
            killer = uuid(owner)
        else
            return -- A controlled summon must not become a party-wide source.
        end
    elseif source and source.IsCharacter then
        killer = direct
    else
        -- Owned projectile/item damage can be credited to the actual wearer.
        killer = uuid(owner)
    end
    if not killer or killer == victim or not entity(killer) then return end
    local rings = partyRings(killer)
    if #rings == 0 then return end
    -- Do not read current HP: that is normally zero at this event.
    local maxHP = Osi.GetMaxHitpoints(victim)
    if not Core.ValidNumber(maxHP) or maxHP <= 0 then
        warn("maxhp:" .. victim, "Invalid maximum HP; kill not credited: " .. victim)
        return
    end
    -- Prepare all new states before committing any, to avoid partial XP awards.
    local changes = {}
    for _, target in ipairs(rings) do
        local s, itemEntity = ringState(target.Item)
        changes[#changes + 1] = {Entity = itemEntity, Item = target.Item, Wearer = target.Wearer,
            Previous = s.Level, State = Core.AddHP(s, maxHP)}
    end
    -- Persistent per-victim death guard prevents repeat death callbacks/save reloads.
    dead.Vars[C.DeathVar] = true
    local upgraded, affected = {}, {}
    for _, change in ipairs(changes) do
        change.Entity.Vars[C.StateVar] = change.State -- reassign to dirty UserVar
        affected[change.Wearer] = true
        if change.State.Level > change.Previous then
            upgraded[change.Wearer] = true
            log("LEVEL UP " .. Core.Summary(change.Item, change.State))
        end
    end
    for wearer in pairs(upgraded) do levelUpVisual(wearer) end
    -- Never rebuild boosts inside the damage/death resolution stack.
    for wearer in pairs(affected) do queueReconcile(wearer) end
end

local function status(character, show)
    local id = assert(uuid(character), "No character available")
    local lines, total = {}, 0
    for _, item in ipairs(wornRings(id)) do
        local s = ringState(item)
        lines[#lines + 1] = Core.Summary(item, s)
        total = total + s.Level
    end
    lines[#lines + 1] = "Effective bonus: +" .. total
    local text = table.concat(lines, "\n")
    log(text)
    if show then
        local data = snapshot()
        local rings = wornRings(id)
        data.Open, data.FocusItem = true, rings[1]
        Channels.Panel:SendToClient(data, id)
    end
end

Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "after", function(template, item, _, _)
    if uuid(template) == C.TemplateUUID then
        guarded("registerRing", ringState, uuid(item))
    end
end)

Ext.Osiris.RegisterListener("KilledBy", 4, "after", function(defender, owner, attacker, _)
    guarded("KilledBy", kill, defender, owner, attacker)
end)
Ext.Osiris.RegisterListener("Resurrected", 1, "after", function(character)
    local e = entity(character)
    if e then e.Vars[C.DeathVar] = nil end -- next genuine life/death can count again
    queueReconcile(character)
end)
for _, event in ipairs({"Equipped", "Unequipped"}) do
    Ext.Osiris.RegisterListener(event, 2, "after", function(_, character) queueReconcile(character) end)
end
for _, event in ipairs({"LeveledUp", "RespecCompleted"}) do
    Ext.Osiris.RegisterListener(event, 1, "after", function(character) queueReconcile(character) end)
end
Ext.Osiris.RegisterListener("UsingSpell", 5, "after", function(caster, spell, _, _, _)
    if spell == "Shout_ER_Inspect" then
        Ext.OnNextTick(function() guarded("inspect", status, caster, true) end)
    end
end)

Ext.Events.SessionLoaded:Subscribe(function()
    ready, ticks, stopped = true, 0, false
    pending, warned = {}, {}
    wearers, revision = {}, 0
    Ext.OnNextTick(function()
        guarded("startup", function() reconcileAll(); autoGive(); pushSnapshot() end)
    end)
end)
Ext.Events.ResetCompleted:Subscribe(function() ready = true; ticks = 0 end)
Ext.Events.Tick:Subscribe(function()
    if not ready then return end
    for id, frames in pairs(pending) do
        guarded("slotClamp:" .. id, function()
            local e = entity(id)
            if not e then return end
            local old = e.Vars[C.AppliedVar]
            if old and old.Caps then
                clampResources(e, old.Caps)
                if frames <= 1 then
                    if old.Boosts == "" then e.Vars[C.AppliedVar] = nil
                    else
                        e.Vars[C.AppliedVar] = {Schema = 1, Boosts = old.Boosts,
                            Level = old.Level, PactLevels = old.PactLevels}
                    end
                end
            end
        end)
        pending[id] = frames > 1 and frames - 1 or nil
    end
    ticks = ticks + 1
    if ticks >= C.ReconcileEveryTicks then
        ticks = 0
        guarded("poll", function() reconcileAll(); autoGive(); pushSnapshot() end)
    end
end)

Ext.RegisterConsoleCommand("er_status", function(_, character)
    guarded("er_status", status, character or Osi.GetHostCharacter(), false)
end)
Ext.RegisterConsoleCommand("er_give", function(_, character)
    guarded("er_give", give, character or Osi.GetHostCharacter())
end)
Ext.RegisterConsoleCommand("er_addhp", function(_, hp, character)
    guarded("er_addhp", function()
        local credit = assert(tonumber(hp), "Usage: !er_addhp <max-HP-credit> [character UUID]")
        assert(Core.ValidNumber(credit))
        local id = uuid(character or Osi.GetHostCharacter())
        local rings = wornRings(id)
        assert(#rings > 0, "Equip a ring first")
        local upgraded = false
        for _, item in ipairs(rings) do
            local s, e = ringState(item)
            -- Debug credit stays scoped to the selected character, full amount
            -- per ring just like a real party award (no division).
            local updated = Core.AddHP(s, credit)
            e.Vars[C.StateVar] = updated
            upgraded = upgraded or updated.Level > s.Level
        end
        if upgraded then levelUpVisual(id) end
        queueReconcile(id)
        status(id, false)
    end)
end)
Ext.RegisterConsoleCommand("er_panel", function(_, character)
    guarded("er_panel", status, character or Osi.GetHostCharacter(), true)
end)
Ext.RegisterConsoleCommand("er_repair", function(_, character)
    guarded("er_repair", function()
        local id = assert(uuid(character or Osi.GetHostCharacter()))
        apply(id, 0)
        queueReconcile(id)
    end)
end)
Ext.RegisterConsoleCommand("er_cleanup", function()
    -- Run before uninstalling, then save. Ring instance progress is retained.
    stopped = true
    for _, e in ipairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        local id = entityId(e)
        if id then guarded("cleanup:" .. id, apply, id, 0) end
    end
    log("Bonuses removed from loaded characters. Unequip rings, wait a moment, save, then exit and disable the mod.")
end)
log("v0.4.1 loaded; runtime acceptance in Windows BG3 is still required.")
