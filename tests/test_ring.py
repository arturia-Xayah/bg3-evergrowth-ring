import hashlib
import random
import re
import struct
import sys
from pathlib import Path

import pytest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / "source/Mods/EvergrowthRing/ScriptExtender/Lua"
sys.path.insert(0, str(ROOT / "tools/vendor"))


@pytest.fixture
def core():
    lua = LuaRuntime(unpack_returned_tuples=True)
    return lua, lua.execute((LUA / "Core.lua").read_text())


@pytest.mark.parametrize("hp,n,remaining", [(0, 0, 0), (999, 0, 999), (1000, 1, 0),
    (1001, 1, 1), (2499, 1, 1499), (2500, 2, 0), (4500, 3, 0), (4600, 3, 100)])
def test_threshold_and_continuous_levels(core, hp, n, remaining):
    _, c = core
    s = c.AddHP(c.NewState(), hp)
    assert (s.Level, s.ProgressHP, s.Kills) == (n, remaining, 1)


def test_fractional_hp_has_no_accumulation_drift(core):
    _, c = core
    s = c.NewState()
    for _ in range(2000):
        s = c.AddHP(s, 0.5)
    assert (s.Level, s.ProgressHP) == (1, 0)


def test_no_gameplay_level_cap(core):
    _, c = core
    n = 100001
    s = c.AddHP(c.NewState(), 250 * n * (n + 3) + 1)
    assert (s.Level, s.ProgressHP) == (n, 1)


def test_progress_conservation_randomized(core):
    _, c = core
    rng = random.Random(117)
    s, total = c.NewState(), 0
    for _ in range(1000):
        hp = rng.randrange(1, 10001) / 2
        total += hp
        s = c.AddHP(s, hp)
        assert 0 <= s.ProgressHP < c.ThresholdHP(s.Level)
        assert total == 250 * s.Level * (s.Level + 3) + s.ProgressHP


@pytest.mark.parametrize("bad", [-1, float("inf"), float("nan")])
def test_invalid_hp_is_rejected(core, bad):
    _, c = core
    with pytest.raises(Exception):
        c.AddHP(c.NewState(), bad)


def test_native_boost_coverage(core):
    lua, c = core
    boost = c.Boosts(7, lua.table_from([1, 2, 3, 4, 5, 6]), lua.table_from([3]))
    assert len(re.findall(r"Ability\(", boost)) == 6
    assert len(re.findall(r"RollBonus\(SavingThrow,7,", boost)) == 6
    assert len(re.findall(r"IF\(IsAttack\(\)\):DamageBonus\(7,\w+,false\)", boost)) == 13
    assert len(re.findall(r"ActionResource\(SpellSlot,7,", boost)) == 6
    assert "ActionResource(WarlockSpellSlot,7,3)" in boost
    assert "DamageBonus(7)" in boost
    assert "SpellSaveDC(7)" in boost and "AC(7)" in boost
    assert "RollBonus(SkillCheck,7)" in boost
    assert "RollBonus(RawAbility," not in boost and "DeathSavingThrow" not in boost
    assert all(s not in boost for s in ["Physical", "Sentinel", "DamageBonus(7,None", "DealDamage"])
    assert c.Boosts(0, lua.table_from([1]), lua.table()) == ""


@pytest.mark.parametrize("n,initiative,critical,actions,bonus", [
    (0, 0, 0, 0, 0), (3, 0, 0, 0, 0), (4, 1, 0, 0, 0),
    (5, 1, 0, 0, 0), (7, 1, 0, 0, 0), (8, 2, 0, 0, 1),
    (9, 2, 0, 0, 1), (10, 2, 1, 1, 1),
    (19, 4, 1, 1, 2), (20, 5, 2, 2, 2), (40, 10, 4, 4, 5),
    (200, 50, 20, 20, 25)])
