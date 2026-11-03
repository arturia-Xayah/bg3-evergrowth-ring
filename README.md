> 本 Mod 由 **Codex** 实现开发、资源整合与打包；美术绘制稿使用内置 imagegen 生成。

<div align="center">

<img src="artwork/evergrowth-ring-icon.png" alt="无尽生长之戒：金色藤蔓戒圈与翠绿宝石，透明背景" width="256">

# 无尽生长之戒 · Evergrowth Ring

**以击杀积累成长，让同一枚戒指陪伴角色不断变强。**

**简体中文** · [English](README.en.md) · [安装包](EvergrowthRing.pak) · [完整使用手册](README.zh-CN.md)

[![Download PAK](https://img.shields.io/badge/Download-PAK-4c8b52)](EvergrowthRing.pak)
[![Version](https://img.shields.io/badge/version-0.4.1-blue)](docs/CHANGELOG.md)
[![Status](https://img.shields.io/badge/in--game-unverified-orange)](docs/VALIDATION.md)

Windows · Baldur’s Gate 3 · BG3 Script Extender ≥ 34 · Lua

</div>

**当前为未经过 Windows 和游戏实测的试用版。** 已生成可导入的 `.pak`，通过 75 项图标、规则、模拟适配器和包结构测试。此前的在线 Stats / RootTemplate 格式校验证据保留；本版自定义图标通过本地格式、引用与包回读检查，未重新在线验证。真实战斗、存读档、图标、实时面板与升级特效仍需游戏验收。核对日期：2026-11-03；[接口与来源记录](docs/API_AUDIT.md)。

## 目录

- [安装与更新](#安装与更新)
- [成长与实例保存](#成长与实例保存)
- [戒指加成](#戒指加成)
- [实时成长面板与升级特效](#实时成长面板与升级特效)
- [外观与贴图](#外观与贴图)
- [兼容性与存档](#兼容性与存档)
- [开发者文档](#开发者文档)

## 安装与更新

1. 备份测试存档，退出游戏，安装 [Norbyte BG3 Script Extender](https://github.com/Norbyte/bg3se/releases)。运行版本须至少为 34，使用官方更新器取得与你的游戏匹配的版本。
2. 下载仓库中的 [EvergrowthRing.pak](EvergrowthRing.pak)（文件页面点 **Download raw file**）。用 [BG3 Mod Manager](https://github.com/LaughingLeader/BG3ModManager) 导入，移到活动列表，保存并 **Export Order to Game**。
3. 载入测试存档。脚本会向主机角色申请发放一枚 0 级戒指；每个存档时间线自动申请一次。佩戴后使用 **查看生长之戒 / Inspect Evergrowth Ring** 打开面板。

安装不需要 Python、MCM、Community Library 或额外 Mod Fixer。更新时完全退出游戏，替换旧 `.pak`，重新导出顺序；不要同时启用同 UUID 的多个版本。已有实例的成长记录保留，升级迁移尚未实机验证。

手动存放路径：`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\EvergrowthRing.pak`，之后仍需激活并导出加载顺序。发放恢复、控制台命令、卸载步骤见[完整手册](README.zh-CN.md)。

## 成长与实例保存

- 初始等级 `n = 0`，不预设等级上限；仍受原生数值范围和浮点精度限制。
- 小队任一成员直接击杀非召唤单位时，全队当前已加载成员**已装备的每枚成长戒指**均获得死者**死亡事件时最大 HP ÷ 100** 的完整进度，临时 HP 不计。击杀者无需佩戴戒指。死亡时当前 HP 通常为 0，因此不使用当前 HP。
- 从 `n` 升到 `n+1` 消耗 `10 + 5n` 进度，保留溢出并可连续跨级。例如增加 46 进度可从 0 级到 **3 级、1/25**。
- 等级、进度、击杀记录绑定**物品实例**。摘下、转交或存箱后仍保留；新生成的戒指从 0 级开始。
- 同一角色戴两枚时，线性加成相加；取整加成先按每枚计算再相加。每枚戒指独立获得完整进度，不因人数或戒指数量减少。例如最大 HP 为 100 的目标被队友击杀，8 枚已装备戒指就各获得 1 进度。

## 戒指加成

下表均为每枚戒指的**直接加成**；属性调整值产生的次生收益由原版继续计算。

| 项目 | 加成 |
| --- | --- |
| 六项属性、法术 DC、六种豁免、AC、攻击掷骰、通用伤害 | 各 `+n` |
| 所有技能检定 | `+n` |
| 先攻 | `+⌊n/4⌋` |
| 每回合移动距离 | `+n` 米 |
| 暴击门槛 | 降低 `⌊n/10⌋` |
| 每回合完整动作 / 附赠动作 | `+⌊n/10⌋` / `+⌊n/8⌋` |
| 1–6 环普通法术位上限 | 每环 `+n`；不授予法术或施法能力 |
| 已有契约法术位上限 | 当前已有环级 `+n`；不凭空授予契约施法 |
| 攻击附伤 | 13 种实际伤害类型各 `n` 点 |

攻击附伤以原生 `IsAttack()` 和 typed `DamageBonus` 实现，覆盖武器、徒手和法术攻击上下文，不主动对纯豁免法术或持续地表附加 13 条伤害。不通过伤害回调再制造伤害，避免本 Mod 自身递归；多射线、DRS 与其他装备 proc 的重复结算仍需按难度和 Mod 组合实测。类型与具体边界见[伤害说明](README.zh-CN.md#伤害范围和-proc)。

## 实时成长面板与升级特效

佩戴后使用 **查看生长之戒**，可保持独立面板开启，查看每枚戒指的等级、进度、升级需求、剩余进度、进度条和各项加成，并切换实例。服务端只读快照在击杀、升级和换装后刷新；面板开启时还有定期刷新。

真正升级时播放原版 `VFX_UI_LevelUp_01` 资源，一次结算对每个实际升级的佩戴者各播放一次，同一人双戒指或跨多级不重复播放，不改变人物经验或职业等级。**界面与特效尚未在游戏内确认。** 原生背包悬浮卡片仍为静态说明；操作与限制见[面板文档](docs/UI_PANEL.md)。

## 外观与贴图

**0.4.1 新增独立戒指图标**：清晰的金色戒圈、翠绿宝石、藤蔓雕纹与透明背景，已替换本页封面，并通过自定义图集和物品图标引用加入 `.pak`。包含64像素背包图集、144像素手柄图及380像素悬浮说明图。资源引用、透明通道与包内容检查通过，**游戏内实际显示仍未验证**。见[图标源图与导出说明](artwork/ICON.md)。

本仓库新增了**旧金 / 藤蔓根系 / 翠绿生命结晶**主题的 [PNG 材质底色绘制稿](artwork/evergrowth-gold-vines-basecolor-draft.png)，用于这枚成长戒指的后续美术制作。参考游戏的奇幻饰品气质，未复制官方纹理。

**这张材质绘制稿尚未接入 `.pak`。** 游戏内3D物品仍继承原版简式金戒指 `LOOT_GEN_Ring_A_Simple_Gold` 的模型与材质。此纹样 PNG 尚未匹配模型 UV，也不是完整 PBR 材质；它与本版已打包的2D戒指图标是不同资产。详见[材质绘制稿说明](artwork/README.md)。

## 兼容性与存档

- 共享按击杀当时的原生同队判定，不设距离或同场战斗要求；只枚举当前已加载成员。背包、箱子里的未装备戒指不获得进度，未加载成员不会补发历史进度。营地待命或临时跟随角色是否计入，取决于引擎当时是否判定为同队。默认召唤物代杀仍不计。
- 成长数据由服务器管理并通过 SE UserVars 保存到实例；客户端只读取面板快照。联机各端须使用相同包与兼容 SE，联机未实测。
- 摘戴或升级不应补满已消耗法术位与本回合资源。新增法术位待对应休息恢复，动作和移动距离待下一回合补充；资源重算时序需实机核验。
- 脚本无正确击杀归属的死亡可能漏算。自定义召唤物若未标记为召唤物，无法通用识别。销毁重建物品的其他 Mod 可能使其变为新实例。
- 正式游玩前按[完整手册的游戏内验收步骤](README.zh-CN.md#游戏内验收步骤)测试。卸载前摘下戒指并按手册清理已加载角色的加成，保留安装前存档。

## 开发者文档

源码与可编辑资源在 `source/`，本地化源在 `localization/`，美术源在 `artwork/`。Python 3.10+ 可离线构建，构建本身无须安装 pip 依赖：

```shell
python tools/build.py
```

Windows 也可运行 `Build-Windows.cmd`。运行模拟与格式测试：

```shell
python -m pip install -r requirements-dev.txt
python -m pytest -q tests
```

- [完整中文使用手册](README.zh-CN.md) / [English overview](README.en.md)
- [API、数据格式与来源核对](docs/API_AUDIT.md)
- [验证结果与未测范围](docs/VALIDATION.md) / [原始测试结果](docs/TEST_RESULTS.txt)
- [更新记录](docs/CHANGELOG.md) / [UI 实现](docs/UI_PANEL.md)
- [包内容及 SHA-256](BUILD_MANIFEST.json)
- [MIT 许可](LICENSE.txt) / [第三方声明](THIRD_PARTY_NOTICES.md)

非官方同人 Mod，与 Larian Studios、Wizards of the Coast 无隶属关系。
