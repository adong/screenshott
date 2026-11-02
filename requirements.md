# Mac 截图 App — 需求决策记录

> Grill session started 2026-11-01. Reference app: **Shottr** (shottr.cc, v1.9.3).
> Living doc: closed branches = decided, open branches = still to grill.

## Shared model (so far)

- **Why:** A (自用，替代付费) + B (练 Swift/macOS 原生) + D (以后做成产品)。不是 C（不做 AI 打通差异化）。
- **Phase 1 = 自己用**；Phase 2 = 产品化。
- **Reference = Shottr**：小（2.3 MB dmg）、快（17 ms 抓图 / ~165 ms 显示）、原生、menu bar app、键盘优先、面向"在意像素"的人。
- **分发 = 直装 DMG**（Shottr 的路）。不上 Mac App Store → 不开沙盒 → v1 直接用辅助功能权限做自动滚动。
- **App 名 = Screenshott**，工程目录 = `~/screenshott`。
- **Stitches = 多张拼一张**（Shottr 的 Combine Screenshots），和长截图是两个功能，都进 P0。
- **截图模型 = 不止一种，热键 = 预设**：每个热键绑一个预设 =（画面：冻结 / 实时）×（选择：不选 / 框选 / 点窗口）×（Enter 后的动作）。区域截图默认用冻结遮罩；实时框选本来长截图就要用；Shottr 流 = 冻结 + 直接进编辑器。编辑器是可选的下一步，不是必经。
- **v1 预设表已定**（见"v1 预设表"一节）：⌘⇧1 全屏、⌘⇧2 区域、⌥⌘⇧1 全屏进编辑器、⌥⌘⇧2 长截图；默认动作 = 复制 + 存档到 `~/Pictures/Screenshott/` + 缩略图。
- **v1 编辑器** = 裁剪、缩放 / 平移、拼图画布、复制 / 存档 / 拖出 + 4 个标注工具：箭头、矩形、文字、马赛克。文档模型是对象层：每张截图都是独立的图片对象，马赛克 / 裁剪作用在各自对象上。
- **标注可再编辑**：存档时 PNG（拍平）进 `~/Pictures/Screenshott/`，工程（原图 + 对象 JSON）进 `~/Library/Application Support/Screenshott/`，按 PNG 文件名对应；从缩略图或 PNG 重新打开可继续改。马赛克带"实色遮盖"模式；导出的 PNG 里被遮像素真的被替换，原图只留在本机工程里。

## Closed branches