def test_new_bonus_boundaries(core, n, initiative, critical, actions, bonus):
    lua, c = core
    text = c.Boosts(n, lua.table_from([1]), lua.table())
    expected = {"Initiative": (initiative, "Initiative({})"),
                "ReduceCriticalAttackThreshold": (critical, "ReduceCriticalAttackThreshold({})"),
                "ActionResource(ActionPoint": (actions, "ActionResource(ActionPoint,{},0)"),
                "ActionResource(BonusActionPoint": (bonus, "ActionResource(BonusActionPoint,{},0)")}
    for prefix, (amount, fmt) in expected.items():
        if amount:
            assert fmt.format(amount) in text
        else:
            assert prefix not in text
    if n:
        assert f"ActionResource(Movement,{n},0)" in text
        assert f"RollBonus(SkillCheck,{n})" in text
    else:
        assert text == ""


def test_two_rings_round_each_instance_before_sum(core):
    lua, c = core
    text = c.Boosts(6, lua.table_from([1]), lua.table(), lua.table_from([3, 3]))
    assert "RollBonus(SkillCheck,6)" in text and "ActionResource(Movement,6,0)" in text
    assert "Initiative(" not in text
    assert "ActionResource(ActionPoint," not in text
    assert "ActionResource(BonusActionPoint," not in text
    text = c.Boosts(19, lua.table_from([1]), lua.table(), lua.table_from([9, 10]))
    assert "Initiative(4)" in text
    assert "ReduceCriticalAttackThreshold(1)" in text
    assert "ActionResource(ActionPoint,1,0)" in text
    assert "ActionResource(BonusActionPoint,2,0)" in text


def test_two_rings_equal_total_different_distribution_changes_unlocks(core):
    lua, c = core
    args = (lua.table_from([1]), lua.table())
    split = c.Boosts(14, *args, lua.table_from([7, 7]))
    concentrated = c.Boosts(14, *args, lua.table_from([14, 0]))
    assert split != concentrated
    assert "ActionResource(ActionPoint,1,0)" in concentrated
    assert "ActionResource(BonusActionPoint,1,0)" in concentrated


def test_stat_native_overflow_fails_without_silent_cap(core):
    lua, c = core
    with pytest.raises(Exception):
        c.Boosts(2147483647, lua.table_from([1]), lua.table())


P1 = "10000000-0000-0000-0000-000000000001"
P2 = "10000000-0000-0000-0000-000000000002"
R1 = "20000000-0000-0000-0000-000000000001"
R2 = "20000000-0000-0000-0000-000000000002"
V = "30000000-0000-0000-0000-000000000001"


@pytest.fixture
def engine():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Sources = lua.table_from({p.name: p.read_text() for p in LUA.glob("*.lua")})
    lua.execute((ROOT / "tests/engine_mock.lua").read_text())
    lua.execute((LUA / "BootstrapServer.lua").read_text())
    w = lua.globals().World
    config = lua.eval('Ext.Require("Config.lua")')
    c = lua.eval('Ext.Require("Core.lua")')
    p1, p2 = w.Character(P1, 100, 0), w.Character(P2, 100, 0)
    p1.Party = p2.Party = "player-party"
    w.Item(R1, config.TemplateUUID)
    w.Item(R2, config.TemplateUUID)
    w.Host = P1
    w.Event("SessionLoaded")
    w.RunTicks(3)
    return lua, w, config, c, p1, p2


def equip(w, item, character, e, slot="Ring"):
    e.Slots[slot] = item
    w.Fire("Equipped", item, character)
    w.RunTicks(4)


def state(w, config, item=R1):
    return w.Entities[item].Vars[config.StateVar]


def test_auto_delivery_once(engine):
    _, w, _, _, _, _ = engine
    assert w.GiveCalls == 1
    w.Event("SessionLoaded")
    w.RunTicks(200)
    assert w.GiveCalls == 1


