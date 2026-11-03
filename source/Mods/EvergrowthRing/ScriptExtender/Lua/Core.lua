-- Pure rules. No engine objects, events, file IO, or damage calls.
local M = {}
M.Abilities = {"Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"}
M.DamageTypes = {"Slashing", "Piercing", "Bludgeoning", "Acid", "Thunder", "Necrotic",
    "Fire", "Lightning", "Cold", "Psychic", "Poison", "Radiant", "Force"}

function M.NewState()
    return {Schema = 1, Level = 0, ProgressHP = 0, Kills = 0}
end

function M.ValidNumber(x)
    return type(x) == "number" and x == x and x >= 0 and x < math.huge
end

function M.CheckState(s)
    assert(type(s) == "table" and s.Schema == 1, "Unsupported ring state schema")
    assert(M.ValidNumber(s.Level) and s.Level % 1 == 0, "Invalid ring level")
    assert(M.ValidNumber(s.ProgressHP), "Invalid ring progress")
    assert(M.ValidNumber(s.Kills) and s.Kills % 1 == 0, "Invalid kill count")
    return s
end

function M.ThresholdHP(n)
    return 1000 + 500 * n -- 100 HP units = 1 progress point
end

function M.AddHP(state, hp)
    M.CheckState(state)
    assert(M.ValidNumber(hp), "HP credit must be finite and nonnegative")
    local s = {Schema = 1, Level = state.Level, ProgressHP = state.ProgressHP + hp,
        Kills = state.Kills + 1}
    -- At most a few thousand iterations for a single int32 MaxHp victim.
    while s.ProgressHP >= M.ThresholdHP(s.Level) do
        s.ProgressHP = s.ProgressHP - M.ThresholdHP(s.Level)
        s.Level = s.Level + 1
    end
    return s
end

function M.DerivedBonuses(levels)
    local result = {Level = 0, Initiative = 0, Movement = 0, Critical = 0, Actions = 0, BonusActions = 0}
    for _, n in ipairs(levels) do
        assert(M.ValidNumber(n) and n % 1 == 0, "Invalid ring level")
        result.Level = result.Level + n
        result.Initiative = result.Initiative + math.floor(n / 4)
        result.Movement = result.Movement + n
        result.Critical = result.Critical + math.floor(n / 10)
        result.Actions = result.Actions + math.floor(n / 10)
        result.BonusActions = result.BonusActions + math.floor(n / 8)
    end
    return result
end

function M.Boosts(n, slotLevels, pactLevels, ringLevels)
    assert(M.ValidNumber(n) and n % 1 == 0, "Invalid effective level")
    -- Not a progression cap: the native Ability/AC/SpellSaveDC fields are int32.
    assert(n <= 2147483000, "Bonus exceeds native int32 safety range; progression retained")
    local extra = M.DerivedBonuses(ringLevels or {n})
    assert(extra.Level == n, "Ring levels do not match effective level")
    if n == 0 then return "" end
    local v, out = string.format("%.0f", n), {}
    for _, a in ipairs(M.Abilities) do
        -- Explicit cap avoids the ordinary Ability boost cap of 20.
        -- DontAdjustHealth avoids healing on repeated CON boost removal/addition.
        out[#out + 1] = "Ability(" .. a .. "," .. v .. ",2147483647,true)"
    end
    out[#out + 1] = "SpellSaveDC(" .. v .. ")"
    out[#out + 1] = "AC(" .. v .. ")"
    out[#out + 1] = "RollBonus(Attack," .. v .. ")"
    -- Skill checks only; do not also add RawAbility to the same request.
    out[#out + 1] = "RollBonus(SkillCheck," .. v .. ")"
    if extra.Initiative > 0 then
        out[#out + 1] = "Initiative(" .. string.format("%.0f", extra.Initiative) .. ")"
    end
    out[#out + 1] = "ActionResource(Movement," .. v .. ",0)"
    if extra.Critical > 0 then
        out[#out + 1] = "ReduceCriticalAttackThreshold(" .. string.format("%.0f", extra.Critical) .. ")"
    end
    if extra.Actions > 0 then
        out[#out + 1] = "ActionResource(ActionPoint," .. string.format("%.0f", extra.Actions) .. ",0)"
    end
    if extra.BonusActions > 0 then
        out[#out + 1] = "ActionResource(BonusActionPoint," .. string.format("%.0f", extra.BonusActions) .. ",0)"
    end
    for _, a in ipairs(M.Abilities) do
        out[#out + 1] = "RollBonus(SavingThrow," .. v .. "," .. a .. ")"
    end
    out[#out + 1] = "DamageBonus(" .. v .. ")"
    -- Native typed bonuses: no OnDamage/DealDamage/ApplyDamage recursion.
    -- This follows native attack/damage-packet semantics, not one proc per cast.
    for _, damageType in ipairs(M.DamageTypes) do
        out[#out + 1] = "IF(IsAttack()):DamageBonus(" .. v .. "," .. damageType .. ",false)"
    end
    for _, level in ipairs(slotLevels) do
        assert(level >= 1 and level <= 9 and level % 1 == 0)
        out[#out + 1] = "ActionResource(SpellSlot," .. v .. "," .. level .. ")"
    end
    for _, level in ipairs(pactLevels or {}) do
        out[#out + 1] = "ActionResource(WarlockSpellSlot," .. v .. "," .. level .. ")"
    end
    return table.concat(out, ";")
end

function M.Summary(item, s)
    return string.format("%s | n=%.0f | progress %.3f / %.3f | credited kills %.0f",
        item, s.Level, s.ProgressHP / 100, M.ThresholdHP(s.Level) / 100, s.Kills)
end

function M.View(item, state)
    M.CheckState(state)
    local required = M.ThresholdHP(state.Level) / 100
    local progress = state.ProgressHP / 100
    return {Item = item, Level = state.Level, Progress = progress, Required = required,
        Remaining = math.max(0, required - progress), Fraction = math.min(1, progress / required),
        Kills = state.Kills, Bonus = M.DerivedBonuses({state.Level})}
end
return M