| # | Decision | Answer | Date |
|---|---|---|---|
| 1 | 为什么自己做 / 给谁 | A+B+D；先自用；参考 Shottr | 2026-11-01 |
| 2 | D 的分发渠道 | 直装 DMG：Developer ID 签名 + 公证 + 自己卖 license（FastSpring / Paddle / Lemon Squeezy）+ Sparkle 更新。$99/年 Apple Developer 只在 Phase 2 才需要；Phase 1 用自签名证书 | 2026-11-01 |
| 9a | 工程位置 | `~/screenshott` | 2026-11-01 |
| 9b | App 名字 | Screenshott（和目录同名） | 2026-11-01 |
| 3 | "Stitches" 的含义 | 多张截图拼到同一画布（= Shottr Combine Screenshots），P0。长截图的帧拼接是另一回事（算法找重叠）；Combine 是画布排版（吸附、间距、对齐），画布以后给标注复用 | 2026-11-01 |
| 4 | 截图模型 | 三种都要，用预设组合（Alan："为什么只能是一种？"）。冻结遮罩是区域截图的默认：按下即冻结，带放大镜 / 方向键 1px 微调 / 窗口吸附。实时框选：长截图和重复上次区域本来就要这条路径，顺便开放成预设。Shottr 流 = 冻结 + 直接进编辑器 | 2026-11-01 |
| 4a | 多显示器选区 | 默认：选区限在起点所在的那块屏，不跨屏（同系统 ⌘⇧4）。每块屏一个遮罩窗口。Alan 可推翻 | 2026-11-01 |
| 4b | Retina 输出 | 默认：按物理像素（2x）保存；设置里可选降到逻辑像素（Shottr 也有这个开关）。Alan 可推翻 | 2026-11-01 |
| 6 | v1 预设表 | 按草案通过：7 个预设、默认热键、遮罩通用键、自动存档到 `~/Pictures/Screenshott/`、拼图走"添加截图"按钮不占热键 | 2026-11-01 |
| 7 | v1 编辑器范围 | 带 4 个标注工具（箭头、矩形、文字、马赛克）；手绘、高亮、聚光灯、步骤编号、弯箭头 → P1。理由：没标注替代不了付费软件；拼图画布已是对象层，标注只是多几种对象；马赛克逼着每张截图都做成能单独打码的图片对象，避开 Shottr"先 Rasterize"的坑 | 2026-11-01 |
| 7a | 标注能否回头改 | 可再编辑。工程文件 = 原图 + 对象 JSON，放 App Support，不放图片文件夹；导出 PNG 永远拍平。马赛克加"实色遮盖"模式（马赛克文字可被 Depix / Unredacter 还原），导出时被遮像素真替换 | 2026-11-01 |
| 5 | 长截图 v1 验收 | 按"长截图 v1 验收"一节的清单通过 | 2026-11-01 |
| 3a | 拼图布局 | 默认：v1 只做自动排列（上下 / 左右、统一间距、对齐），自由拖放 → P1。Alan 可推翻 | 2026-11-01 |
| 8 | UI 技术栈 | 默认：混合。AppKit 管热路径（冻结遮罩窗口、编辑画布、缩略图面板）；SwiftUI 管冷界面（设置、预设编辑、菜单栏菜单），用 NSHostingView 接起来。纯 SwiftUI 做不好每屏一个顶层无边框遮罩窗口和大图画布。Alan 可推翻 | 2026-11-01 |
| 9c | 最低 macOS | 默认：14+（`SCScreenshotManager`、Observation 框架都要 14）。用到 15+ 的 API 再上调。Alan 可推翻 | 2026-11-01 |
| 8b | 工程构建方式 | 只用 Command Line Tools，不装 Xcode（Alan："xcode cli tool 就够了吧？"，已核实属实）。SwiftPM + `scripts/bundle.sh` 拼出 `Screenshott.app`（Info.plist、LSUIElement、签名）。CLT 已带：Swift 6.4、lldb、sourcekit-lsp（Vim）、swift-format、Swift Testing、notarytool、stapler；系统自带 codesign、iconutil、hdiutil、pkgbuild、sample、leaks、heap、vmmap。缺的 actool / ibtool / Instruments（xctrace）/ XCTest 都用不上或有替代 | 2026-11-01 |
| 10 | 可扩展：别人带自己的工作流（类 Alfred Workflows，Alan 2026-11-02 提出） | **只开放"截完之后"这一层**（Alan 选的）。截图方式和编辑器工具不开放，以后真要开再单独议（Phase 2）。具体设计见下方"Workflows（#10）"一节 → M7 | 2026-11-02 |

## Workflows（#10，2026-11-02 已定范围）

扩展面 = 截完之后。一张图截好了，workflow 决定它接下来去哪。

- **Workflow = 触发 → 步骤链**，打包成 `.screenshottworkflow`（zip：`workflow.json` + 脚本 + 图标），双击安装到 `~/Library/Application Support/Screenshott/Workflows/`。
- **触发**：出现在缩略图 / 遮罩的动作栏；也能设成某个预设的 Enter 动作，所以能有自己的热键；或者从菜单栏跑（对最近一张截图）。
- **步骤类型**：`script`（任意语言的可执行文件）、`shortcut`（跑一个苹果"快捷指令"，零代码）、`open-url`（模板 URL）、内置动作（复制、存档、贴图、OCR、进编辑器）。
- **数据约定**：图片路径和元数据 JSON 走 stdin 和环境变量（`SCREENSHOTT_IMAGE` 等）；脚本往 stdout 打 JSON 告诉 app 下一步：`clipboard` / `notify` / `open` / `image`（换一张图交给下一步）。
- **进程外运行**：第三方代码不进 app 进程，崩了不拖垮截图；安装时列出要跑的脚本让用户确认。
- **内置动作走同一个接口**（M2 起），外部 workflow 只是又一种动作来源。
- **默认：脚本不继承 Screenshott 的权限**。macOS 把子进程的权限算在父 app 头上：不处理的话，workflow 脚本能用 Screenshott 的屏幕录制授权随时偷截屏，M5 之后还能用它的辅助功能授权操作键盘鼠标。脚本已经拿到了那张图，用不着这些权限。做法：启动脚本时放弃"责任进程"（`posix_spawn` + `responsibility_spawnattrs_setdisclaim`，iTerm2 / LLDB 用的私有接口；DMG 分发可以用私有 API），脚本要截屏得自己去要授权。[M7 开工时验证：disclaim 后的子进程调 `CGPreflightScreenCaptureAccess` 应返回 false] Alan 可推翻。

