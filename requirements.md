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
| 11 | 设置窗口（Alan："I dont see option menu, nor customize shortcuts … where to store files, etc"） | 菜单栏 Settings…（⌘,）。快捷键录制：每个动作一个录制框，Delete 清空、Esc 取消、可一键恢复默认；规则：至少两个修饰键（⇧ 不能单独算）或 F 键，避开 ⌘⇧3/4/5、⌘Space、⌘Tab，不能和另一个动作重复，系统注册失败就提示"被别的 app 占用"并保留旧的。另有：保存位置、保留 Retina 原始分辨率（决策 4b 的开关）、复制到剪贴板、显示缩略图、播放声音、开机启动。自动存档始终开（理由见预设表）。录制器自己写，不用 KeyboardShortcuts 包：它的资源包得另外拷进 .app，漏了 `Bundle.module` 会直接崩 | 2026-11-02 |

## Workflows（#10，2026-11-02 已定范围）

扩展面 = 截完之后。一张图截好了，workflow 决定它接下来去哪。

- **Workflow = 触发 → 步骤链**，打包成 `.screenshottworkflow`（zip：`workflow.json` + 脚本 + 图标），双击安装到 `~/Library/Application Support/Screenshott/Workflows/`。
- **触发**：出现在缩略图 / 遮罩的动作栏；也能设成某个预设的 Enter 动作，所以能有自己的热键；或者从菜单栏跑（对最近一张截图）。
- **步骤类型**：`script`（任意语言的可执行文件）、`shortcut`（跑一个苹果"快捷指令"，零代码）、`open-url`（模板 URL）、内置动作（复制、存档、贴图、OCR、进编辑器）。
- **数据约定**：图片路径和元数据 JSON 走 stdin 和环境变量（`SCREENSHOTT_IMAGE` 等）；脚本往 stdout 打 JSON 告诉 app 下一步：`clipboard` / `notify` / `open` / `image`（换一张图交给下一步）。
- **进程外运行**：第三方代码不进 app 进程，崩了不拖垮截图；安装时列出要跑的脚本让用户确认。
- **内置动作走同一个接口**（M2 起），外部 workflow 只是又一种动作来源。
- **默认：脚本不继承 Screenshott 的权限**。macOS 把子进程的权限算在父 app 头上：不处理的话，workflow 脚本能用 Screenshott 的屏幕录制授权随时偷截屏，M5 之后还能用它的辅助功能授权操作键盘鼠标。脚本已经拿到了那张图，用不着这些权限。做法：启动脚本时放弃"责任进程"（`posix_spawn` + `responsibility_spawnattrs_setdisclaim`，iTerm2 / LLDB 用的私有接口；DMG 分发可以用私有 API），脚本要截屏得自己去要授权。验证办法：`scripts/verify-disclaim.sh` 让 app 把探针 `Tools/TCCProbe` 各起一次（不放弃 / 放弃），记下子进程里 `CGPreflightScreenCaptureAccess()` 的结果。2026-11-03 实机：inherited=true、disclaimed=false，即不处理的话脚本真能借到屏幕录制授权，放弃之后借不到。Alan 可推翻。
- **实现细节和默认**见"M7 Workflows 默认"一节；给作者看的格式说明在 `docs/workflows.md`。

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

### 长截图实测（待 Alan 手试）

| App | 模式 | 结果 | 备注 |
|---|---|---|---|
| Safari | 自动滚 | 待测 | |
| Chrome | 自动滚 | 待测 | |
| Slack | 自动滚 | 待测 | |
| 微信 | 自动滚 | 待测 | |
| 备忘录 | 自动滚 | 待测 | |
| Mail | 自动滚 | 待测 | |
| cmux | 手动滚 | 待测 | |
| Ghostty | 手动滚 | 待测 | |
| iTerm2 | 手动滚 | 待测 | |
| Terminal | 手动滚 | 待测 | |
| VS Code | 手动滚 | 待测 | |
| Cursor | 手动滚 | 待测 | |
| Finder 分栏 | 手动滚 | 待测 | |
| 自绘测试页（`readme-shots.sh … scrolling`） | 自动滚 | ✅ 2026-11-04 | 504×1400 @1x，头尾各一次，到底自停，滚动条切掉 |

## v1 里程碑（草案）

每个里程碑都是能跑的竖切片，做完能拿来用，不是"写完一层再写下一层"。