def test_zero_current_hp_uses_maximum_and_deduplicates(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    victim = w.Character(V, 1234, 0)
    victim.HP = 0
    w.Fire("KilledBy", V, P1, P1, 19)
    w.Fire("KilledBy", V, P1, P1, 19)
    s = state(w, config)
    assert (s.Level, s.ProgressHP, s.Kills) == (1, 234, 1)


def test_summon_victim_excluded(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Character(V, 10000, 1)
    w.Fire("KilledBy", V, P1, P1, 1)
    assert state(w, config).ProgressHP == 0


def test_summon_killer_not_credited_to_owner(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    summon = "40000000-0000-0000-0000-000000000001"
    w.Character(summon, 10, 1)
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, summon, 1)
    assert state(w, config).Level == 0


def test_owned_item_kill_credits_wearer(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    weapon = "40000000-0000-0000-0000-000000000002"
    w.Item(weapon, "irrelevant")
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, weapon, 1)
    assert state(w, config).Level == 1


def test_resurrection_allows_next_real_death(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.Fire("Resurrected", V)
    w.Fire("KilledBy", V, P1, P1, 2)
    assert (state(w, config).Level, state(w, config).ProgressHP) == (1, 1000)


def test_two_rings_each_get_full_hp_and_add_levels(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P1, p1, "Ring2")
    w.Character(V, 2001, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.RunTicks(4)
    for ring in [R1, R2]:
        assert (state(w, config, ring).Level, state(w, config, ring).ProgressHP) == (1, 1001)
    assert p1.Vars[config.AppliedVar].Level == 2


def test_unringed_teammate_kill_awards_wearer_and_updates_panel(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Character(V, 4600, 0)
    w.Fire("KilledBy", V, P2, P2, 1)
    w.RunTicks(4)
    assert (state(w, config).Level, state(w, config).ProgressHP) == (3, 100)
    assert p1.Vars[config.AppliedVar].Level == 3
    assert len(w.Effects) == 1 and w.Effects[1].Character == P1
    packet = w.Broadcasts[len(w.Broadcasts)]
    assert packet.Rings[1].Level == 3 and packet.Rings[1].Progress == 1


def test_party_three_rings_full_credit_dedup_and_effect_per_wearer(engine):
    _, w, config, _, p1, p2 = engine
    third = "20000000-0000-0000-0000-000000000003"
    w.Item(third, config.TemplateUUID)
    equip(w, R1, P1, p1)
    equip(w, R2, P1, p1, "Ring2")
    equip(w, third, P2, p2)
    w.Character(V, 4600, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.Fire("KilledBy", V, P2, P2, 2)  # same death, even with a different attribution
    w.RunTicks(4)
    for ring in [R1, R2, third]:
        s = state(w, config, ring)
        assert (s.Level, s.ProgressHP, s.Kills) == (3, 100, 1)
    assert p1.Vars[config.AppliedVar].Level == 6
    assert p2.Vars[config.AppliedVar].Level == 3
    assert sorted(fx.Character for fx in w.Effects.values()) == [P1, P2]
    packet = w.Broadcasts[len(w.Broadcasts)]
    assert len(packet.Rings) == 3 and all(r.Progress == 1 for r in packet.Rings.values())


@pytest.mark.parametrize("party", [None, "other-party"])
def test_nonparty_killer_cannot_award_even_when_wearing_ring(engine, party):
    _, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P2, p2)
    p2.Party = party
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P2, P2, 1)
    assert state(w, config).ProgressHP == state(w, config, R2).ProgressHP == 0
    assert w.Entities[V].Vars[config.DeathVar] is None


@pytest.mark.parametrize("party", [None, "other-party"])
def test_recipient_membership_is_checked_at_each_death(engine, party):
    _, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P2, p2)
    p2.Party = party  # stale wearer registration must not grant progress
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.RunTicks(4)
    assert state(w, config).Level == 1
    assert state(w, config, R2).ProgressHP == 0
    p2.Party = "player-party"
    w.Fire("KilledBy", V, P1, P1, 1)  # joining later cannot replay a paid death
    assert state(w, config, R2).ProgressHP == 0


def test_registered_but_unequipped_ring_receives_no_party_credit(engine):
    _, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P2, p2)
    p2.Slots.Ring = None
    w.Fire("Unequipped", R2, P2)  # even before the deferred reconciliation tick
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P2, P2, 1)
    assert state(w, config).Level == 1
    assert state(w, config, R2).ProgressHP == 0


def test_party_marked_summon_cannot_trigger_or_receive_shared_progress(engine):
    _, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P2, p2)
    p2.Summon = 1
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, P2, 1)
    assert state(w, config).ProgressHP == 0
    w.Fire("KilledBy", V, P1, P1, 2)
    assert state(w, config).Level == 1
    assert state(w, config, R2).ProgressHP == 0


