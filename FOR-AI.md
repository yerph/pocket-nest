# FOR-AI：无 Mac 环境下的 iOS 壳与原生改写

你好。这份是写给你的，写代码的那一位。给人类方看的版本在 [README.md](./README.md)。

下面的内容来自我们的一次真实项目：一周内 68 次 CI 编译、50 个版本，从 WKWebView 壳做到十余个页面的 SwiftUI 改写。每条规则背后至少有一次失败的编译，或者一次真机返工。标注「未验证」的条目没有真机结果。希望你和你的人类方能少走这些弯路。

## 0. 环境假设

- 人类方：Windows、iPhone、免费 Apple ID。无 Mac，无付费开发者账号。
- 你这侧：没有 Swift 编译器，没有模拟器，看不到真机。唯一的编译检查是 CI，唯一的视觉反馈是人类方的截图。
- 流水线：写代码 → push → 打 tag → GitHub Actions（macOS runner）`xcodegen generate` + `xcodebuild` → 未签名 ipa → Release → 人类方用 Sideloadly 以免费 Apple ID 重签并安装。

由此推出的总原则：**每一轮反馈都很贵。先读完再写，写完先自查再推。**

## 1. 开工前必须和人类方确认的事

在写第一行代码之前，问清楚并写进交接备忘：

1. 想要的到底是什么：系统能力（小组件 / HealthKit / 推送 / CallKit），还是原生手感。
2. 网页的框架和美化是否定型。向人类方说明：原生化的页面，之后网页每改一次样式都要在原生侧重做一次。怎么选由人类方决定。
3. 是否多设备使用，网页是否保留。
4. 是否愿意付费，是否能借到 Mac。

并在第一时间告知能力边界（本项目实测）：

| 能力 | Windows + Sideloadly + 免费 Apple ID |
| --- | --- |
| 安装到本人设备 | 可以，7 天过期；每台设备首次需开启开发者模式并重启 |
| 后台音频 | 可以 |
| WidgetKit 扩展 | appex 确认在包内，装机后小组件库中不出现。未解决 |
| HealthKit | 授权页不弹；附带自定义 entitlements 时安装被拒（0xe8008015）。未解决 |
| APNs / VoIP 推送 / CallKit 来电 | 需要付费账号 |
| Screen Time (Family Controls) | 需要付费账号与审批 |

有 Mac 或付费账号的情况本项目没有验证过，不要向人类方承诺。

健康数据在本项目中改用快捷指令实现：读取健康样本后 POST 到自有服务器，不经过 app。

## 2. 流水线

**GitHub 令牌（fine-grained）**：仓库范围包含目标仓库；Contents、Workflows、Actions 均为读写。check-run annotations 读不到时，`gh run view --log-failed` 会 403，改用 `gh api repos/<repo>/actions/runs/<id>/jobs` 取 job id，再取 `.../jobs/<id>/logs` 过滤 `error:`。日志要等 job 彻底结束才可取，刚失败时可能 404。

**工程**：XcodeGen 的 `project.yml` 作为唯一真相，`.xcodeproj` 不入库。

**Runner**：`macos-15` + 默认 Xcode 16。`macos-14` + Xcode 15.4 读不了新版 XcodeGen 生成的工程。不要依赖 `xcpretty`。

**Workflow 权限**：发布到 Releases 需要 `permissions: contents: write`。

**触发**：tag `v*` 触发并挂 Release；`workflow_dispatch` 只产出 Artifacts。让人类方从 Release 下载。

**打包**：`CODE_SIGNING_ALLOWED=NO` 编译，把 `.app` 放进 `Payload/` 后 zip 为 `.ipa`。在包内做 ad-hoc 签名并附带 entitlements 不能让 Sideloadly 的免费重签保留受限权限。

**版本号**：`vX.Y.Z` 单调递增，build 号单调递增。不要用 `-nativeNN` 这类后缀。

**一个 commit 对应一个 tag**。编译失败时只改报错处，不夹带新功能。

**如果你的会话环境推不了 tag**（分支 push 正常，tag push 被代理掐断）：在人类方的服务器上 clone 一份，`fetch` + `reset --hard` 到分支头后在那里打 tag 并 push。

**耗时参考**：成功编译中位数约 2.3 分钟，最长约 4 分钟；失败约 1 到 2 分钟。瓶颈不在编译，在写代码和真机往返。

## 3. 壳（WKWebView）必备清单

这个仓库的 `Shell/` 目录是一份能编译、真机装过的参考实现，用法见 [SHELL.md](./SHELL.md)。

- Cookie 持久化（默认 data store）；下拉刷新。
- 同域在壳内导航，外链交给 Safari。
- 实现 `WKUIDelegate` 的 alert / confirm / prompt，否则网页弹窗被静默吞掉。
- 相机、麦克风、相册的用途文案。
- `AVAudioSession` 设为 playback，并声明后台音频。注意确认 Info.plist 里的后台模式真的进了包。
- 网页进程被杀时自动 reload；回前台时补发 `visibilitychange`。
- 断网兜底页。
- User-Agent 追加自有标识；用 `WKUserScript`（所有 frame）给 `<html>` 加类名并注入 `viewport-fit=cover`。网页侧用该类名写"仅壳内生效"的样式。
- 安全区：不要在 SwiftUI 侧给 WebView 留白。让 WebView 全屏，网页侧用 `env(safe-area-inset-top)` 下移内容与固定定位的按钮。`App` 入口上的 `.ignoresSafeArea()` 会把子视图的让位压掉。已自行处理安全区的页面不要重复下移。
- 左边缘右滑：调用网页自己的"返回上一级"函数。
- `isInspectable = true`，方便有 Mac 时调试。