| 里程碑 | 内容 | 做完能干什么 |
|---|---|---|
| **M0 骨架** ✅ 2026-11-02 验收通过（真改代码的重编 cdhash=f19deb15 启动即 screenCapture=true，授权跨重编保留） | `Package.swift` + `bundle.sh` + 自签名签名；菜单栏 app；屏幕录制授权引导；⌘⇧1 全屏 → 复制 + 存档 | 验证整条管线：编译 → 打包 → 签名 → 授权 → 截图 → 剪贴板，且重新编译后授权不丢 |
| **M1 冻结遮罩** 🔨 2026-11-02 代码完成、40 个测试全过；外接屏（2560×1440 @1x）实机截图通过，遮罩 138–160 ms 弹出，裁剪对；Retina 屏待测 | 每屏一个遮罩窗口；框选、单击吸附窗口；放大镜、方向键微调；多显示器 + Retina；浮动缩略图。交互默认见"M1 交互默认"一节 | ⌘⇧2 日常区域截图可用 |
| **M2 预设与热键** 🔨 2026-11-03 代码完成；`scripts/self-test.sh` 实机自动跑通延时（3.4 s 后出遮罩）和重复上次区域（同样 1024×576）。实时区域要真拖，待 Alan 手试。全屏进编辑器 / 长截图等 M3 / M5 合并。默认见"M2 预设默认"一节 | 预设模型（冻结 / 实时 × 选择 × 动作）；7 个预设；热键录制（自写，见决策 11）；设置页；遮罩通用键；**动作接口**（复制、存档、编辑器等内置动作都走它，给 #10 workflow 铺路） | 热键可改，Shottr 流、延时、重复区域可用 |
| **M3 编辑器** 🔨 2026-11-03 代码完成、Core 测试全过（92 个）；`--readme-shots` 在壁纸上自动标注一张假结账卡片，渲染正确；Alan 手动试用待测。交互默认见"M3 编辑器交互默认"一节 | 对象层文档模型；裁剪、缩放 / 平移；箭头、矩形、文字、马赛克（含实色遮盖）；工程文件存取 | 能标注，能重新打开再改 |
| **M4 拼图** 🔨 2026-11-03 代码完成、Core 测试全过（104 个）；`--readme-shots` 走真的"添加截图"路径（编辑器让开 → 遮罩 → 选区落到画布）拼出两张，渲染正确；Alan 手动试用待测。交互默认见"M4 拼图交互默认"一节 | 编辑器 / 缩略图上"添加截图"；自动排列 | 多张拼一张 |
| **M5 长截图** 🔨 2026-11-04 代码完成、合进 main（v0.1.0），M5 的 Core 测试 27 个全过；`readme-shots.sh … scrolling` 在自绘页面上实机自动跑通：自动滚 5 次后到底自停，拼出 504×1400，顶部 56 行、底部输入框 64 行各只留一次，滚动条那条被切掉，用时 3.7 s。13 个 app 的手试待 Alan，结果记在"长截图实测"一节。交互默认见"M5 长截图交互默认"一节 | 实时框选；自动滚（辅助功能权限）+ 手动滚；重叠匹配拼接；固定头尾去重；进度预览；30,000 px 上限 | 通过长截图验收清单 |
| **M7 Workflows**（#10：只开"截完之后"）🔨 2026-11-03 代码完成、86 个测试全过；双击安装实机通过；self-test 跑通 Copy Markdown Link 和 Copy at 1x（1x 屏和模拟 2x 都对）；disclaim 实机验证通过（inherited=true / disclaimed=false） | `.screenshottworkflow` 格式、安装与确认、script / shortcut / open-url 步骤、stdout JSON 协议、脚本放弃责任进程（不继承屏幕录制 / 辅助功能授权）、3 个示例 workflow | 别人能写、能分享、能装自己的工作流 |
| **M6 打磨** 🔨 2026-11-03 抓图这半边完成：`--bench` + `os_signpost`，内容列表缓存，`captureImage(in:)`；⌘⇧2 → 遮罩上屏 119 → 74 ms、⌘⇧1 → 复制 + 存档 133 → 110 ms（p50，见"M6 性能记录"）。Delivery 那半边（编码挪出主线程、剪贴板延迟提供）等 M2 合并后做。开机启动（设置里）、图标（`make-icon.sh`）已有 | 内置计时（`ContinuousClock` + `os_signpost`）+ `--bench` 模式连截 N 次出 p50 / p95，对标 17 ms / 165 ms，热点用 `sample` 查；开机启动；`iconutil` 做图标 | 能替代 Shottr 当主力 |

## M1 交互默认（2026-11-02，Alan 可推翻）

