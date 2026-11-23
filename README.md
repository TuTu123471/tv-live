# TV live playlists

自动生成的电视直播源，供 TVBox / 影视仓 的「直播」功能使用。

## 用法

TVBox → 设置 → 直播，填入：

```
https://cdn.jsdelivr.net/gh/TuTu123471/tv-live@main/tvbox-live.json
```

包含两个源：

- `hd.m3u` — 央视 / 卫视（H.264，走公网 CDN）
- `lunbo.m3u` — 影视轮播（明星专场 / 影视剧 / 其他轮播）

## 说明

- `build-playlists.ps1` 每天 UTC 20:00（北京时间 04:00）由 GitHub Actions 运行，拉取最新的公开源、检测可用性、剔除 H.265（播放器容易黑屏）后重新生成 m3u。
- 轮播源来自第三方公开地址（YY / 虎牙等），随时可能失效；脚本每次运行都会重新测试，失效的会被自动丢弃。
- 仅供个人测试使用。