## Open branches

需求访谈主体已结束（2026-11-01），#10 也已定（2026-11-02）。以下不挡开工，到对应阶段再定：

- **自签名代码签名证书**：M0 测权限前，Alan 在钥匙串访问里手动建（证书助理 → 创建证书 → 自签名根证书，类型"代码签名"）。不建的话每次重新编译屏幕录制授权都会失效。
- **Bundle ID**：默认 `com.adong.Screenshott`，Alan 可改。
- **$99 Apple Developer 账号**：Phase 2 才买。
- **P1 / P2 内部顺序**：v1 完成后再排。

## v1 预设表（2026-11-01 已定）

热键规律：1 = 全屏类，2 = 区域类，加 ⌥ = 进阶变体。避开系统 ⌘⇧3/4/5。

| 预设 | 画面 | 怎么选 | Enter 后 | 默认热键 |
|---|---|---|---|---|
| 区域 | 冻结 | 拖框；单击 = 吸附窗口 | 复制 + 存档 + 缩略图 | ⌘⇧2 |
| 全屏 | 冻结 | 不用选（鼠标所在屏） | 复制 + 存档 + 缩略图 | ⌘⇧1 |
| 全屏进编辑器（Shottr 流） | 冻结 | 在编辑器里选、裁 | 打开编辑器 | ⌥⌘⇧1 |
| 长截图 | 实时 | 拖框 → 自动滚 / 手动滚 | 拼完 → 缩略图 | ⌥⌘⇧2 |
| 实时区域 | 实时 | 拖框，松手才截 | 复制 + 存档 + 缩略图 | 不绑 |
| 重复上次区域 | 实时 | 不用选 | 复制 + 存档 + 缩略图 | 不绑 |
| 延时（3 / 5 / 10 s） | 冻结 | 倒计时后进遮罩 | 同"区域" | 不绑 |

遮罩里的通用键（覆盖预设的 Enter 动作）：Enter = 预设动作 · ⌘C = 只复制 · ⌘S = 另存为 · E = 进编辑器 · P = 贴图（P1）· Esc = 取消。

存档默认位置：`~/Pictures/Screenshott/`（不放桌面）。自动存档的理由：剪贴板会被下一次复制覆盖，存档保证截过的图不会丢。

拼图（Combine）不是独立热键：在缩略图或编辑器上点"添加截图"，下一张截图追加到当前画布。

## 长截图 v1 验收（2026-11-01 已定）

| 项 | v1 标准 |
|---|---|
| 方向 | 只做竖向；横向 → P2 |
| 自动滚必须能用 | Safari、Chrome、Slack、微信、备忘录、Mail |
| 手动滚必须能用 | 终端（本机装了 cmux、Ghostty、iTerm2、Terminal）、VS Code、Cursor、Finder 分栏 —— Shottr FAQ 证实这类 app 自动滚会出错 |
| 固定头尾（sticky header / 底部输入框） | 自动识别连续几帧里不变的顶部 / 底部行：顶部只留第一帧的，底部只留最后一帧的 |
| 自动滚何时停 | 连续两帧画面相同（到底了），或按 Enter / Esc |
| 手动滚何时停 | 按 Enter |
| 最大长度 | 30,000 物理像素，到了自动停并保存（宽 3000 px 时约 360 MB 内存） |
| 过程中 | 屏幕边上显示拼接进度的窄条预览，拼错能当场看到 |
| 已知不保证 | 页面里有动画、视频、懒加载跳动时可能错位，v1 接受 |

## v1 里程碑（草案）

每个里程碑都是能跑的竖切片，做完能拿来用，不是"写完一层再写下一层"。

