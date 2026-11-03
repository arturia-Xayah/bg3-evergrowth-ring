-- API adapter test only. This does not render ImGui or run a BG3 client.
World = {Events = {}, Queue = {}, Requests = 0, UI = {Windows = {}, Texts = {},
    Combos = {}, ProgressBars = {}, Buttons = {}}}
local W, cache = World, {}
Ext = {Vars = {}, Events = {}, Net = {}, IMGUI = {}}
function Ext.Require(name)
    if cache[name] == nil then cache[name] = assert(load(Sources[name]))() end
    return cache[name]
end
function Ext.Vars.RegisterUserVariable(...) end
function Ext.Vars.RegisterModVariable(...) end
function Ext.Net.CreateChannel(_, _)
    local channel = {}
    function channel:SetHandler(f) self.Handler = f end
    function channel:RequestToServer(data, callback)
        assert(type(data) == "table" and next(data) == nil)
        W.Requests = W.Requests + 1
        if W.Reply then callback(W.Reply) end
    end
    W.Channel = channel
    return channel
end
for _, name in ipairs({"SessionLoaded", "SessionLoading", "ResetCompleted", "Tick"}) do
    W.Events[name] = {}
    Ext.Events[name] = {Subscribe = function(_, f) table.insert(W.Events[name], f) end}
end
function Ext.OnNextTick(f) W.Queue[#W.Queue + 1] = f end
function W.Event(name) for _, f in ipairs(W.Events[name]) do f({}) end end
function W.Tick()
    local queue = W.Queue; W.Queue = {}
    for _, f in ipairs(queue) do f() end
    W.Event("Tick")
end
function W.RunTicks(n) for _ = 1, n do W.Tick() end end
local allowed = {Label = true, TextWrapPos = true, Closeable = true, Open = true,
    NoFocusOnAppearing = true, Options = true, Disabled = true, SelectedIndex = true,
    OnChange = true, OnClick = true, Size = true, Value = true, Overlay = true}
local methods = {}
local function node(kind, label)
    local values = {Label = label}
    local obj = setmetatable({}, {
        __index = function(_, key) return methods[key] or values[key] end,
        __newindex = function(_, key, value)
            assert(allowed[key], "Unexpected ImGui property: " .. key)
            values[key] = value
        end,
    })
    table.insert(W.UI[kind], obj)
    return obj
end
function Ext.IMGUI.NewWindow(label) return node("Windows", label) end
function methods:SetSize(size, condition)
    assert(size[1] == 580 and size[2] == 700 and condition == "FirstUseEver")
end
function methods:AddText(label) return node("Texts", label) end
function methods:AddCombo(label) return node("Combos", label) end
function methods:AddProgressBar() return node("ProgressBars", "") end
function methods:AddButton(label) return node("Buttons", label) end
function methods:AddSeparator() end
