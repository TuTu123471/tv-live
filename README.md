# tv-live

央视 1-17 + 卫视 直播源（中国大陆直连）。

- `cctv.m3u` — 央视 1-17（18 台，每台 3 条，H.264 1080p）
- `ws.m3u` — 卫视（34 台，90 条；辽宁/新疆各 1 条稳定线，广西 2 条（含慢备用），其余 2-3 条）
- `ws-verified.json` — 卫视各台验证过的同频道源表（云函数修复用）
- `ok-live.json` — OK影视 / TVBox 配置（两个分类：央视 1-17、卫视，**推荐用这个地址**）
- `ok-cctv.json` — 旧配置文件名（内容相同，保留兼容；OK影视 可能缓存了旧版，建议换 `ok-live.json`）

## 配置地址（中国大陆直连）

```
https://gh-proxy.com/https://raw.githubusercontent.com/TuTu123471/tv-live/main/ok-live.json
```

## 自动维护

腾讯云函数 `iptv-refresh` 每天 04:00（北京时间）同时维护 `cctv.m3u` 和 `ws.m3u`：

- 只替换连续两次都测不通的死线
- 替换源只用抽帧验证过的同频道源
- 找不到验证过的备源就保留原线，绝不删除
- 移动 CDN / 各台官方 CDN 的线不探测、不改动
