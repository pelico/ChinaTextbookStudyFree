# 学习游戏化改造方案（分支 game 暂存）

> 状态：**暂存中（规划草案，未开发）**
> 适用范围：扣宝石机制 + 商店改造（提升小孩兴趣度）
> 本文件只记录方案与实现要点，具体开发在 `game` 分支上推进，成熟后合并回 `main`。

---

## 一、扣宝石机制（机会成本法 C）

### 产品规则
- **不扣任何现有宝石**，采用"机会成本"而非"惩罚"。
- 断签判定：`today()` 与 `lastActiveDate`（YYYY-MM-DD）差值 >= 2 视为"连续 2 天未登录"。
- 断签时**当天签到奖励为 0**（正常为 +N 宝石），直到恢复连续打卡才重新发放。
- 提示话术：情绪正面，如"连续打卡中断，今天没有签到宝箱，明天继续哦"。
- 家长开关**默认关闭**，避免打扰现有用户。

### 涉及文件
- `apps/web/src/store/progress.ts`
  - `claimDailyReward`（约 L369）：断签时 `gems = 0`，并推送提示。
  - 断签判定基于 `streak` / `lastActiveDate` 同步字段。
- `custom_server.py`
  - `parent_settings` 增加字段：`streak_penalty_on`、`penalty_grace_days`（宽限天数）。
  - `[parent/settings]` 返回、`[parent/public-settings]` 下发（约 L2304/L2321）。
  - `get_public_settings_cached` 需带上新字段。
- 前端：`apps/web/src/app/profile/ProfileClient.tsx`（父设置 section）+ 家长模式 UI 加开关与宽限天数设置。

### 落地要点
- delta 同步保证多设备只扣一次，用 `lastActiveDate` 做幂等幂等。
- `public-settings` 短缓存 TTL 已在用（~5s），新开关可沿用，家长改后前台轮询生效。

---

## 二、商店改造（三段内容）

现状：`progress.ts` 已有 `buyCosmetic` / `owned` / 集合（如 `skin_fox` / `cat`），**结算系统已存在，缺的是内容供给与展示**。

### 1. 扩展装扮内容
Cosmetic 增加分类与批量资源：
- **skins 皮肤**：现有 `cat/fox` 扩到十几二十个（兔子、熊猫、恐龙、宇航员…）。
- **accents 配饰/挂件**：帽子、领结、眼镜等。
- **frames 边框**：头像 / 成就卡边框。
- **titles 称号**：文字称号（"数学小达人"等），开销低、展示明显。
- **theme 主题配色**：主页配色主题。

恒定模型：`{ id, category, rarity, price, available: true/false }`。
相关文件：`apps/web/src/lib/cosmetics.ts`、`apps/web/src/store/progress.ts`。

### 2. 稀缺限时机制
- 稀有度分级：`common / rare / legendary`。
- **每日轮换**：每天商店有一两款 rare/legendary"今日特惠"，用 `todayStr()` 做**确定性 seed**（同一设备同日见同一款，可离线、跨端一致、无需服务端随机）。
- **解锁条件**：部分 legendary 需"连续打卡 >= N 天"才可购买（把坚持学习与收藏绑定）。

### 3. 装扮可见展示
- **首页/主页主角**：装备的 skin 立即替换当前 Mascot。
- **连胜页 / 荣耀墙 / 成就卡**：展示边框 + 称号 + 挂件（复用 `equipCosmetic` 自动装备逻辑）。
- 相关文件：`Mascot.tsx`、`MascotSkinOverlay.tsx`、`AchievementWall.tsx` 等。

---

## 三、工程注意
- **数据版本号**：cosmetic 结构变更需 bump 版本，老客户端对新字段用 `??` 兜底，避免闪崩。
- **确定性轮换**：用 `hash(tier, todayStr())` 决定每日特惠，不加服务端随机状态。
- **跨端同步**：`owned` / 装备状态走现有 delta 同步，确保手机 / Web 一致（沿用之前宝石 delta 修复的经验）。

---

## 四、开发顺序（每阶段独立、可测、可回滚）
1. ① 机会成本扣宝石 + 家长开关（含后端字段、数据模型、前端 UI）
2. ② 装扮内容扩展（数据结构 + 批量资源）
3. ③ 稀缺限时机制（稀有度 + 每日轮换 + 解锁条件）
4. ④ 装扮可见展示（首页 / 连胜页 / 荣耀墙联动）

## 五、命名 / 发布说明
- 开发分支：`game`（git 名不含 `:`，冒号是 ref 保留字符）。
- `:game` 是目标 **Docker 镜像 tag**（产物标记），待本功能成熟发布时通过构建生成，当前仅规划。
- Docker CI（`docker-publish.yml`）当前仅 `main` 触发、tag 为 `latest` + `sha`，发布 game 版时需另行安排构建与 tag。