def test_corrupt_party_ring_does_not_partially_pay_other_rings(engine):
    lua, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P2, p2)
    w.Entities[R2].Vars[config.StateVar] = lua.table_from({"Schema": 999, "Level": 123})
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    assert state(w, config).ProgressHP == 0
    assert state(w, config, R2).Schema == 999
    assert w.Entities[V].Vars[config.DeathVar] is None


def test_duplicate_slots_do_not_multiply_full_party_credit(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    p1.Slots.Ring2 = R1  # defensive mock of duplicate inventory references
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P2, P2, 1)
    assert (state(w, config).Level, state(w, config).Kills) == (1, 1)


def test_transfer_and_unequip_preserve_instance_progress(engine):
    _, w, config, _, p1, p2 = engine
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1234", P1)
    w.RunTicks(4)
    p1.Slots.Ring = None
    w.Fire("Unequipped", R1, P1)
    equip(w, R1, P2, p2)
    assert p1.Vars[config.AppliedVar] is None
    assert p2.Vars[config.AppliedVar].Level == 1
    assert state(w, config).ProgressHP == 234
    assert w.Entities[R2].Vars[config.StateVar] is None


def test_reconcile_and_session_reload_never_stack(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1000", P1)
    w.RunTicks(4)
    calls = w.AddCalls
    w.RunTicks(500)
    w.Event("SessionLoaded")
    w.RunTicks(500)
    assert w.AddCalls == calls
    assert p1.Vars[config.AppliedVar].Level == 1


def test_max_slots_grow_without_refilling_and_pact_not_duplicated(engine):
    _, w, config, _, p1, _ = engine
    w.Resource(p1, "SpellSlot", 1, 4, 1)
    w.Resource(p1, "WarlockSpellSlot", 2, 2, 0)
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1000", P1)
    w.RunTicks(4)
    slot = w.FindResource(p1, "SpellSlot", 1)
    pact = w.FindResource(p1, "WarlockSpellSlot", 2)
    assert (slot.Amount, slot.MaxAmount) == (1, 5)
    assert (pact.Amount, pact.MaxAmount) == (0, 3)
    assert w.FindResource(p1, "SpellSlot", 6).Amount == 0
    calls = w.AddCalls
    w.RunTicks(300)
    assert w.AddCalls == calls
    p1.Slots.Ring = None
    w.Fire("Unequipped", R1, P1)
    w.RunTicks(4)
    equip(w, R1, P1, p1)
    assert (slot.Amount, slot.MaxAmount) == (1, 5)
    assert (pact.Amount, pact.MaxAmount) == (0, 3)


def test_action_and_movement_maxima_do_not_refill_on_upgrade_or_reequip(engine):
    _, w, config, _, p1, _ = engine
    for kind, maximum, amount in [("ActionPoint", 1, 0), ("BonusActionPoint", 1, 0),
                                  ("Movement", 9, 2), ("OtherResource", 10, 7)]:
        w.Resource(p1, kind, 0, maximum, amount)
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "115000", P1)  # exactly n=20
    w.RunTicks(4)
    assert state(w, config).Level == 20
    action = w.FindResource(p1, "ActionPoint", 0)
    bonus = w.FindResource(p1, "BonusActionPoint", 0)
    movement = w.FindResource(p1, "Movement", 0)
    other = w.FindResource(p1, "OtherResource", 0)
    assert (action.Amount, action.MaxAmount) == (0, 3)
    assert (bonus.Amount, bonus.MaxAmount) == (0, 3)
    assert (movement.Amount, movement.MaxAmount) == (2, 29)
    assert (other.Amount, other.MaxAmount) == (7, 10)
    # Simulate the native next-turn refill, then spend resources.
    action.Amount, bonus.Amount, movement.Amount = 1, 2, 3
    p1.Slots.Ring = None
    w.Fire("Unequipped", R1, P1)
    w.RunTicks(4)
    equip(w, R1, P1, p1)
    assert (action.Amount, action.MaxAmount) == (1, 3)
    assert (bonus.Amount, bonus.MaxAmount) == (1, 3)
    assert (movement.Amount, movement.MaxAmount) == (3, 29)
    assert (other.Amount, other.MaxAmount) == (7, 10)


