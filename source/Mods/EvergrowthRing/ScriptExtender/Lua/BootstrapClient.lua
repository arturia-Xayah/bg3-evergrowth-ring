local C = Ext.Require("Vars.lua")
local Channels = Ext.Require("Channels.lua")
local window, widgets, latest, selectedItem
local active, ticks, inFlight, requestAge = false, 0, false, 0
local warned = false
local receive, request

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if not ok and not warned then
        warned = true
        print("[EvergrowthRing] Panel error: " .. tostring(value) .. "; use !er_status as fallback.")
    end
    return ok, value
end
local function text(label)
    local node = window:AddText(label)
    node.TextWrapPos = 0
    return node
end

local function render()
    if not window or not latest then return end
    local rings, options, index = latest.Rings or {}, {}, 1
    for i, ring in ipairs(rings) do
        options[i] = string.format("n=%.0f | %s | %s", ring.Level,
            ring.OwnerName ~= "" and ring.OwnerName or "Ground / On item", ring.Item:sub(1, 8))
        if ring.Item == selectedItem then index = i end
    end
    widgets.Choice.Options = #options > 0 and options or {"暂无戒指 / No known rings"}
    widgets.Choice.Disabled = #rings == 0
    widgets.Choice.SelectedIndex = index - 1 -- SE's ImGui combo uses zero-based indices
    local ring = rings[index]
    if not ring then
        widgets.Header.Label = "先佩戴戒指，再使用“查看生长之戒”。\nEquip a ring, then use Inspect Evergrowth Ring."
        widgets.Identity.Label, widgets.Progress.Label = "", ""
        widgets.Bar.Value, widgets.Bar.Overlay = 0, ""
        widgets.Linear.Label, widgets.Extra.Label, widgets.Types.Label, widgets.Total.Label = "", "", "", ""
        return
    end
    selectedItem = ring.Item
    local n, bonus = ring.Level, ring.Bonus
    widgets.Header.Label = string.format("等级 Level %.0f  |  %s  |  %s", n,
        ring.Active and "已佩戴 / Equipped" or "未佩戴：以下为潜在加成 / Unequipped",
        ring.OwnerName or "")
    widgets.Identity.Label = "戒指实例 Item: " .. ring.Item
    widgets.Progress.Label = string.format("进度 Progress %.3f / %.3f\n本级升级需求 Required %.3f | 还需 Remaining %.3f",
        ring.Progress, ring.Required, ring.Required, ring.Remaining)
    widgets.Bar.Value = ring.Fraction
    widgets.Bar.Overlay = string.format("%.2f%%", ring.Fraction * 100)
    widgets.Linear.Label = string.format(
        "六项属性 All abilities +%.0f\n法术 DC / Spell DC +%.0f | AC +%.0f\n六项豁免 Saves +%.0f | 攻击掷骰 Attack +%.0f\n所有技能检定 Skill checks +%.0f | 通用伤害 Damage +%.0f\n普通法术位上限 Spell slot maxima (%s) +%.0f each",
        n, n, n, n, n, n, n, table.concat(latest.SlotLevels or {}, "/"), n)
    local pacts = ring.PactLevels or {}
    widgets.Extra.Label = string.format(
        "先攻 Initiative +%.0f | 移动 Movement +%.0f m\n暴击门槛降低 Critical threshold -%.0f\n每回合完整动作 Actions +%.0f | 附赠动作 Bonus actions +%.0f\n已有契约法术位 Pact slots: %s\n已计入击杀 Credited kills %.0f",
        bonus.Initiative, bonus.Movement, bonus.Critical, bonus.Actions, bonus.BonusActions,
        #pacts > 0 and (table.concat(pacts, "/") .. " : +" .. n .. " each") or "未适用 / Not applicable",
        ring.Kills)
    widgets.Types.Label = string.format(
        "攻击附伤：13种各 +%.0f / Attack damage: each type +%.0f\n挥砍 Slashing · 穿刺 Piercing · 钝击 Bludgeoning\n强酸 Acid · 雷鸣 Thunder · 黯蚀 Necrotic · 火焰 Fire\n闪电 Lightning · 寒冷 Cold · 心灵 Psychic · 毒素 Poison\n光耀 Radiant · 力场 Force", n, n)
    local total = ring.WearerTotal
    widgets.Total.Label = total and string.format(
        "同一佩戴者合计 / Equipped total\n线性加成 +%.0f | 先攻 +%.0f | 移动 +%.0f m\n暴击门槛 -%.0f | 动作 +%.0f | 附赠动作 +%.0f",
        total.Level, total.Initiative, total.Movement, total.Critical, total.Actions, total.BonusActions) or ""
end

local function ensureWindow()
    if window then return end
    window = Ext.IMGUI.NewWindow("生长之戒 / Evergrowth Ring###ER_7d174b8e_Panel")
    window.Closeable = true
    window.Open = false
    window.NoFocusOnAppearing = true
    window:SetSize({580, 700}, "FirstUseEver")
    widgets = {}
    widgets.Choice = window:AddCombo("戒指 Ring")
    widgets.Choice.OnChange = function()
        if latest and latest.Rings then
            local ring = latest.Rings[widgets.Choice.SelectedIndex + 1]
            if ring then selectedItem = ring.Item end
            safe(render)
        end
    end
    widgets.Header, widgets.Identity = text(""), text("")
    widgets.Progress = text("")
    widgets.Bar = window:AddProgressBar()
    widgets.Bar.Size = {-1, 20}
    window:AddSeparator()
    widgets.Linear, widgets.Extra, widgets.Types = text(""), text(""), text("")
    window:AddSeparator()
    widgets.Total = text("")
    text("显示戒指的直接加成；不含属性调整值等次生收益。\nDirect ring bonuses only. Turn resources replenish next turn.")
    local refresh = window:AddButton("刷新 Refresh")
    refresh.OnClick = function() request() end
end

receive = function(data)
    if type(data) ~= "table" or type(data.Rings) ~= "table" then return end
    if latest and data.Revision and latest.Revision and data.Revision < latest.Revision then return end
    latest = data
    if data.FocusItem then selectedItem = data.FocusItem end
    if data.Open then
        local ok = safe(ensureWindow)
        if not ok then return end
        window.Open = true
    end
    if window then safe(render) end
end

request = function()
    if inFlight or not active then return end
    inFlight, requestAge = true, 0
    local ok = safe(function()
        Channels.Panel:RequestToServer({}, function(data)
            inFlight = false
            safe(receive, data)
        end)
    end)
    if not ok then inFlight = false end
end

Channels.Panel:SetHandler(function(data) safe(receive, data) end)
local function sessionReady()
    active, ticks, inFlight, requestAge = true, 0, false, 0
    latest, selectedItem = nil, nil
    if window then window.Open = false end
    Ext.OnNextTick(request)
end
Ext.Events.SessionLoaded:Subscribe(sessionReady)
Ext.Events.ResetCompleted:Subscribe(sessionReady)
Ext.Events.SessionLoading:Subscribe(function()
    active, inFlight = false, false
    latest, selectedItem = nil, nil
    if window then window.Open = false end
end)
Ext.Events.Tick:Subscribe(function()
    if not active then return end
    if inFlight then
        requestAge = requestAge + 1
        if requestAge > 180 then inFlight = false end
    end
    ticks = ticks + 1
    if ticks >= C.PanelPollTicks then
        ticks = 0
        if window and window.Open then request() end
    end
end)