| 里程碑 | 内容 | 做完能干什么 |
|---|---|---|
| **M0 骨架** ✅ 2026-11-02 验收通过（真改代码的重编 cdhash=f19deb15 启动即 screenCapture=true，授权跨重编保留） | `Package.swift` + `bundle.sh` + 自签名签名；菜单栏 app；屏幕录制授权引导；⌘⇧1 全屏 → 复制 + 存档 | 验证整条管线：编译 → 打包 → 签名 → 授权 → 截图 → 剪贴板，且重新编译后授权不丢 |
| **M1 冻结遮罩** | 每屏一个遮罩窗口；框选、单击吸附窗口；放大镜、方向键微调；多显示器 + Retina；浮动缩略图 | ⌘⇧2 日常区域截图可用 |
| **M2 预设与热键** | 预设模型（冻结 / 实时 × 选择 × 动作）；7 个预设；热键录制（KeyboardShortcuts）；设置页；遮罩通用键；**动作接口**（复制、存档、编辑器等内置动作都走它，给 #10 workflow 铺路） | 热键可改，Shottr 流、延时、重复区域可用 |
| **M3 编辑器** | 对象层文档模型；裁剪、缩放 / 平移；箭头、矩形、文字、马赛克（含实色遮盖）；工程文件存取 | 能标注，能重新打开再改 |
| **M4 拼图** | 编辑器 / 缩略图上"添加截图"；自动排列 | 多张拼一张 |
| **M5 长截图** | 实时框选；自动滚（辅助功能权限）+ 手动滚；重叠匹配拼接；固定头尾去重；进度预览；30,000 px 上限 | 通过长截图验收清单 |
| **M7 Workflows**（#10：只开"截完之后"） | `.screenshottworkflow` 格式、安装与确认、script / shortcut / open-url 步骤、stdout JSON 协议、脚本放弃责任进程（不继承屏幕录制 / 辅助功能授权）、3 个示例 workflow | 别人能写、能分享、能装自己的工作流 |
| **M6 打磨** | 内置计时（`ContinuousClock` + `os_signpost`）+ `--bench` 模式连截 N 次出 p50 / p95，对标 17 ms / 165 ms，热点用 `sample` 查；开机启动；`iconutil` 做图标 | 能替代 Shottr 当主力 |

## 开发备注

- **构建**：`scripts/bundle.sh [debug|release]` → `dist/Screenshott.app`。如果 app 正在运行，脚本会先退出它、编完再重开（否则 `open` 只会激活旧进程，测的还是旧代码）。
- **测试**：`scripts/test.sh`（Swift Testing，11 个，2026-11-02 全过）。只装 Command Line Tools 时，swift-build 有时不加载 `host/plugins/testing/` 下的宏插件，所有 `@Test` 都会报 "plugin for module 'TestingMacros' not found"，脚本会显式传 `-plugin-path`。
- **图标**：`scripts/make-icon.sh` 用 `Tools/MakeIcon` 里的 CoreGraphics 矢量代码按每个尺寸单独绘制，再用 `iconutil` 打包成 `Support/AppIcon.icns`（.icns 提交进 git，中间 PNG 不提交）。菜单栏图形在 `AppDelegate.menuBarGlyph` 里用代码画，是 template 图，系统按深浅色菜单栏自动着色。
- **启动日志带 CDHash**：`launch 0.1.0 (1) cdhash=xxxxxxxx …`。缓存命中的构建会重新签同样的字节，CDHash 不变；只有 CDHash 变了还不用重新授权，才能证明授权真的跨重编保留。
- **Claude 会话的沙盒里编不了**：SwiftPM 往 `/var/folders/hs/…/T`（临时文件、原子写）和 `/var/folders/hs/…/C`（clang 模块缓存）写东西，沙盒拒绝；另外 SwiftPM 自己的 `sandbox-exec` 不能嵌套，需要加 `--disable-sandbox`。home-guard 又禁止在沙盒外跑仓库脚本。所以目前 `bundle.sh` 由 Alan 在自己的终端跑。想让 Claude 自己编：在 `sandbox.filesystem.allowWrite` 里加 `/private/var/folders/hs/967572j15p385840s129d2r40000gn`，然后用 `swift build --disable-sandbox`。
- **签名证书**：钥匙串里已有自签名证书 "NoteTaker Local Dev"（另一个项目建的）。`bundle.sh` 找不到 "Screenshott Dev" 时会自动用它，TCC 授权照样能跨重编保留。想分开就建一个 "Screenshott Dev"，脚本会优先用。
- **Shottr 冲突**：本机装了 Shottr，默认占 ⌘⇧1 / ⌘⇧2。测 Screenshott 时先退出 Shottr，或者改掉它的热键。注册失败时菜单里会显示"⌘⇧1 is taken by another app"。
- **日志**：`~/Library/Logs/Screenshott.log`，每次截图记录 list / grab / encode / copy+save 各段耗时，M6 对标 17 ms 用。
- **UI 文案**：先用英文（以后做产品要本地化，英文当基准语言）。Alan 可推翻。

