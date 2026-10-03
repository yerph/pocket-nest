# 先把网页变成 PWA

如果你现在只有一个普通的网页，还没做过 PWA，可以先看这一份。

> 这份文档分两半：前面是给人看的，讲要做什么、会遇到什么；最后的[「给 AI 的部分」](#给-ai-的部分)是给你的 AI 看的，里面有可以直接用的代码。把整份交给 TA 就好。

PWA 的意思是：让网页可以"添加到主屏幕"，在桌面上有自己的图标，点开以后全屏显示，没有浏览器的地址栏，用起来像一个 app。它不需要电脑、不需要签名、不需要每七天重装，改了网页刷新就生效。

我们的小窝一直是这样用的，通知也是靠它收的。

先说清楚两件事：

- **套壳不需要先做 PWA。** 仓库里的空壳能打开任何 https 网页，普通网页也可以直接套。
- **但我们建议先做 PWA。** 它花的时间最少，而且壳里收不到推送，通知还是要靠 PWA。

## 你需要准备什么

- 网页必须是 https
- 两三张图标（见下面）
- 能改网页文件的人或 AI

## 要做的三件事

这三件事都可以交给你的 AI，把这份文档给 TA 就行。文档最后有可以直接用的代码。

**1. 加一个说明文件（manifest）**

一个小小的文件，告诉手机：这个 app 叫什么、图标是哪张、打开时全屏显示。

**2. 在网页开头加几行标签**

iPhone 认的是它自己的一套标签：主屏幕图标、全屏开关、状态栏样式、桌面上显示的名字。

**3. 准备图标**

- 192×192 和 512×512 各一张 png
- 180×180 一张，给 iPhone 主屏幕用。这张不要带透明，透明的地方会变成黑色

## 怎么添加到主屏幕

1. 用 **Safari** 打开你的网页
2. 点底部的分享按钮
3. 往下找到"添加到主屏幕"
4. 确认名字，点"添加"

之后从桌面图标点进去，就是全屏的了。

## 想要通知的话

iPhone 上的网页推送有三个前提：

- 系统在 iOS 16.4 以上
- 必须是从主屏幕图标打开的，在 Safari 里直接开网页不行
- 申请通知权限必须由你亲手点一下按钮触发，网页不能一打开就自己弹

做法是让 AI 加一个后台小脚本（service worker）负责接收通知，服务器那边用一对密钥（VAPID）来发。细节在文档最后。

## 我们踩过的坑

**1. 后台小脚本不要去管网页的请求**

这是我们踩得最疼的一个。我们的后台脚本原本会经手网页的每一条请求（只是原样转发，并没有做缓存）。结果在 iPhone 上和 AI 聊天时，长一点的回复会在中途断掉，页面只显示"加载失败"，那条回复就丢了。

原因是 AI 的回复是一条持续几十秒的长请求，在 iPhone 上经过后台脚本会被掐断。我们后来做了两件事：

- 让后台脚本完全不碰请求，只负责通知。
- 让服务器在回复还没出字的那段时间里，每隔十几秒发一个"我还在"的信号，免得连接因为太久没动静被判定为断开。

之后就没再丢过。如果你的网页是用来和 AI 聊天的，建议一开始就这样做。

**2. 改了图标或名字，桌面上不会变**

主屏幕上的图标和名字是添加那一刻存下来的。之后改了，要把桌面图标删掉，重新添加一次。我们还给图标的地址加了版本号，避免手机一直用旧图。

**3. 添加到主屏幕以后要重新登录**

主屏幕上的 PWA 和 Safari 里的网页，本地存储是分开的。头像、主题这类设置也要重设一次。

**4. 网页要认得出自己是从主屏幕打开的**

有些东西只想在 PWA 里显示，比如开屏动画、通知开关。让 AI 加一个判断就可以，文档最后有。

**5. 每次打开都检查一下通知的订阅**

订阅有时会悄悄失效。我们的做法是每次打开时检查一次，没了就提示重新开启。

## 做完 PWA 之后

- 觉得这样已经够用：到这里就结束了，这也是维护最省心的方式。
- 想要一个真正装在手机里的 app：回到 [README.md](./README.md) 的第一章，或者直接用 [SHELL.md](./SHELL.md) 里的空壳。

---

## 给 AI 的部分

下面是最小可用的写法，按人类方的网页实际情况调整。

**manifest.json**（放在网站根目录）

```json
{
  "name": "我的小窝",
  "short_name": "小窝",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#f4f1eb",
  "theme_color": "#f4f1eb",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

**`<head>` 里的标签**

```html
<link rel="manifest" href="/manifest.json">
<link rel="apple-touch-icon" href="/apple-touch-icon.png?v=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="小窝">
<meta name="theme-color" content="#f4f1eb">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
```

- `apple-touch-icon` 用 180×180、不透明的 png。改图标时把 `?v=` 的数字加一。
- 想让背景延伸到刘海下面，viewport 加 `viewport-fit=cover`，内容用 `env(safe-area-inset-top)` 下移。
- 启动图（`apple-touch-startup-image`）是可选的，需要按机型尺寸逐个提供，没有也能用。

**判断是否从主屏幕打开**

```js
const standalone = matchMedia('(display-mode: standalone)').matches || !!navigator.standalone;
```

**sw.js**（只负责通知，不接管请求）

```js
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// 不要在 fetch 里调用 respondWith。
// 在 iOS 上，流式的长请求 (SSE / 流式 POST) 经过 service worker 会被中断，
// 前端表现为 "FetchEvent.respondWith received an error: Load failed"。
self.addEventListener('fetch', () => {});

self.addEventListener('push', (event) => {
  let data = { title: '新消息', body: '', url: '/' };
  try { data = Object.assign(data, event.data.json()); } catch (e) {}
  event.waitUntil(self.registration.showNotification(data.title, {
    body: data.body,
    data: { url: data.url }
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) { c.navigate(url); return c.focus(); }
      }
      return clients.openWindow(url);
    })
  );
});
```

**页面里：注册与订阅**

```js
// 注册可以在页面加载时做
const reg = await navigator.serviceWorker.register('/sw.js');