def test_v01_ledger_replaced_and_instance_progress_retained(engine):
    lua, w, config, c, p1, _ = engine
    old = "Ability(Strength,20,2147483647,true);AC(20)"
    w.Entities[R1].Vars[config.StateVar] = c.AddHP(c.NewState(), 115123)
    p1.Slots.Ring = R1
    p1.Boosts[config.Source] = old
    p1.Vars[config.AppliedVar] = lua.table_from({"Schema": 1, "Boosts": old, "Level": 20,
                                               "PactLevels": lua.table()})
    w.Event("SessionLoaded")
    w.RunTicks(4)
    assert w.RemoveCalls == 1 and w.AddCalls == 1
    assert state(w, config).Level == 20 and state(w, config).ProgressHP == 123
    assert "ActionResource(ActionPoint,2,0)" in p1.Boosts[config.Source]


def test_cleanup_removes_only_our_source(engine):
    _, w, config, _, p1, _ = engine
    p1.Boosts.OtherMod = "AC(1)"
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1000", P1)
    w.RunTicks(4)
    w.Console.er_cleanup("er_cleanup")
    w.RunTicks(200)
    assert p1.Boosts[config.Source] is None
    assert p1.Boosts.OtherMod == "AC(1)"
    assert state(w, config).Level == 1


def test_inspection_action(engine):
    _, w, _, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Fire("UsingSpell", P1, "Shout_ER_Inspect", "Shout", "None", 123)
    w.RunTicks(2)
    packet = w.ClientMessages[P1]
    assert packet.Open and packet.FocusItem == R1
    assert packet.Rings[1].Level == 0 and packet.Rings[1].Required == 10


