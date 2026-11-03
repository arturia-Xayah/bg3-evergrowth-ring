return {
    ModuleUUID = "7d174b8e-d212-49a3-bd8b-94f17bd08633",
    TemplateUUID = "2cbb59be-e573-4dfa-8d40-52db636de013",
    StateVar = "ER_7d174b8e_RingState",
    AppliedVar = "ER_7d174b8e_Applied",
    DeathVar = "ER_7d174b8e_DeathPaid",
    Source = "EvergrowthRing_7d174b8e_v1",
    AutoGive = true,
    SpellSlotLevels = {1, 2, 3, 4, 5, 6},
    -- Set true only with a mod that actually implements levels 7-9.
    -- SpellSlotLevels = {1, 2, 3, 4, 5, 6, 7, 8, 9},
    IncludeExistingPactSlots = true,
    -- Direct character kills and owned item/projectile kills count.
    -- A summon killing something does not count for its owner by default.
    CreditSummonKills = false,
    ReconcileEveryTicks = 90,
    SpellResource = "d136c5d9-0ff0-43da-acce-a74a07f8d6bf",
    PactResource = "e9127b70-22b7-42a1-b172-d02f828f260a",
    ActionResource = "734cbcfb-8922-4b6d-8330-b2a7e4c14b6a",
    BonusActionResource = "420c8df5-45c2-4253-93c2-7ec44e127930",
    MovementResource = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185",
    LevelUpEffect = "453e009e-aed7-8ef0-d2bc-8e9ba79065df", -- VFX_UI_LevelUp_01, 3s, non-looping
    PlayLevelUpEffect = true,
    PanelPollTicks = 30,
}
