-- Deliberately small adapter harness, NOT a BG3 simulation.
World = {Entities = {}, Listeners = {}, Events = {}, Console = {}, Queue = {},
    ModVars = {}, AddCalls = 0, RemoveCalls = 0, GiveCalls = 0, Messages = {},
    Channels = {}, Broadcasts = {}, ClientMessages = {}, Effects = {}}
local W = World
Ext = {Vars = {}, Entity = {}, Osiris = {}, Events = {}, Net = {}, Loca = {}}
Osi = {}
local cache = {}
function Ext.Require(name)
    if cache[name] == nil then cache[name] = assert(load(Sources[name]))() end
    return cache[name]
end
function Ext.Vars.RegisterUserVariable(...) end
function Ext.Vars.RegisterModVariable(...) end
function Ext.Vars.GetModVariables(id)
    W.ModVars[id] = W.ModVars[id] or {}
    return W.ModVars[id]
end
function Ext.Entity.Get(id) return W.Entities[id] end
function Ext.Entity.GetAllEntitiesWithComponent(name)
    assert(name == "ServerCharacter")
    local all = {}
    for _, e in pairs(W.Entities) do if e.IsCharacter then all[#all + 1] = e end end
    return all
end
for _, name in ipairs({"SessionLoaded", "ResetCompleted", "Tick"}) do
    W.Events[name] = {}
    Ext.Events[name] = {Subscribe = function(_, f) table.insert(W.Events[name], f) end}
end
function Ext.Osiris.RegisterListener(name, arity, when, f)
    W.Listeners[name] = {Arity = arity, When = when, Callback = f}
end
function Ext.RegisterConsoleCommand(name, f) W.Console[name] = f end
function Ext.OnNextTick(f) W.Queue[#W.Queue + 1] = f end
function Ext.Net.CreateChannel(module, name)
    local channel = {}
    function channel:SetHandler(f) self.MessageHandler = f end
    function channel:SetRequestHandler(f) self.RequestHandler = f end
    function channel:Broadcast(data) table.insert(W.Broadcasts, data) end
    function channel:SendToClient(data, user) W.ClientMessages[user] = data end
    W.Channels[name] = channel
    return channel
end
function Ext.Loca.GetTranslatedString(_, fallback) return fallback end
function W.Fire(name, ...)
    local listener = assert(W.Listeners[name], "Missing listener " .. name)
    assert(select("#", ...) == listener.Arity, "Bad arity for " .. name)
    listener.Callback(...)
end
function W.Event(name)
    for _, f in ipairs(W.Events[name]) do f({}) end
end
function W.Tick()
    -- Native resource recomputation is deferred until the engine tick.
    for _, e in pairs(W.Entities) do
        if e.Dirty then
            e.Dirty = false
            W.Recompute(e)
        end
    end
    local queue = W.Queue; W.Queue = {}
    for _, f in ipairs(queue) do f() end
    W.Event("Tick")
end
function W.RunTicks(n) for _ = 1, n do W.Tick() end end
function W.Character(id, hp, summon)
    local e = {Uuid = {EntityUuid = id}, IsCharacter = {}, Vars = {}, Slots = {},
        HP = hp or 100, MaxHP = hp or 100, Summon = summon or 0, Boosts = {}, Party = nil,
        ActionResources = {Resources = {}}, BaseSlots = {}}
    function e:Replicate(name) assert(name == "ActionResources") end
    W.Entities[id] = e
    return e
end
function W.Item(id, template)
    local e = {Uuid = {EntityUuid = id}, Vars = {}, Template = template}
    W.Entities[id] = e
    return e
end
local RES = {SpellSlot = "d136c5d9-0ff0-43da-acce-a74a07f8d6bf",
    WarlockSpellSlot = "e9127b70-22b7-42a1-b172-d02f828f260a",
    ActionPoint = "734cbcfb-8922-4b6d-8330-b2a7e4c14b6a",
    BonusActionPoint = "420c8df5-45c2-4253-93c2-7ec44e127930",
    Movement = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185",
    OtherResource = "ffffffff-0000-0000-0000-000000000001"} -- mock-only unrelated resource
function W.Resource(e, kind, level, max, amount)
    local id = RES[kind]
    e.ActionResources.Resources[id] = e.ActionResources.Resources[id] or {}
    table.insert(e.ActionResources.Resources[id], {Level = level, Amount = amount,
        MaxAmount = max, ResourceUUID = id})
    e.BaseSlots[id .. ":" .. level] = max
end
function W.FindResource(e, kind, level)
    for _, v in ipairs(e.ActionResources.Resources[RES[kind]] or {}) do
        if v.Level == level then return v end
    end
end
function W.Recompute(e)
    local bonus = {}
    for _, text in pairs(e.Boosts) do
        for kind, value, level in text:gmatch("ActionResource%((%w+),(%d+),(%d+)%)") do
            local key = RES[kind] .. ":" .. level
            bonus[key] = (bonus[key] or 0) + tonumber(value)
            if not W.FindResource(e, kind, tonumber(level)) then
                W.Resource(e, kind, tonumber(level), 0, 0)
            end
        end
    end
    for id, entries in pairs(e.ActionResources.Resources) do
        for _, entry in ipairs(entries) do
            local key = id .. ":" .. entry.Level
            local newMax = (e.BaseSlots[key] or 0) + (bonus[key] or 0)
            -- Worst case harness: engine grants all resource-max growth as current.
            entry.Amount = math.min(newMax, entry.Amount + math.max(0, newMax - entry.MaxAmount))
            entry.MaxAmount = newMax
        end
    end
end
function Osi.GetTemplate(item) return W.Entities[item] and W.Entities[item].Template end
function Osi.GetDisplayName(id) return "h" .. id end
function Osi.GetDirectInventoryOwner(item)
    for id, e in pairs(W.Entities) do
        for _, value in pairs(e.Slots or {}) do if value == item then return id end end
    end
    return W.Entities[item] and W.Entities[item].Owner
end
function Osi.PlayEffect(character, effect, bone, scale)
    W.Effects[#W.Effects + 1] = {Character = character, Effect = effect, Bone = bone, Scale = scale}
end
function Osi.GetEquippedItem(character, slot) return W.Entities[character].Slots[slot] end
function Osi.GetMaxHitpoints(id) return W.Entities[id].MaxHP end
function Osi.IsSummon(id) return W.Entities[id] and W.Entities[id].Summon or 0 end
function Osi.IsPartyMember(id, includeNotControlable)
    assert(includeNotControlable == 1)
    return W.Entities[id] and W.Entities[id].Party ~= nil and 1 or 0
end
function Osi.IsInPartyWith(id, other)
    local a, b = W.Entities[id], W.Entities[other]
    return a and b and a.Party ~= nil and a.Party == b.Party and 1 or 0
end
function Osi.GetHostCharacter() return W.Host end
function Osi.TemplateAddTo(template, who, count, notification)
    assert(count == 1 and notification == 1)
    W.GiveCalls = W.GiveCalls + 1
end
function Osi.AddBoosts(id, boosts, source, cause)
    assert(id == cause)
    W.AddCalls = W.AddCalls + 1
    local e = W.Entities[id]
    assert(e.Boosts[source] == nil, "Duplicate boost source")
    e.Boosts[source] = boosts; e.Dirty = true
end
function Osi.RemoveBoosts(id, boosts, first, source, cause)
    assert(first == 0 and id == cause)
    W.RemoveCalls = W.RemoveCalls + 1
    local e = W.Entities[id]
    assert(e.Boosts[source] == boosts, "Removal differs from persisted ledger")
    e.Boosts[source] = nil; e.Dirty = true
end
function Osi.OpenMessageBox(id, text) W.Messages[id] = text end