## Shottr 功能盘点 → 我们的分层（草案，待砍）

| Shottr 功能 | 说明 | 我们 |
|---|---|---|
| 全屏 / 区域 / 任意窗口截图 | Capture Any Window 有独立热键 | **P0** |
| 自定义全局快捷键 | — | **P0** |
| 重复上次区域、延时截图 | Repeat Area / Delayed | **P0**（便宜） |
| 滚动截图 | 自动滚；Terminal / VS Code / Finder 分栏 / MOS 等改滚动的 app 下会失败 → 有手动滚模式 | **P0，两种模式都要**（Alan 天天用 Terminal/VS Code） |
| Combine Screenshots | Add Capture 到同一画布，可并排 | **P0**（= Stitches） |
| 裁剪（选区 + Enter）、缩放、平移 | ⌘1/⌘0/⌘2、Z 点击放大、Space 拖动 | **P0** |
| 复制 / ⌘S 存专用文件夹 / 拖出到其他 app | — | **P0** |
| 浮动缩略图 | Area Capture 预览缩略图 | **P0** |
| 标注：文字、箭头（可弯）、矩形、手绘、高亮、聚光灯、步骤编号 | — | **P0：箭头、矩形、文字**；P1：手绘、高亮、聚光灯、步骤编号、弯箭头 |
| 马赛克 / 擦除（含仅文字模式） | — | **P0：马赛克**；P1：擦除、仅文字模式 |
| OCR + 二维码 | Vision framework，成本低 | P1 |
| 贴图（置顶无边框窗口） | 滚轮缩放 | P1 |
| 屏幕尺子（方向键测距）、取色（Tab / Shift+Tab / C 平均色） | Shottr 的招牌 | P1 |
| 智能选区（A 自动吸附、⌘ 点击选单色块） | — | P2 |
| Backdrop（渐变背景、阴影、圆角） | — | P2 |
| 图片叠加 / before-after 动画、调整尺寸 | — | P2 |
| 物体移除 | — | P2 |
| S3 上传、URL scheme | — | P2（产品期） |
| License、自动更新、公证、引导页 | — | Phase 2（D） |

## 已知技术约束

- 截屏：ScreenCaptureKit `SCScreenshotManager`（macOS 14+）。`CGWindowListCreateImage` 在 macOS 15 SDK 已不可用。
- 热键：Carbon `RegisterEventHotKey`（无需辅助功能权限）；录制 UI 可用 sindresorhus/KeyboardShortcuts。
- 系统 ⌘⇧3/4/5 优先于第三方；想占用需用户先在系统设置里关掉。
- 开发期 ad-hoc 签名 → 每次 rebuild 屏幕录制授权失效 → 需自签名代码签名证书（Alan 在钥匙串里手动建）。
- TCC 授权绑定 app 所在位置：从 Downloads 挪到 /Applications 后旧授权失效（Shottr FAQ 也踩过）。
- 自动滚动需给别的 app 发滚轮事件 → 需辅助功能权限（DMG 直装，不受沙盒限制）。
- 测试用 Swift Testing（`import Testing`）：CLT 里有 Testing.framework，没有 XCTest。
- 图标不走 asset catalog（`actool` 只在 Xcode 里），用 `iconutil` 生成 `.icns`。

## Sources

- https://shottr.cc/ （功能、快捷键、release notes）
- https://shottr.cc/kb/faq （滚动截图失败场景、全屏裁剪工作流、TCC 授权问题）
- Depix（github.com/spipm/Depix，2020）、Bishop Fox Unredacter（2022）—— 马赛克文字可被还原
