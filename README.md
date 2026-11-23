# tv-live

电视直播源（M3U），供 TVBox / 影视仓 的「直播」功能使用。列表由本地电脑每天自动刷新后推送到这里，所以**电视端不需要依赖那台电脑在线**。

## 用法

TVBox → 设置 → 直播，填：

```
https://raw.githubusercontent.com/TuTu123471/tv-live/main/tvbox-live.json
```

如果电视打不开 `raw.githubusercontent.com`，改用 CDN 地址：

```
https://cdn.jsdelivr.net/gh/TuTu123471/tv-live@main/tvbox-live.json
```

包含两个源：

- `hd.m3u` — 央视 / 卫视（91 个频道，H.264）
- `lunbo.m3u` — 影视轮播（464 个频道：明星专场 / 影视剧 / 其他轮播 / H.265 单独分组）

## 更新方式

`build-playlists.ps1` 在本地电脑上每天 04:00 运行：拉取公开源 → 逐个测试可用性 → 剔除失效和 H.265（电视容易黑屏）→ 重新生成 m3u → 通过 GitHub API 提交到本仓库。

没有使用 GitHub Actions：GitHub 的云端 runner 在境外，访问不了这些国内的直播源（实测 92 个直播源 + 456 个轮播源全部超时）。

## 说明

- 轮播源来自第三方公开地址（YY / 虎牙等），随时可能失效；每次刷新都会重新测试并丢弃失效的。
- 电脑长期不开时，列表会停留在最后一次推送的状态。
- 仅供个人测试使用。
