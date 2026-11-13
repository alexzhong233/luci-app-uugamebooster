# Changes made in this fork

Upstream: [xiaodoudou/luci-app-uugamebooster](https://github.com/xiaodoudou/luci-app-uugamebooster).
Kept deliberately small — only what cannot live upstream — so the scheduled sync
in `.github/workflows/sync-upstream.yml` keeps working.

## 1. Menu under VPN

`luasrc/controller/uuplugin.lua`: `admin/services/uuplugin` → `admin/vpn/uuplugin`.
This is the same kind of thing as the netbird and tailscale pages, so it sits
next to them.

`luasrc/view/uuplugin/uuplugin_status.htm` builds the status URL from the same
path parts (`url([[admin]], [[vpn]], [[uuplugin]], [[status]])`); the two have to
move together, otherwise the panel 404s and every value stays at "collecting".

## 2. Scheduled sync from upstream

`.github/workflows/sync-upstream.yml` calls GitHub's own `merge-upstream`
endpoint daily, which merges the parent repository's default branch into
`master`. A conflict is reported in the run log and left alone — it is never
resolved by guessing.

## 3. 中文翻译

`luci-app-uugamebooster/po/zh_Hans/uugamebooster.po` 跟上上游新增的字符串；
`po/templates/uugamebooster.pot` 用 `tools/i18n-scan.py` 从源码重新生成
（脚本的默认输出就是包里那份，仓库根目录不要另放一份）。

`.lmo` 是编译产物，构建时由 `luci.mk` 从 po 生成，所以**热替换 .lua/.htm 不会
带出中文**——这时页面回落到英文原文。想在不重编固件的情况下看效果，直接放一份
预编译好的：`dist/uugamebooster.zh-cn.lmo`（用 `tools/po2lmo.py` 生成，
与当前 po 一致；改过 po 要重新生成）。

## 4. 路由器上的更新脚本

`tools/update-router.sh`（在路由器上执行：整包下载 + 单文件重试）和
`tools/update.sh`（从本机推到路由器，保住已有 UCI 配置）。上游没有这两个。

## PassWall 共存：已经还给上游

2026-11 之前这个 fork 自带一套 `uu-passwall-sync`（把发往路由器本机的
`udp/53` 用 RETURN 顶在 UU 的重定向前面）。上游后来把同样的思路做进了主分支
（PR #12 / #14 / #16）：`uu-passwall-sync` 重写、新增 `uu-route-check`、每个代理
统一走 `uu-sync.d/` 一套引擎，PassWall 也被放进 `sync` 列表。

所以本地那套实现已经删掉，**不要再加回来**——会和上游的引擎抢同一批规则。
现在 PassWall 共存由上游的 `passwall_mode` 控制，默认 `off`（上游的理由：让被
加速设备继续用 PassWall 的解析，可能把游戏解析到 UU 不路由的地址）。要开就
`uci set uuplugin.@uuplugin[0].passwall_mode='cooperative'`，或走页面
**共存方式 → PassWall → 分流**。