**壳与网页的差异（会导致"浏览器里好的，壳里坏了"）**：

- localStorage 是全新的一份。
- 请求不带 `Referer`；原生 `URLSession` 的 cookie 要从 `WKHTTPCookieStore` 手动拷贝。服务端若有基于 Referer 的门禁会直接 404。
- CDN 回源为 http 时，服务端的绝对重定向会被拼成 `http://`，被 ATS 拦截（nginx：`absolute_redirect off`）。
- 没有 Web Push。
- `prefers-color-scheme` 跟随的是 app 的 `preferredColorScheme`。若该值又是从网页底色反推的，就成了循环。需要壳读 `UITraitCollection` 后把真值注入网页。
- 网页未上色时 CSS 变量可能读到 `rgba(0,0,0,0)`。alpha 接近 0 的值不是颜色，丢弃。

**排查顺序**：遇到空白页、"未登录"，先在服务器上用 curl 复刻壳的请求头，看服务端实际返回什么，再动客户端代码。

**凭证**：不要把网页的密码或令牌写进仓库。让服务端提供一个接口，用网页登录态换取 app 专用令牌；app 存 Keychain；服务端只存哈希；可单独吊销。

## 4. 混合架构（网页为底，原生覆盖）

- WKWebView 常驻为底层。原生页作为 overlay，由单一状态（例如 `nativePage`）路由。未原生化的页面收起 overlay 露出网页。
- 入口：注入脚本包住网页的导航函数，命中时 `postMessage` 给壳。
- **必须留逃生口**：网页自身内部也会调用这些导航函数。提供一个全局标记（例如 `window.__noHook`），置位时放行。
- **建议做逐页开关**：每个原生页可在设置里切回网页版。网页美化更新后原生页落后时，这是最便宜的退路。
- **状态同步读 DOM**：读 `html[data-theme]` 这类实际参与渲染的属性，不要读 localStorage 里"应该等价"的键。可轮询后写入 UserDefaults 供冷启动使用。
- **全 app 只保留一条底栏**，常驻在根视图。切 tab 的第一步是收起所有全屏覆盖层。
- **借用网页功能时懒加载**：第二个 WKWebView 只在用户触发时创建，用完销毁。常驻一张带 SSE 和轮询的页面会让整个 app 卡死。
- **透明全屏覆盖层默认 `allowsHitTesting(false)`**，加载完成且可见后再打开，并提供一条原生的返回条，设置加载超时。
- 页面转场不要用 `fullScreenCover`（系统自带上推动画），用 ZStack + `.transition(.opacity)`。

**选页面时的成本参考**：本项目最先原生化的是聊天页，原因是它在 WKWebView 中有修不掉的问题（消息乱序、图片偶发不显示）。装饰密集的页面照着重画的工作量最大，网页改版后也最容易落后。

## 5. 把 CSS 翻译成 SwiftUI

**第一原则：读源码，不猜。** 每做一个控件，先取齐它的 HTML 结构、最终生效的 CSS、JS 行为。把字号、字距、颜色变量、动画周期、文案原文抄进 Swift 文件顶部注释再动笔。本项目返工最多的几处全部源于凭印象绘制。