- **松手不截**：拖完选区留着，可以再调；Enter 或在选区里双击才截。拖选区内部 = 移动，拖边或角（6 pt 内）= 改大小，拖出对边会翻转。
- **单击 = 吸附窗口**：没拖动的单击选中鼠标下的窗口；在桌面上单击清掉选区。没有选区时，悬停会高亮鼠标下的窗口，直接按 Enter 就截它。M1 的窗口截图是从冻结画面里裁的，被挡住的部分会带进来；真正的单窗口截图以后做。
- **遮罩键**：Enter = 复制 + 存档 + 缩略图 · ⌘C = 只复制 · ⌘S = 另存为（弹保存框）· E（编辑器，M3）和 P（贴图，P1）暂时只响一声 · Esc = 关遮罩。
- **方向键**：有选区时移 1 px，⇧ = 10 px，⌥ = 拉右边和下边；没选区时移动真实鼠标 1 物理像素，方便对准起点。
- **多屏**：每块屏一个遮罩；在另一块屏按下会清掉原来那块屏上的选区（决策 4a）。按物理像素裁（决策 4b），PNG 按 72 × 缩放倍数写 DPI。
- **焦点**：遮罩出现时 Screenshott 会拿走焦点（只有前台 app 能把鼠标指针换成十字），关掉遮罩后把焦点还给原来的 app。
- **缩略图**：截完出现在那块屏右下角，6 秒后自动消失（鼠标停在上面时不消失），多张往上叠，每屏最多 5 张。单击用预览打开（M3 之后改成进编辑器），拖出去 = 拖文件，右键有拷贝 / 在 Finder 中显示 / 打开 / 移到废纸篓。⌘⇧1 全屏截图也会出缩略图。自己的缩略图不会被截进下一张。

## M6 性能记录（2026-11-03）

测法：`scripts/bench.sh 20`（`--bench N` 启动模式，不碰键鼠，同一轮里交替跑每条路径，所以前后对比是同样的条件）。M3 Max，外接 2560×1440 @1x，macOS 26.7.1，截的是真实屏幕内容。单位 ms，p50 / p95，n = 20。原始结果在 `dist/bench/`（不进 git）。"M1"一栏是旧路径（每次都查 `SCShareableContent` + content filter 截图），在同一次运行里测的。

| 阶段 | M1 | M6 | 怎么做到的 |
|---|---|---|---|
| 内容列表 | 27 / 37 | 0 / 0 | 没有缩略图时根本不需要；有缩略图时用缓存 |
| 抓图 | 52 / 61 | 35 / 44 | `SCScreenshotManager.captureImage(in:)`（macOS 15.2+） |
| ⌘⇧2 → 遮罩上屏 | 119 / 131 | **74 / 84** | 上述两项；"上屏" = WindowServer 报告遮罩窗口已 on screen，下一次刷新就显示 |
| ⌘⇧2 → 遮罩上屏，有缩略图时 | 119 / 131 | 98 / 111 | 走缓存的 content filter 路径（要把缩略图排除掉） |
| ⌘⇧2，空闲 10 s 之后 | — | 81 / 82（n = 3） | |
| ⌘⇧1 → 复制 + 存档 | 133 / 146 | **110 / 121** | 剩下的大头是 PNG 编码（54–72），在 Delivery |

对标 Shottr 公布的数字：抓图 17 ms —— 我们 35 ms，还慢一倍；显示 ~165 ms —— 我们遮罩 74 ms 上屏。

**查到的（`sample` + bench check）：**

- **热点**：主线程最大的一块是 PNG 编码（ImageIO → libpng → zlib `deflate`）。内容列表的时间主要花在客户端给每个窗口建 `SCWindow` / `SCRunningApplication`。`captureImage(in:)` 直接走 SkyLight 的硬件截屏（`SLSHWCaptureDesktopProxying`），不建 stream，所以快。
- **缓存为什么成立**：截图只需要每块屏的 `SCDisplay`，和我们自己缩略图的 `SCWindow`（要排除）。别的 app 的窗口不影响：display filter 会截到查询之后才打开的窗口（bench check 用一个查询后才打开的洋红窗口验证过）。缓存失效：显示器变化、唤醒、新缩略图出现（`Thumbnails.show` 里预取）、要排除的窗口不在缓存里（当场重查）。失败就退回 M1 的路径。
- **`captureImage(in:)`**：不能排除窗口，所以只在没有缩略图时用。它没有光标开关；bench 拿"带光标 / 不带光标"两张 filter 截图做对照，确认 macOS 26.7 上它不画光标。它自己决定输出尺寸，所以有尺寸校验：不对就退回缓存路径，这次运行里不再用它。**Retina 屏上待测**。
- **macOS 26 的 `captureScreenshot(rect:)`** 更慢（54 / 63），第一次跑时还连续报 -3811（`SCStreamErrorInternalError`），只留在 bench 里对比。
- **`captureImage(in:)` 的图第一次读像素更贵**：同样编 PNG，它的图 72 ms，filter 的图 54 ms。同一张图编第二次只要 35 ms，所以第一次多出来的约 19 ms（rect 图约 36 ms）是把像素读回来。抓图省下的时间有一部分挪进了编码。
- **遮罩**：从我们的代码跑完（"shown"，52）到 WindowServer 报告上屏（74）还有约 21 ms：CA 提交，加上 14 MB 的图交给 WindowServer。可以试试给 layer 直接用 IOSurface（零拷贝）—— 那是 M1 遮罩的代码，这次没动。

