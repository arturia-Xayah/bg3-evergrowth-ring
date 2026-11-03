# API 与格式核对记录

核对日期：2026-11-03。这里只记录实际查阅的来源和实施决策，不把文档/源码阅读当成运行验证。

## 0.4.1 自定义图标资源

- 官方[Adding Skill and Item Icons](https://docs.baldursgate3.game/Adding_Skill_and_Item_Icons)确认64px图集、144px手柄、380px悬浮图、Mods下GUI的两类目标目录，以及物品在RootTemplate中填写Icon名称。此前继承的原版图标在本版改为ER_Item_EvergrowthRing，3D模型和材质仍继承原版。
- 对照图标工具作者[app.js，8681d7ea0a6b1058fd6a06043a46c5ddb0baf017](https://github.com/Atamg1994/Bg3_Icon_bulder/blob/8681d7ea0a6b1058fd6a06043a46c5ddb0baf017/app.js)的TextureAtlasInfo/IconUVList、Content/UI下TextureBank和config→entries→Object→entries元数据结构。元数据逻辑键使用.png，物理纹理使用.DDS；实际w/h与mipcount按本包DDS填写。该工具是作者实现参考，不冒称为本机Toolkit导出。
- 纹理使用BC3/DXT5，透明通道保留，单mip；DDS头按[微软DDS格式说明](https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide)实现。Node可选工具使用sharp 0.35.5做尺寸适配和sRGB编码，dxt-js 0.0.3做BC3压缩；不复制游戏图像。导出后解压回读，再核对透明中心并目视检查64px预览。
- 图集UV必须以LSX保留，而TextureBank和GUI元数据编译成LSF v7。这是打包器新增的特例；不再错误排除运行时图集文件。
- 仅完成资源/包检查，没有运行Toolkit或游戏；不能保证图形后端、旧物品缓存或手柄界面的实际显示。验收应覆盖新生成物品和旧存档已有实例。

## 0.4.0 小队共享接口核对

- 使用下文同一已核对提交的 `BG3ModdingTools/generated/Osi.lua`：`Osi.IsPartyMember(character, includeNotControlable) -> integer`、`Osi.IsInPartyWith(character, target) -> integer`，分别两个输入；返回值严格与1比较。
- 官方 [IsInPartyWith](https://docs.baldursgate3.game/index.php?title=IsInPartyWith) 说明查询两角色是否同队，Osiris定义为两个输入加一个输出；SE Lua把输出作为返回值。
- 官方 [IsPartyMember](https://docs.baldursgate3.game/index.php?title=IsPartyMember) 页面摘要定义缺少一个输入，但示例是 `IsPartyMember(character, 1, 1)`，与生成声明的 `includeNotControlable` 输入及输出bool一致。实际采用生成声明的2个Lua输入，没有盲从不完整摘要。
- 使用 `IsPartyMember(id, 1)`，允许引擎仍认定属于小队但暂不可控的成员；再用 `IsInPartyWith` 校验与主机/击杀者同队。先确认击杀者属于主机小队，再从已核对的 `GetAllEntitiesWithComponent("ServerCharacter")` 路径枚举当前已加载同队非召唤成员，读取死亡时Ring/Ring2装备。不依据缓存的佩戴者表或历史招募名单发放。
- 不加距离或同场战斗过滤。未加载角色不创建补发记录；营地/跟随/分区分类依原生查询，不宣称所有待命角色都被判为同队。默认召唤物代杀仍不触发奖励。
- 每枚唯一物品UUID获完整maxHP额度，先准备全部新状态再写入；一份持久死者防重记录覆盖全队。升级特效按佩戴者去重，所有受影响佩戴者延后重算Boost并推送面板。调试命令 `!er_addhp`仅向指定角色的每枚戒指发放完整额度。
- 接口文档与模拟调用已核对；未运行游戏，尤其不能据此声称营地/联机/临时控制角色分类已经实测。

## BG3 Script Extender

使用仓库主分支快照：

- [Norbyte/bg3se，4c85de82264b985d2796cddd012b08847c6527fd](https://github.com/Norbyte/bg3se/tree/4c85de82264b985d2796cddd012b08847c6527fd)，提交日期2026-11-02。
- [resource.h](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/resource.h) 的 `RES_DLL_MAJOR_VERSION` 为34；[API.md](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/Docs/API.md) 标题仍标为v30。这里按源码34设置 `RequiredVersion`，没有声称实际运行过34，也没有把 GitHub updater 下载包的版本等同于运行时版本。
- API文档核对了 `Mods/<Folder>/ScriptExtender/Config.json`、BootstrapServer/BootstrapClient、`Ext.Require`、`Ext.Events`、`Ext.OnNextTick`、`Ext.RegisterConsoleCommand`、`Ext.Entity.Get`、`Entity:Replicate` 与 UserVars/ModVars。
- 使用推荐的 `Ext.Vars.RegisterUserVariable` 和 `Ext.Vars.RegisterModVariable`，不使用已经废弃的 PersistentVars。服务器和客户端启动时都注册相同的变量定义；状态写回通过直接赋值，避免只修改嵌套表而漏掉 dirty 标记。

## Osiris 调用及事件

交叉核对了 [LaughingLeader/BG3ModdingTools，ab343b616d8b7a37eb487c75010a3ffb95e918bf](https://github.com/LaughingLeader/BG3ModdingTools/tree/ab343b616d8b7a37eb487c75010a3ffb95e918bf) 的 `generated/Osi.lua`、`generated/Osi.Events.lua`、`generated/Ext.Osiris.RegisterListener.lua`，及 Larian 文档可访问的页面。该项目的生成声明并不是本机游戏导出的函数表；需要游戏内验收。

| 接口 | 实际使用签名/行为 |
| --- | --- |
| `KilledBy` | 4参：defender、attackOwner、attacker、storyActionID。直接击杀者与归属者分开使用，不用最后一次伤害猜归属 |
| `Resurrected` | 1参character，重置死者的结算防重记录 |
| `Equipped`、`Unequipped` | 各2参item、character |
| `LeveledUp`、`RespecCompleted` | 各1参character；不是臆造一个带等级参数的版本 |
| `UsingSpell` | 5参caster、spell、spellType、spellElement、storyActionID，用于查看动作 |
| `GetEquippedItem` | character、slotName → item，使用 `Ring`、`Ring2` |
| `GetTemplate` | target → root template；按模板识别Mod戒指，按实际item UUID保存成长 |
| `GetMaxHitpoints` | entity → maximum HP；不用 `GetHitpoints` 的死亡时当前值 |
| `IsSummon` | potentialSummon → integer；明确与0比较，避免Lua把0当真值 |
| `AddBoosts` | object、boosts、sourceID、cause |
| `RemoveBoosts` | object、boosts、removeOnlyFirstDescMatch、sourceID、cause |
| `TemplateAddTo` | itemTemplate、inventoryHolder、count、showNotification |
| `OpenMessageBox` | 历史0.1/0.2版本使用；0.3改为NetChannel打开客户端实时面板，控制台保留文字回退 |

相关官方页面：[KilledBy](https://docs.baldursgate3.game/index.php?title=KilledBy)、[GetEquippedItem](https://docs.baldursgate3.game/index.php?title=GetEquippedItem)、[OpenMessageBox](https://docs.baldursgate3.game/index.php?title=OpenMessageBox)。KilledBy文档说明攻击者未知时可能不会发送事件，因此没有用 Died 事件补发不可靠经验。

## ECS 字段

从上述 BG3SE 快照的 [ExtIdeHelpers.lua](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/IdeHelpers/ExtIdeHelpers.lua) 核对：

- `EntityHandle` 的 `Uuid.EntityUuid`、`Vars`、`IsCharacter`、`ActionResources`。
- `Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")` 用于服务器角色枚举。
- `ActionResources.Resources` 是按资源UUID索引的资源条目数组。每条读取 `Level`、`Amount`、`MaxAmount`；只写 `Amount`，不直接写上限。
- 仅在换装/升级改变原生资源Boost后，向下钳制SpellSlot、WarlockSpellSlot以及0.2.0新增的ActionPoint、BonusActionPoint、Movement当前可用值，调用 `entity:Replicate("ActionResources")`。不修改气、术法点等其他资源。

写入Amount的格式存在，**并不意味着该写入与休息/消耗/原生重算交互已经游戏实测**。

## Boost 与实际游戏数据

在 [Norbyte BG3 数据检索](https://bg3.norbyte.dev/search) 查询了 `_Ring`、`ARM_Ring`、普通戒指模板、`SpellSlot`、`WarlockSpellSlot`、`Shout_SecondWind` 及豁免Boost实例。原始查询和完整验证用Stats探针归档在本目录的验证证据文本中。

核实结果：

- `_Ring` 是Armor Stats父项，装备Slot为Ring。
- `ecf4a8a4-7859-4a82-8c08-0c9526f29500` 是原版 `LOOT_GEN_Ring_A_Simple_Gold` 模板；图标为 `Item_LOOT_GEN_Ring_A_Simple_Gold`。只继承其外观/物理资源，使用新Stats和新模板UUID，不修改原版戒指。
- `SpellSlot` UUID为 `d136c5d9-0ff0-43da-acce-a74a07f8d6bf`、补充类型Rest；`WarlockSpellSlot` 为 `e9127b70-22b7-42a1-b172-d02f828f260a`、补充类型ShortRest。两者定义的MaxLevel都是9，这不代表原版提供7–9环法术。
- `Shout_SecondWind` 在SpellProperties内治疗。因此查看动作在继承后显式清除SpellProperties、SpellSuccess、TooltipDamageList、UseCosts、Cooldown、说明参数和视觉音效，避免附带治疗或消耗。
- [Boosts.h](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/GameDefinitions/Components/Boosts.h) 中Ability有ValueCap与DontAdjustHealth；DamageBonus有Amount、DamageType和CriticalHit；ActionResourceValue有ResourceUUID、Level、Amount。
- [Stats.inl](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/GameDefinitions/Enumerations/Stats.inl) 明确列出13种实际DamageType，以及None/Sentinel。未添加不存在的Physical伤害。
- `IsAttack()` 的含义参考了 [Bg3-Khn-Libs 的原游戏条件导出](https://github.com/NellyDevo/Bg3-Khn-Libs/blob/master/Khn.CommonConditions.lua)：近战或远程攻击，覆盖武器/法术/徒手。该导出不是本机最新游戏的现场采集；本版仍以游戏自身执行的条件为准。

将三份Stats文件和n=0/3/4/5/9/10/20/200的 `Core.Boosts` 包装成临时Status提交给 [Norbyte Stats Validator](https://bg3.norbyte.dev/stats-validator)，返回 **Stats validated with no errors!**。包含能力值显式cap、六种豁免、攻击、DC、AC、通用伤害、13种条件伤害、普通/契约位，以及0.2.0新增的技能、先攻、移动、暴击、动作、附赠动作。格式通过不证明最终数值行为。

RootTemplate经 [Norbyte LSX Validator](https://bg3.norbyte.dev/lsx-validator) 校验。第一次提示缺少LevelName；已加入空LevelName，重新校验返回 **LSX validated with no errors!**。meta.lsx提交后返回“不匹配已知schema”，因此不宣称meta通过该在线schema校验；其结构经过本地XML解析和ModuleInfo字段检查。

## 打包格式

- 核对 [Norbyte/lslib，6f5f6987d10d8485876b8368431c948e4dea4f83](https://github.com/Norbyte/lslib/tree/6f5f6987d10d8485876b8368431c948e4dea4f83) 的 `LSLib/LS/PackageFormat.cs`、`PackageWriter.cs`、`Enums/PackageVersion.cs` 与Localization实现。
- PAK为LSPK v18；v16式40字节头，v18式272字节文件目录；内容不压缩，目录为合法的LZ4 literal block；数据相对40字节头按64字节对齐；MD5采用按文件顺序累积内容后逐字节+1的LSLib约定。
- RootTemplate实际编译为二进制LSF v7文件 `Public/EvergrowthRing/RootTemplates/_merged.lsf`。没有只打包XML冒充可加载模板。LOCA实际编译成二进制，未只打包XML。
- 编译使用 MIT 项目 [crazyace/bg3-forge](https://github.com/crazyace/bg3-forge/tree/10fa2959b472bb71ba2714d274b9828e59cd4576) 的LSF/LOCA实现，包含源码和许可。其作者报告过零售版加载测试，但**那是该工具作者的测试，不是本戒指Mod的测试**。
- 自有小型PAK writer独立于bg3forge的writer。除了bg3forge回读逐文件SHA-256比对，还用 `struct` + 原生 `lz4.block` 独立解析目录、检查偏移/对齐、内容和MD5。

未在本环境运行官方 Divine.exe、Windows游戏或BG3SE DLL，没有声称使用官方工具成功安装/验证本Mod。

## 0.2.0新增核对

查询Norbyte游戏数据检索的ActionResourceDefinition，确认ActionPoint UUID `734cbcfb-8922-4b6d-8330-b2a7e4c14b6a`、BonusActionPoint UUID `420c8df5-45c2-4253-93c2-7ec44e127930`、Movement UUID `d6b2369d-84f0-4ca4-a3a7-62d2d192a185`。三者MaxLevel=0、ReplenishType=Turn。Movement查询会同时返回同名动画资源；本版取的是ActionResourceDefinition，不使用动画资源ID。

从相同BG3SE快照核对RollType.SkillCheck、Initiative Boost、ReduceCriticalAttackThreshold的int32 Reduction和ActionResourceValue字段。使用原生 `RollBonus(SkillCheck,n)`、`Initiative(floor(n/4))`、`ActionResource(Movement,n,0)`、`ReduceCriticalAttackThreshold(floor(n/10))`、`ActionResource(ActionPoint,floor(n/5),0)`、`ActionResource(BonusActionPoint,floor(n/4),0)`；零值取整项省略。双戒指按实例分别取整后相加。格式探针与校验响应随本版归档，不能代替游戏里对动作上限、移动单位、暴击实际下限的验收。

实时界面仅评估Noesis UI与ViewModel变更通知、UserVars客户端同步的已存在接口；没有实施或验证具体的原版tooltip实例绑定点。

## 0.3.0新增核对

动作改为floor(n/10)，附赠动作改为floor(n/8)。新探针覆盖n=0/4/7/8/9/10/19/20/200。上面0.2.0段落保留为历史记录，当前公式以本段和Core.lua为准。

在[Norbyte效果资源检索](https://bg3.norbyte.dev/search?q=LevelUp%20type%3Aeffect)核对原版VFX_UI_LevelUp_01：ID `453e009e-aed7-8ef0-d2bc-8e9ba79065df`，Duration=3、Looping=False，原资源路径为Public/Shared/Assets/Effects/Effects_Banks/UI/VFX_UI_LevelUp_01.lsfx。依赖中包含对应音效资源，但没有实测声音是否随本调用播放，因此不承诺音效。实际只打包资源引用，不复制原版资产。

[PlayEffect官方文档](https://docs.baldursgate3.game/index.php?title=PlayEffect)与generated/Osi.lua确认四参数Object、EffectResource、Bone、Scale；无指定骨骼时使用默认骨骼。本版调用 `Osi.PlayEffect(character, effectUUID, "", 1.0)`，在真实成长后推迟一Tick执行。重复事件、读档、普通进度增加不发起播放；一次跨多级/两枚一起升级合并一次。不调用LevelUp/人物经验函数。

从同一BG3SE快照的ClientIMGUI.inl、ExtIdeHelpers.lua及IMGUI/Objects.h核对Ext.IMGUI.NewWindow与窗口/文字/下拉菜单/进度条属性。SelectedIndex为ImGui的零起始索引；OnChange/OnClick可赋Lua回调；显示文本修改Label、进度条修改Value/Overlay。窗口保持打开时原地更新已有控件，不反复创建窗口。

从LuaScripts/Libs/NetChannel.lua核对CreateChannel、SetRequestHandler、SetHandler、RequestToServer、Broadcast、SendToClient；SendToClient可用角色GUID定位所属客户端。频道在两端启动时都创建。UI快照为普通可序列化表，客户端只有只读查询。经验UserVar继续仅服务器写入；KnownRings为新的持久ModVar索引，客户端不直接写入。

BG3SE IMGUI.cpp根据游戏语言使用默认字体；中文游戏对应NotoSerifSC-Regular.otf及ChineseFull字形。SE源码同时包含DX11/Vulkan后端，但本包没有实际验证任一后端。界面不是Noesis对象，所以没有依赖未知原版tooltip节点或编造Noesis绑定路径。

相关源码：[ClientIMGUI](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/Lua/Libs/ClientIMGUI.inl)、[NetChannel](https://github.com/Norbyte/bg3se/blob/4c85de82264b985d2796cddd012b08847c6527fd/BG3Extender/LuaScripts/Libs/NetChannel.lua)。