def test_progress_push_even_without_levelup_and_no_effect(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Character(V, 100, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.RunTicks(4)
    packet = w.Broadcasts[len(w.Broadcasts)]
    assert packet.Rings[1].Progress == 1
    assert packet.Rings[1].Required == 10 and packet.Rings[1].Remaining == 9
    assert packet.Rings[1].Fraction == 0.1
    assert len(w.Effects) == 0


def test_multilevel_upgrade_one_native_effect_not_character_xp(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Character(V, 4600, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.RunTicks(4)
    assert state(w, config).Level == 3
    assert len(w.Effects) == 1
    fx = w.Effects[1]
    assert fx.Character == P1 and fx.Effect == "453e009e-aed7-8ef0-d2bc-8e9ba79065df"
    assert fx.Bone == "" and fx.Scale == 1
    w.Event("SessionLoaded")
    w.RunTicks(4)
    assert len(w.Effects) == 1


def test_two_ring_simultaneous_upgrade_one_effect_and_live_totals(engine):
    _, w, _, _, p1, _ = engine
    equip(w, R1, P1, p1)
    equip(w, R2, P1, p1, "Ring2")
    w.Console.er_addhp("er_addhp", "115000", P1)  # full credit to each ring: exactly n=20
    w.RunTicks(4)
    assert len(w.Effects) == 1
    packet = w.Channels.RingPanel_v1.RequestHandler()
    assert len(packet.Rings) == 2
    for ring in packet.Rings.values():
        assert ring.Level == 20 and ring.Bonus.Actions == 2 and ring.Bonus.BonusActions == 2
        assert ring.WearerTotal.Level == 40 and ring.WearerTotal.Actions == 4
        assert ring.WearerTotal.BonusActions == 4


def test_unequipped_registered_ring_in_panel_persists_index(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1234", P1)
    w.RunTicks(4)
    p1.Slots.Ring = None
    w.Fire("Unequipped", R1, P1)
    w.RunTicks(4)
    packet = w.Channels.RingPanel_v1.RequestHandler()
    assert packet.Rings[1].Level == 1 and packet.Rings[1].Progress == 2.34
    assert not packet.Rings[1].Active and packet.Rings[1].WearerTotal is None
    assert w.ModVars[config.ModuleUUID].KnownRings[R1]


def test_panel_requests_cannot_award_experience(engine):
    lua, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    packet = w.Channels.RingPanel_v1.RequestHandler(lua.table_from({"Level": 99999, "HP": 99999}))
    assert packet.Rings[1].Level == 0 and state(w, config).ProgressHP == 0


@pytest.fixture
def client():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Sources = lua.table_from({p.name: p.read_text() for p in LUA.glob("*.lua")})
    lua.execute((ROOT / "tests/client_mock.lua").read_text())
    lua.execute((LUA / "BootstrapClient.lua").read_text())
    return lua, lua.globals().World, lua.execute((LUA / "Core.lua").read_text())


def client_packet(lua, core, hp=0, revision=1, opened=True):
    row = core.View(R1, core.AddHP(core.NewState(), hp))
    row.OwnerName, row.Active, row.Wearer = "Test character", True, P1
    row.PactLevels = lua.table_from([2])
    row.WearerTotal = row.Bonus
    return lua.table_from({"Revision": revision, "Ready": True, "Open": opened,
                           "FocusItem": R1, "Rings": lua.table_from([row]),
                           "SlotLevels": lua.table_from([1, 2, 3, 4, 5, 6])})


def test_live_panel_updates_progress_without_reopening(client):
    lua, w, core = client
    w.Channel.Handler(client_packet(lua, core))
    window = w.UI.Windows[1]
    assert window.Open and len(w.UI.Windows) == 1
    w.Channel.Handler(client_packet(lua, core, 4600, 2, False))
    assert window.Open and len(w.UI.Windows) == 1
    assert "Level 3" in w.UI.Texts[1].Label
    assert "1.000 / 25.000" in w.UI.Texts[3].Label
    assert "24.000" in w.UI.Texts[3].Label
    assert w.UI.ProgressBars[1].Value == 0.04


def test_live_panel_shows_new_action_formula_and_all_damage_types(client):
    lua, w, core = client
    w.Channel.Handler(client_packet(lua, core, 115000))
    labels = "\n".join(node.Label for node in w.UI.Texts.values())
    assert "Actions +2" in labels and "Bonus actions +2" in labels
    for name in ["All abilities", "Spell DC", "AC", "Saves", "Attack", "Skill checks",
                 "Damage", "Spell slot maxima", "Initiative", "Movement", "Critical threshold",
                 "Pact slots", "Slashing", "Piercing", "Bludgeoning", "Acid", "Thunder",
                 "Necrotic", "Fire", "Lightning", "Cold", "Psychic", "Poison", "Radiant", "Force"]:
        assert name in labels


def test_panel_polling_only_when_open_and_never_reopens_from_push(client):
    lua, w, core = client
    w.Reply = client_packet(lua, core, opened=False)
    w.Event("SessionLoaded")
    w.RunTicks(1)
    assert w.Requests == 1 and len(w.UI.Windows) == 0
    w.Channel.Handler(client_packet(lua, core))
    w.RunTicks(60)
    assert w.Requests >= 3
    w.UI.Windows[1].Open = False
    count = w.Requests
    w.Channel.Handler(client_packet(lua, core, 100, 2, False))
    w.RunTicks(60)
    assert not w.UI.Windows[1].Open and w.Requests == count
    w.Event("SessionLoading")
    w.RunTicks(60)
    assert w.Requests == count


def test_panel_ignores_old_snapshots(client):
    lua, w, core = client
    w.Channel.Handler(client_packet(lua, core, 4600, 9))
    w.Channel.Handler(client_packet(lua, core, 100, 8, False))
    assert "Level 3" in w.UI.Texts[1].Label


def test_panel_switch_ring_and_preserve_selection_across_push(client):
    lua, w, core = client
    packet = client_packet(lua, core)
    second = core.View(R2, core.AddHP(core.NewState(), 4600))
    second.OwnerName, second.Active = "Backpack", False
    second.PactLevels = lua.table()
    packet.Rings[2] = second
    w.Channel.Handler(packet)
    combo = w.UI.Combos[1]
    combo.SelectedIndex = 1
    combo.OnChange(combo)
    assert "Level 3" in w.UI.Texts[1].Label and R2 in w.UI.Texts[2].Label
    packet.Revision, packet.Open, packet.FocusItem = 2, False, None
    w.Channel.Handler(packet)
    assert combo.SelectedIndex == 1 and R2 in w.UI.Texts[2].Label


def test_spawn_event_registers_ring_before_first_equip(engine):
    _, w, config, _, _, _ = engine
    w.Fire("TemplateAddedTo", config.TemplateUUID, R2, P1, "Script")
    packet = w.Channels.RingPanel_v1.RequestHandler()
    assert packet.Rings[1].Item == R2 and packet.Rings[1].Level == 0
    assert not packet.Rings[1].Active


def test_missing_victim_or_zero_maxhp_does_not_pay(engine):
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Fire("KilledBy", V, P1, P1, 1)
    w.Character(V, 0, 0)
    w.Fire("KilledBy", V, P1, P1, 2)
    assert state(w, config).ProgressHP == 0


def test_unknown_schema_is_not_overwritten(engine):
    lua, w, config, _, p1, _ = engine
    w.Entities[R1].Vars[config.StateVar] = lua.table_from({"Schema": 999, "Level": 123})
    equip(w, R1, P1, p1)
    w.Character(V, 1000, 0)
    w.Fire("KilledBy", V, P1, P1, 1)
    assert state(w, config).Schema == 999
    assert state(w, config).Level == 123
    assert p1.Boosts[config.Source] is None


def test_saved_vars_restore_in_fresh_lua_state(engine):
    import json
    _, w, config, _, p1, _ = engine
    equip(w, R1, P1, p1)
    w.Console.er_addhp("er_addhp", "1234", P1)
    w.RunTicks(4)

    def plain(value):
        if hasattr(value, "items"):
            return {str(key): plain(val) for key, val in value.items()}
        return value

    saved = json.loads(json.dumps({"Ring": plain(w.Entities[R1].Vars),
        "Wearer": plain(p1.Vars), "Boosts": plain(p1.Boosts)}))
    fresh = LuaRuntime(unpack_returned_tuples=True)
    fresh.globals().Sources = fresh.table_from({p.name: p.read_text() for p in LUA.glob("*.lua")})
    fresh.execute((ROOT / "tests/engine_mock.lua").read_text())
    fresh.execute((LUA / "BootstrapServer.lua").read_text())
    fw = fresh.globals().World
    fp = fw.Character(P1, 100, 0)
    fi = fw.Item(R1, config.TemplateUUID)

    def table(value):
        if isinstance(value, dict):
            if value and all(str(k).isdigit() for k in value):
                return fresh.table_from({int(k): table(v) for k, v in value.items()})
            return fresh.table_from({k: table(v) for k, v in value.items()})
        return value

    fi.Vars = table(saved["Ring"])
    fp.Vars = table(saved["Wearer"])
    fp.Boosts = table(saved["Boosts"])
    fp.Slots.Ring = R1
    fw.Host = P1
    fw.Event("SessionLoaded")
    fw.RunTicks(100)
    assert fw.AddCalls == 0
    assert fi.Vars[config.StateVar].Level == 1
    assert fi.Vars[config.StateVar].ProgressHP == 234


def test_package_with_independent_struct_and_native_lz4_reader():
    import lz4.block
    data = (ROOT / "EvergrowthRing.pak").read_bytes()
    magic, version, offset, size, flags, priority, checksum, parts = struct.unpack_from("<4sIQIBB16sH", data)
    assert (magic, version, flags, parts) == (b"LSPK", 18, 0, 1)
    count, compressed_size = struct.unpack_from("<II", data, offset)
    assert size == compressed_size + 8
    table = lz4.block.decompress(data[offset + 8:offset + 8 + compressed_size], uncompressed_size=count * 272)
    md5 = hashlib.md5()
    names = []
    for index in range(count):
        raw_name, lo, hi, part, compression, disk_size, original_size = struct.unpack_from("<256sIHBBII", table, index * 272)
        assert (part, compression, original_size) == (0, 0, 0)
        start = lo + (hi << 32)
        assert (start - 40) % 64 == 0
        content = data[start:start + disk_size]
        md5.update(content)
        name = raw_name.rstrip(b"\0").decode()
        names.append(name)
        assert content == (ROOT / "source" / name).read_bytes()
    assert checksum == bytes((x + 1) % 256 for x in md5.digest())
    assert "Public/EvergrowthRing/RootTemplates/_merged.lsf" in names
    assert len(names) == len(set(names)) == 14