**Delivery 那边的想法（没实现：M2 正在把 Delivery 改成动作接口，等它合并）：**

| 想法 | 量到的 | 预计 |
|---|---|---|
| 编码挪出主线程 | 全屏 PNG 编码 54–72 ms，全在主线程，是 ⌘⇧1 最大的一段 | "到存档"不变短，但主线程空出来：缩略图只要 `CGImage` 不要 PNG（文件名可以先定），能早约 60 ms 出现；紧接着的下一次热键也不用排队 |
| 剪贴板延迟提供（`NSPasteboardItem` + data provider） | 剪贴板现在要等编码完 | ⌘⇧1 → 剪贴板可用 ≈ 抓图 ≈ 38 ms（现在 110）；别的 app 粘贴时才要 PNG，等后台编码完再给。要验证：app 退出前没被粘贴的话，AppKit 会不会先把承诺的数据要走 |
| 剪贴板先放 TIFF | 不压缩 2.2 ms，但 14.4 MB（PNG 1.1 MB） | 可以作为立即可用的类型，PNG 延迟提供；14 MB 进剪贴板服务本身要多少时间待测 |
| 换 PNG 滤波 | `FILTER_NONE` 33 ms（只快 2 ms，大 7%）；`FILTER_SUB` 46 ms（更慢） | 不改，用 ImageIO 默认 |
| 后台存档 | 复制 + 写文件只要 1.4 ms | 单独挪没意义，跟编码一起挪 |

## M2 预设默认（2026-11-03，Alan 可推翻）

- **预设是固定的 7 个**（预设表），每个在设置里能改热键和 Enter 后的动作；画面和选择方式不开放改（v1 不做自定义预设）。"点窗口"这种选择已包含在"区域"的单击吸附里，所以模型里没有单独的窗口模式。
- **Enter 后的动作**可选：复制 + 存档 + 缩略图（默认）/ 只复制 / 另存为 / 进编辑器；M7 起加上已装的 workflow。长截图的动作暂不可选（M5 拼完自己出缩略图）。遮罩里 ⌘C / ⌘S / E 照旧覆盖 Enter 的动作。
- **延时**是一个预设，倒计时 3 / 5 / 10 s 在设置里选（默认 3 s）。倒计时显示在鼠标所在屏中央；点它或再按一次热键 = 取消；数完进冻结遮罩，和"区域"一样操作。
- **重复上次区域**：记住上一次任何区域截图（冻结、实时、延时都算）的位置，按屏幕坐标存（换了显示器排列也照这个坐标找屏）。实时截那块屏，不弹遮罩。还没截过区域时改为打开区域遮罩；那块区域已不在任何屏上时提示并响一声。
- **实时区域**：每屏一层透明遮罩，Screenshott 不抢焦点，被截的 app 保持激活的样子；代价是鼠标没法变成十字（只有前台 app 能换指针），用穿过鼠标的虚线代替。拖完松手立即截；单击 = 鼠标下的窗口；Esc 或右键取消；再按一次热键也取消。
- **全屏进编辑器（⌥⌘⇧1）、长截图（⌥⌘⇧2）**：热键、菜单、设置都在，M3 / M5 合并前按了只提示"arrives with M3 / M5"并响一声。入口是 `AppDelegate.openInEditor(_:)`（`.editor` 先存进文件夹，再交给编辑器，和 M3 的 `Delivery.Action.editor` 同名同义）和 `runScrollingCapture()`，桩在 `PendingFeatures.swift`。
- **动作接口**：`Delivery.run(_:on:)` 是所有截后动作的统一入口（复制、存档、另存为、缩略图、编辑器），遮罩按键、缩略图菜单都走它；`Delivery.deliver(...)` 签名不变。#10 的 workflow 是又一种动作。
- **设置窗口分页**：预设 / 通用（7 个预设加其他选项一页放不下笔记本屏幕）。
- **存储**：快捷键仍是 `shortcut.<预设名>`（`captureArea`、`captureFullScreen` 沿用，旧设置不丢）；动作和倒计时是 `preset.<预设名>.action` / `.delay`；上次区域是 `lastArea`。

## M7 Workflows 默认（2026-11-03，Alan 可推翻）