// 订阅必须放在用户点击的回调里
async function enablePush(vapidPublicKey) {
  const perm = await Notification.requestPermission();
  if (perm !== 'granted') return;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
  });
  await fetch('/api/push/subscribe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(sub)
  });
}

function urlBase64ToUint8Array(s) {
  const pad = '='.repeat((4 - (s.length % 4)) % 4);
  const b = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(b, (ch) => ch.charCodeAt(0));
}
```

- 每次启动时调用 `reg.pushManager.getSubscription()`，返回空就提示人类方重新开启。
- 通知开关只在 `standalone` 为真时显示，Safari 标签页里订阅不了。

**服务端**（Node 的 `web-push` 为例）

```js
const webpush = require('web-push');
// 密钥用 webpush.generateVAPIDKeys() 生成一次，私钥放环境变量，不要进仓库
webpush.setVapidDetails('mailto:you@example.com', PUBLIC_KEY, PRIVATE_KEY);

await webpush.sendNotification(subscription, JSON.stringify({
  title: '新消息', body: '内容', url: '/'
}));
```

- 发送返回 404 或 410 时，说明这条订阅已失效，从库里删掉。
- 订阅是按设备存的，人类方有几台设备就有几条。

**流式回复的保活**

如果聊天接口是 SSE 或流式响应，模型在冷启动、思考、调用工具时可能几十秒不出字。iOS Safari 会把长时间没有字节的请求判定为失败（`Load failed`）。让服务端每 10 到 15 秒写一个前端会忽略的心跳事件，直到正文开始或结束。

**核对清单**

- [ ] 全站 https
- [ ] manifest 能访问，`display` 为 `standalone`
- [ ] `apple-touch-icon` 180×180 且不透明
- [ ] 从主屏幕打开是全屏
- [ ] service worker 的 fetch 不调用 `respondWith`
- [ ] 通知权限由点击触发
- [ ] 流式接口有心跳
- [ ] 流式回复在 PWA 里能完整收完
