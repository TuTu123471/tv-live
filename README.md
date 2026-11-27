# tv-live

央视 1-17 直播源（18 个台，每台 3 条线，H.264 1080p）。

- `cctv.m3u` — 播放列表：CCTV01 → CCTV17（CCTV05+ 在 05 之后）
- `ok-cctv.json` — OK影视 / TVBox 配置

## 配置地址（中国大陆直连）

```
https://gh-proxy.com/https://raw.githubusercontent.com/TuTu123471/tv-live/main/ok-cctv.json
```

## 自动维护

腾讯云函数 `iptv-refresh` 每天 04:00（北京时间）自动修复 `cctv.m3u`：

- 只替换连续两次都测不通的死线
- 替换源只用抽帧验证过的同频道源
- 找不到验证过的备源就保留原线，绝不删除
- 移动 CDN / 浙江广电 CDN 的线不探测、不改动