- **先存档再跑**：workflow 开跑前截图先进存档文件夹（决策 11 的自动存档），所以脚本总能拿到一个真文件路径。
- **步骤**：`script`（包里的可执行文件，带 `#!`）、`shortcut`（`shortcuts run 名字 --input-path 图`）、`open-url`（模板 URL）、`action`（`copy` / `save` / `save-as` / `thumbnail` / `editor`）。贴图、OCR 是 P1，到时再加成内置动作。
- **stdout 协议**：空，或一个 JSON 对象（`clipboard` / `notify` / `open` / `image`），日志一律走 stderr。不认识的键忽略并记日志（拼错能在日志里看到）。不是 JSON 对象、退出码非 0、超时 = 整条链停下，浮层提示"第几步、为什么"（带 stderr 最后一行）。
- **超时**：脚本默认 30 s，可配 1–300 s；到点给整个进程组 SIGTERM，2 s 后 SIGKILL。Shortcut 120 s。
- **环境**：最小环境，不继承启动 Screenshott 的环境；`PATH` 带 `/opt/homebrew/bin`、`/usr/local/bin`；工作目录 = workflow 文件夹；每步有一个空的输出文件夹（`SCREENSHOTT_OUTPUT_DIR`），在系统临时目录下，下次启动清掉。
- **`image`**：绝对路径，或相对输出文件夹的路径；倍数按图片 DPI 算（144 = 2x），后面的步骤拿到新图。
- **`notify`**：用 app 自己的浮层（屏幕下方，几秒后消失），不走系统通知，免得多一个授权弹窗。
- **Shortcut 的输出**：图片 → 换图；JSON 对象 → 和脚本 stdout 一样；其他忽略。
- **安装**：`ditto` 解压；`workflow.json` 可在 zip 根目录或唯一的顶层文件夹里（Finder"压缩"出来的就是这样）。路径必须在包内（不许 `/`、`~`、`..`，符号链接也不许指出去）。确认框列出作者、版本和每一步要做的事。同 id 再装 = 替换，旧的进废纸篓。装好后脚本 `chmod +x`，去掉下载隔离属性（用户刚确认过这些脚本）。删除 = 移到废纸篓。
- **入口**：遮罩选区下方的动作栏（复制 / 另存为 / 编辑器 + 最多 9 个 workflow，数字键 1–9 对应）；缩略图悬停出现闪电按钮，右键菜单里也有；菜单栏 Workflows ▸ 对最近一张截图运行 / 安装 / 打开文件夹；设置里每个预设的"Then"可以选 workflow（workflow 被删后自动退回默认动作）。设置加第三个标签 Workflows：列表、显示位置、移到废纸篓、安装。
- **文档类型**：`Info.plist` 声明 `com.adong.screenshott.workflow`（扩展名 `.screenshottworkflow`，符合 `public.zip-archive`），Screenshott 是 Owner，双击即装。
- **3 个示例**（`Examples/Workflows`，`scripts/pack-workflows.sh` 打包）：Copy Markdown Link（JXA 脚本 → clipboard + notify）、Copy at 1x（`sips` 缩一半 → image，再内置 copy）、Email It（内置 copy + `mailto:` 模板 URL，粘贴即可）。`shortcut` 步骤需要用户自己的快捷指令，没有做成示例，写在 `docs/workflows.md`。

## M3 编辑器交互默认（2026-11-03，Alan 可推翻）