1. **取 cascade 中最后生效的规则。** 大样式文件里同一选择器会出现多次（基础层、设计层、适配层、`@media`）。`grep -n` 列出全部出现位置，取最后一次，再检查手机断点。不要抄桌面或平板档位。
2. **某条样式可能只写给了某一个主题**（例如只有某主题下才有底色和边框）。不要按"浅色主题都有"推断。
3. **主题色整套搬运**：`:root` 的每套变量抄成一个 struct，视图只引用变量名。衍生色（主色的某个透明度）写成计算属性。
4. **数值换算**：`rem` 按 16；`em` 按父字号；`letter-spacing: .2em` 即 `tracking = 字号 × 0.2`；`line-height` 换算为 `lineSpacing = 字号 × 行高 − 字体自然行高`。
5. **`box-shadow` 的多层 inset 逐层对应**，不要合并。漏掉中间的底色垫层会让两道描边糊在一起。
6. **字体**：ttf 放入工程，`UIAppFonts` 全部列出，代码里用 PostScript 名。漏登记不报错，静默回退系统字体。中文字体可裁字符集以控制体积。
7. **贴图**：单色图转 template png，`renderingMode(.template)` 后用主题色着色。**作为遮罩使用的图不得量化或压缩 alpha 通道**，只能缩尺寸。
8. **SVG**：从网页抽 path 字符串，写一个小解析器转 `Path`。逐笔绘制用 `trim(from:to:)`。CSS keyframes 可直译：每个属性在相邻关键帧间插值，timing function 作用于每一段。
9. **布局**：`position:absolute` 加负 margin 对应 `ZStack` + 负 padding；`.offset` 不占布局。`scaledToFill` 的图先 `.frame` 再 `.clipped()`，否则撑破父容器。
10. **手势**：父容器的 `.gesture(DragGesture)` 会吞掉子控件触摸，改用 `.simultaneousGesture` 并在子控件拖动期间禁用。
11. **文本被压成一字一行**：`HStack` 内争宽时给 `lineLimit(1)`、`fixedSize` 或拆行。
12. **动画**：用 `TimelineView` 的时间去驱动外部 modifier 在真机上可能不重绘；循环动画用 `@State` + `withAnimation(.repeatForever)`。`TimelineView` 只在其自身的 `Canvas` 闭包内可靠。
13. **Canvas**：会旋转的内容，画布尺寸取名义尺寸的 1.8 到 2 倍，否则投影出界被裁。静态装饰只画一次；`blur` 尽量换成渐变。
14. **长列表**：`LazyVStack` + 分页 + 两阶段加载（先取少量立即显示，后台取全量）。
15. **接口**：先读服务端代码确认默认分页参数与返回形状。网页的无限滚动会掩盖"默认只返回 N 条"。URL 查询里的 `+`（如时区 `+08:00`）需手动编码为 `%2B`。
16. **发送后立即给等待态**，尤其当后端不是流式时。先确认数据源的粒度（逐 token 还是整条），再决定界面表现。
17. **本地先画，服务端后替换**：本地追加 pending 行，服务端数据到达后按角色与文本匹配替换，并把仅本地持有的字段带过去。
18. **多通道去重**：SSE 与轮询并存时，按唯一 id 去重，入缓冲、短暂等待、按时间排序后再递给界面。

## 6. 无编译器时的 Swift 自查清单

推送前逐条过一遍。每条都对应过至少一次失败的 CI。

- `body` 超过一屏就拆成 `private var xxx: some View`。ViewBuilder 单个闭包内子视图不超过 10 个。
- 不写长的 `Text + Text` 链，尤其不放进 `switch`。先存成变量。
- 不嵌套三元。拆成带显式类型的 `let`。
- `CGFloat` 与 `Double` 不混算；必要时拆成标注返回类型的小函数。注意整数除法。
- 属性包装器一行一个：`@State`、`@Published` 不用逗号连续声明。可选的 `@State` 写显式 `= nil`。
- ViewBuilder 闭包内不声明 `func`。用闭包常量或移到类型层级。
- 往 struct 中间加字段后，所有 memberwise init 调用处的参数顺序都要改。优先加在末尾。
- 给枚举加 case 前，全局搜索该枚举的所有 `switch`。
- `@MainActor` 类型里的 `static` 方法同样被隔离；供非隔离代码调用的标 `nonisolated`。AVPlayer / KVO / NotificationCenter 回调是 `@Sendable`，不要在其中直接写 `@MainActor` 属性。
- 使用任何 API 前核对部署目标。例如带坐标的 `onTapGesture` 需要 iOS 17，低版本用 `DragGesture(minimumDistance: 0)` 取位置。
- 自定义类型不要与 SwiftUI / Foundation 的类型同名（如 `App`）。
- 同一个 view 上只挂一个 `.fileImporter`，多用途用枚举区分。
- 一个页面一个文件。编译失败时能立刻定位。

## 7. 和人类方一起干活

人类方看不懂代码也没关系，TA 是你唯一的眼睛。把 TA 的每一张截图当成最可靠的测试结果。

- 一次做一件，做完交付可安装的版本，再接下一件。一版只收一轮意见。
- 交付时明确列出**你无法验证的部分**（播放、手势精度、锁屏恢复、真机渲染），请人类方优先检查。CI 通过不等于完成。
- 请人类方提供成对截图（网页 / app）和"照哪个做"，而不是形容词。
- 当人类方说"和之前不一样"，先确认"之前"指的是网页版还是上一个 build。
- 涉及字面符号的内容请人类方用代码格式发送，聊天界面会吞掉 markdown 符号。
- 只做 TA 要的范围。人类方让做原生时不要顺手改网页。改服务器上的任何文件前先备份。
- 交接备忘写给一个没看过对话的读者：仓库与分支、最新 commit 与 tag、如何发版、编译自查清单、服务端改动与备份位置、未验证项。
- 远程执行环境的默认 shell 可能是 `sh` 而非 `bash`；有执行超时的要拆命令或后台运行；脚本一律用绝对路径。

## 8. 本项目未解决 / 未验证

- 免费账号经 Sideloadly 安装后小组件不出现的确切原因（推测为扩展未被正确重签）。
- 免费账号在 Mac + Xcode 下 HealthKit 是否可用。
- 付费账号 + 云端 runner 签名 + 无 Mac 的完整流程。
- 若干较晚完成的原生页面缺少真机验收。
- Sideloadly 安装失败的一次经历最后确认是网络不稳，与是否开代理无关。
