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

## 5. activate_status 的读取路径

`uu-detect` 里这个文件原来固定读 `/tmp/uu/activate_status` —— 那是**网易官方
一键脚本**的目录，本插件在 `takeover` 时还会把它删掉，自己也从不往那里写。
本插件跑核心的目录是 `$RUN_DIR`（`/var/tmp/uu`，OpenWrt 上 `/var` 链到 `/tmp`，
所以实际是 `/tmp/tmp/uu`），两处不是一回事。结果是 `activated=` 在我们自己的
安装上**永远是空的**，一度被当成「核心没注册」的证据。

现在先读 `$RUN_DIR`，再回落到 `/tmp/uu`（兼容仍留着官方脚本的机器）。这只是
诊断输出，状态页不拿它做判断（见下条）。

`tools/check-status-phase.py` 可以离线把这个结论跑出来：喂一份 `uu-detect` 的
输出（或直接用内置的「厂商版·模拟运行」样本），分别按现在的判据和 2.4 的判据
算一遍 phase，能看到同一个「activate_status 为空、cloud 已连」的样本，现在给
`ready`，旧逻辑给 `starting` —— 也就是那个「永远卡在正在注册」的 bug。

## 状态页的判据：别再往回改

2.5 起 phase 只看两件事：进程在跑（`ours=` 有值）、到网易控制服务器的连接
已建立（`cloud=` 有值）。`activate_status` 是**首次绑定时写一次的链路快照**
（wan_if / MTU），OEM 版重启后干脆永远不写 —— 它从来不是注册凭据。把它重新
加回判据，OEM 设备的状态页就又会永久停在「正在注册」，哪怕 App 里路由器在、
加速也正常。


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