- **入口**：遮罩里按 E（先存档到保存文件夹，再打开编辑器，不复制、不出缩略图）；单击缩略图；菜单栏 *Open in Editor…*；Finder 里对 PNG 用"打开方式 → Screenshott"。M2 的"全屏进编辑器"预设走 `Delivery.Action.editor`，同一条路。
- **编辑器开着时 Screenshott 是普通 app**：有 Dock 图标、能 ⌘Tab、有菜单栏（Edit / View）；最后一个编辑器关掉后回到只在菜单栏。
- **工具键**：V 选择 · A 箭头 · R 矩形 · T 文字 · M 马赛克（再按一次 M 在马赛克 / 实色之间切换）· C 裁剪；1 / 2 / 3 = 细 / 中 / 粗（文字 14 / 20 / 32 pt）。任何工具下按在已有对象上 = 选中并拖动，按在把手上 = 改形状；⇧ = 箭头 45°、矩形正方形、拖动锁水平 / 垂直；方向键移 1 px（⇧ 10 px）；Delete 删除；Esc 取消选中。
- **颜色 / 粗细**：工具栏 6 个色块 + S / M / L。改色或改粗细同时作用在选中的对象上（可撤销）。实色遮盖用当前颜色，强制不透明。
- **文字**：单击空白处开始输入，Return 结束（⇧Return 换行），Esc 或点别处也结束；双击文字再改。打字有自己的撤销，结束后整段文字算一步。
- **马赛克**：8 pt 一格（2x 屏 16 px），每格取平均色；只采样截图本身，不采样其他标注。导出的 PNG 里被遮的像素真的被替换，原图只留在本机工程里。
- **裁剪**：按 C 显示整张原图和当前裁剪框（和遮罩一样的暗角、把手、尺寸），可以往外放回去；Return 或在框里双击 = 裁，Esc = 取消；方向键微调（⌥ 拉右边和下边）。裁剪作用在那张截图对象上，标注跟着像素走。
- **缩放 / 平移**：⌘= 放大、⌘- 缩小、⌘0 实际大小、⌘9 适合窗口，触控板捏合；滚动或按住空格拖动平移。放大到 ≥100% 时按像素直出（不插值）。
- **保存**：⌘S 先写工程（原图 + `project.json`）到 `~/Library/Application Support/Screenshott/Projects/<PNG 名>/`，再覆盖写 PNG——顺序保证原图先进工程。没有文件名的新文档按时间命名存进保存文件夹。⌘C 复制拍平的 PNG；工具栏右边的小方块拖出去 = 拖文件（有改动先存）。关窗或退出时有未存改动会问 Save / Don't Save / Cancel。
- **重新打开**：按 PNG 文件名找工程，找到就恢复原图和所有对象，找不到就把 PNG 本身当原图。

## M4 拼图交互默认（2026-11-03，Alan 可推翻）

- **添加截图**：编辑器工具栏的 *Add Capture*（⇧⌘A），或鼠标停在缩略图上出现的 **+**（先用编辑器打开那张，再添加）。编辑器先隐藏（不挡画面），弹出 ⌘⇧2 同款冻结遮罩；Enter / ⌘C / E 都只把这张加进画布，不另存、不复制、不出缩略图；Esc 取消，编辑器原样回来。
- **自动排列**：默认竖排、左对齐、间距 16 pt；工具栏出现竖排 / 横排、起点 / 居中 / 终点对齐、间距（0 / 4 / 16 / 32 pt）。空白处填白色。改排列可撤销。加图后窗口按新画布重新适配（最多占屏幕 85%）。
- **标注跟着图走**：标注画在哪张图上就挂在哪张图上（按第一个点判断），排列或裁剪移动那张图时一起移动；画在空白处的不跟。
- **删除一张**：选择工具（V）点一张图（蓝框）→ Delete，连同它上面的标注一起去掉；最后一张不能删。
- **不同缩放的屏**：2x 画布里加一张 1x 截图会放大到同样的显示大小（反之缩小），整张画布只有一个缩放倍数。
- **自由拖放**：P1（决策 3a）。

## 2026-11-04 Alan 追加（v0.1.0 之后）

- **按住空格移动选区**（Alan："we dont have a vital features that hold SPACE to move the screen area"）：画选区或拖把手时按住空格 = 整个框按当前大小跟着鼠标走，松开空格接着画 / 拉（和系统 ⌘⇧4 一样）。在 `SelectionModel.holdToMove`，冻结遮罩和长截图遮罩都有。没在拖时按空格不做事。
- **形状**（Alan："lack of shapes, such as circle, oval, triangle, rectangle, hold SHIFT…"）：编辑器加椭圆（O）和三角形（D，Δ）。⇧ = 正圆 / 正方形 / 等边三角形。三角形顶点在框的上边中点，圆角连接。工程格式升到 2（旧版 0.1.0 打不开含新形状的工程；新版保存时写当前版本）。
- **坐标贴着光标**（Alan："show the coordination close to the cursor plus should have option to opt out without magnifier glass"）：光标旁的小标签显示像素坐标、色块和 hex；放大镜下方不再有坐标。设置 → 通用 → "Show magnifier"可关放大镜，标签保留。标签放在放大镜的另一侧（`MagnifierLayout.tagFrame`），永不重叠。
- **取色**（Alan："also use as a color picker, Show hex value when select and press CMD + C to copy the hex value"）：hex 按 sRGB（截图是显示器色彩空间，粘到设计工具按 sRGB 理解）。**没有选区时 ⌘C = 复制 hex 并关遮罩**；有选区时 ⌘C 照旧复制图片。代价：以前"悬停窗口 + ⌘C"复制那个窗口，现在要先单击吸附窗口再 ⌘C。

## M5 长截图交互默认（2026-11-04，Alan 可推翻）

- **选区**：⌥⌘⇧2 出遮罩，画面不冻结。拖框；或单击，取鼠标下的滚动区域（辅助功能里的 AXScrollArea），拿不到就取整个窗口。只框会滚的那块：框里有一条不跟着滚的侧栏，行就对不上。拖、改大小、方向键微调和 ⌘⇧2 一样。
- **开始**：Enter（或在选区里双击、或点 *Auto-scroll*）= 自动滚；M（或点 *Scroll Myself*）= 自己滚。没有辅助功能授权时，Enter 弹系统授权框，这一次改成自己滚，窄条上写明原因。菜单栏菜单里有 *Allow Auto-scroll (Accessibility)…*。
- **截的过程中**：被截的 app 拿回焦点，看起来就是平时的样子，键盘翻页也照常。Return、小键盘 Enter、Esc 临时注册成全局热键，不会打进那个 app（不会把 Slack 消息发出去）。遮罩只框住选区，鼠标和滚轮都穿过去。
- **停**：Enter = 停并保存。Esc = 取消，什么都不存。验收表写的是"Enter / Esc 停"，这里把 Esc 定成取消，和遮罩一致。
- **自动滚**：往选区中心发像素滚轮事件（像触控板），鼠标会被挪到那里。第一步滚半个选区；之后按上一步内容实际移动了多少来调，目标是会动那部分高度的 60%（各 app 对同样的滚轮事件滚得不一样远）。
- **"连续两帧相同"的做法**：每滚一次，等画面停下 150 ms（最多等 0.7 s）。一点没动算一次，连续两次没动 = 到底，停并保存。对不上（滚过头）就滚回去、步子减半；连续三次对不上，停并保存已拼好的部分。
- **上限**：30,000 物理像素。拼上下一帧会超过时就停下保存，结果不超过 30,000，可能差不到一帧。
- **拼接**：每帧和上一张用上的帧比，按行找重叠。顶部不动的行（sticky header）只留第一帧的，底部不动的行（输入框、footer）只留最后一帧的。闪烁的光标、小转圈不算变化。往回滚的帧不用。
- **滚动条**：最右 16 pt 不参与比对。这一条里有东西在动（覆盖式滚动条出现、移动），就把这 16 pt 从结果里切掉；否则每个接缝处都会留一截滚动条。
- **窄条预览**：放在屏幕上离选区远的一侧，显示模式、当前高度和按键。对不上时边框闪橙色；自己滚时还提示"往回滚一点"。
- **系统提示**：第一次用时 macOS 会问 "Screenshott is requesting to bypass the system private window picker…"，要点 Allow。长截图用 ScreenCaptureKit 的连续流，这个授权和截单张不是一回事。

## 开发备注

- **构建**：`scripts/bundle.sh [debug|release]` → `dist/Screenshott.app`。如果 app 正在运行，脚本会先退出它、编完再重开（否则 `open` 只会激活旧进程，测的还是旧代码）。
- **测试**：`scripts/test.sh`（Swift Testing，M7 后 86 个，2026-11-03 全过）。只装 Command Line Tools 时，swift-build 有时不加载 `host/plugins/testing/` 下的宏插件，所有 `@Test` 都会报 "plugin for module 'TestingMacros' not found"，脚本会显式传 `-plugin-path`。
- **图标**：`scripts/make-icon.sh` 用 `Tools/MakeIcon` 里的 CoreGraphics 矢量代码按每个尺寸单独绘制，再用 `iconutil` 打包成 `Support/AppIcon.icns`（.icns 提交进 git，中间 PNG 不提交）。菜单栏图形在 `AppDelegate.menuBarGlyph` 里用代码画，是 template 图，系统按深浅色菜单栏自动着色。
- **启动日志带 CDHash**：`launch 0.1.0 (1) cdhash=xxxxxxxx …`。缓存命中的构建会重新签同样的字节，CDHash 不变；只有 CDHash 变了还不用重新授权，才能证明授权真的跨重编保留。
- **Claude 会话的沙盒里编不了**：SwiftPM 往 `/var/folders/hs/…/T`（临时文件、原子写）和 `/var/folders/hs/…/C`（clang 模块缓存）写东西，沙盒拒绝；另外 SwiftPM 自己的 `sandbox-exec` 不能嵌套，需要加 `--disable-sandbox`。home-guard 又禁止在沙盒外跑仓库脚本。所以目前 `bundle.sh` 由 Alan 在自己的终端跑。想让 Claude 自己编：在 `sandbox.filesystem.allowWrite` 里加 `/private/var/folders/hs/967572j15p385840s129d2r40000gn`，然后用 `swift build --disable-sandbox`。
- **沙盒里的替代办法（2026-11-02 起，home-guard 连沙盒外的 `swift build` / `swift test` 也拒了）**：不走 SwiftPM，直接用 `swiftc` 编：先把 `Sources/ScreenshottCore` 编成静态库加模块（`-emit-library -static -emit-module`，`-module-cache-path` 指到 `$TMPDIR`），再编 app 或测试去链它；测试多带 `-enable-testing`、`-F …/CommandLineTools/Library/Developer/Frameworks -framework Testing`、宏插件的 `-plugin-path`，再加一个调用 `Testing.__swiftPMEntryPoint()` 的 `@main` 文件；运行时 Testing.framework 还要 `lib_TestingInterop.dylib`，在 `…/CommandLineTools/Library/Developer/usr/lib`，链接时加这个 rpath。这样能编译、能跑测试，但出不了签好名的 .app，打包仍然是 Alan 跑 `bundle.sh`。
- **签名证书**：钥匙串里已有自签名证书 "NoteTaker Local Dev"（另一个项目建的）。`bundle.sh` 找不到 "Screenshott Dev" 时会自动用它，TCC 授权照样能跨重编保留。想分开就建一个 "Screenshott Dev"，脚本会优先用。
- **Shottr 冲突**：本机装了 Shottr，默认占 ⌘⇧1 / ⌘⇧2。测 Screenshott 时先退出 Shottr，或者改掉它的热键。注册失败时菜单里会显示"⌘⇧1 is taken by another app"。
- **自测**：`scripts/self-test.sh` 用 `--self-test` 启动 app，不用鼠标自己跑延时、重复上次区域和两个示例 workflow（含一张假装 2x 的截图），每项记 `self-test PASS/FAIL`，跑完退出再重开。前提是装了 Copy Markdown Link 和 Copy at 1x。会动剪贴板，往截图文件夹里存几张壁纸图；"上次区域"跑完会还原。
- **README 截图别在屏保时跑**：屏保盖在所有窗口上面，包括垫底的壁纸窗口，2026-11-03 拍出来全是翻页钟。`readme-shots.sh` 现在检测到屏保就不跑。
- **重绘噪声（M5，2026-11-04）**：app 滚动后会重画文字，抗锯齿可能差 1 级。自绘页面滚 300 px 后，180 行重叠里有 93 行像素差 1，按哈希一行都对不上。所以行比较先比哈希，不一样再比 32 段列的颜色和，容差是每个像素每个通道差 1；"没动"的判断也忽略不超过 8 级的差。
- **长截图调试**：退出 Screenshott 后 `open dist/Screenshott.app --args --scroll-debug <目录>`，会把第一帧和前几张对不上的帧存成 PNG，日志里记它和上一张好帧差多少像素、多少行、最大差几级。那是真屏幕内容，只留本机。
- **README 长截图**：`scripts/readme-shots.sh dist/readme-shots scrolling` 只跑长截图：自己画一个聊天式页面（标题栏 + 长内容 + 底部输入框），直接滚它的 NSScrollView（不用辅助功能），走真的 ScreenCaptureKit 流和拼接，存 `scrolling.png`（过程中，带窄条）和 `scrolling-result.png`（结果）。墙纸窗口垫在弹出菜单那一层，别的 app 的浮动面板盖不过来。
- **日志**：`~/Library/Logs/Screenshott.log`，每次截图记录 list / grab / encode / copy+save 各段耗时，M6 对标 17 ms 用。
- **基准（M6）**：`scripts/bench.sh [N] [--sample]` 跑 `--bench N`，结果打印出来并存到 `dist/bench/`。截图进临时文件夹和私有剪贴板，跑完删掉，不出声、不出缩略图，不碰 `~/Pictures/Screenshott` 和剪贴板。跑的时候不能用 Screenshott：打开菜单栏菜单会卡住所有 MainActor 任务（结果会标 `bench disturbed`）；`bundle.sh`、`bench.sh`、别的会话的自测都会按名字退出正在跑的 Screenshott，这个机器上几个会话一起测的时候要先说好。`--sample` 每毫秒采样一次，会拖慢 app，那次的数字不能比。各阶段也是 `os_signpost` 区间（subsystem `com.adong.Screenshott`），不落盘，实时看：`log stream --signpost --predicate 'subsystem == "com.adong.Screenshott"'`。
- **SwiftUI 不能用 `@State`**：这个 SDK 里 `@State`（还有 `@Entry`、`@Previewable`）是宏，宏插件 `SwiftUIMacros` 只随 Xcode 发，Command Line Tools 里没有，编译直接报 "plugin for module 'SwiftUIMacros' not found"。视图自己的状态放进 `ObservableObject` + `@Published`（属性包装器，不是宏）；`@Observable` 也能用，CLT 带了 `ObservationMacros`。
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
