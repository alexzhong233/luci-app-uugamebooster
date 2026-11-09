# Changes made in this fork

Upstream: [xiaodoudou/luci-app-uugamebooster](https://github.com/xiaodoudou/luci-app-uugamebooster).
Everything here is additive — no upstream file is rewritten for style, so the
scheduled sync in `.github/workflows/sync-upstream.yml` keeps working.

## 1. PassWall coexistence

New: `root/usr/libexec/uuplugin/uu-passwall-sync`, `docs/passwall.md`.

| File | Change |
|---|---|
| `root/etc/config/uuplugin` | `option passwall_mode 'cooperative'` |
| `root/etc/init.d/uuplugin` | `PWSW_SYNC`, `start_passwall_sync()`, called from `start_service()`; `cleanup` on stop |
| `luasrc/model/cbi/uuplugin.lua` | new **PassWall** tab, one `ListValue` |
| `luasrc/controller/uuplugin.lua` | `passwall_installed` / `passwall_mode` / `passwall_exempted` in the status JSON |
| `luasrc/view/uuplugin/uuplugin_status.htm` | PassWall rows in the status panel |

Rationale and the measured behaviour: [docs/passwall.md](passwall.md).

## 2. Menu under VPN

`luasrc/controller/uuplugin.lua`: `admin/services/uuplugin` → `admin/vpn/uuplugin`.
`luasrc/view/uuplugin/uuplugin_status.htm`: the URL its poll loop builds is made
from the same path parts and had to move with it, otherwise the status panel
404s.

## 3. 出厂设备名

`root/etc/config/uuplugin` 里的 `model` 默认值从 `OpenWrt` 改成 `RE-CS-02`。
它写进 `/var/tmp/uu/h3c_info` 的 `productname`，也就是网易云端和 UU App 里显示
的那台设备的名字。

- 与 `oem_model` 无关：后者（`h3c-nx30pro` / `h3c-bx54`）决定下载哪一家的厂商包，
  改它会导致下不到包。
- 改这个值等于换了一台设备，**已在 App 绑定过的需要解绑再绑定**，加速能力
  （含 PC/手机加速）是否保留取决于云端对 model 的校验，首次切换后应在 App 里
  确认一台电脑/手机还能被加速。
- 只是出厂默认：已经装过插件的机器 `/etc/config/uuplugin` 早已存在，需要在
  路由器上 `uci set uuplugin.@uuplugin[0].model='RE-CS-02' && uci commit uuplugin`
  再重启服务。

## 4. Scheduled sync from upstream

`.github/workflows/sync-upstream.yml` calls GitHub's own `merge-upstream`
endpoint daily, which merges the parent repository's default branch into
`master`. A conflict is reported in the run log and left alone — it is never
resolved by guessing.

## 5. 中文翻译

新增的字符串（PassWall 标签页、状态面板那两行）在 `po/zh_Hans/uugamebooster.po`
里补了 8 条，`po/templates/uugamebooster.pot` 用 `tools/i18n-scan.py` 重新生成。

`.lmo` 是编译产物，构建时由 `luci.mk` 从 po 生成，所以**热替换 .lua/.htm 不会
带出中文**——这时页面回落到英文原文。想在不重编固件的情况下看效果，直接放一份
预编译好的目录：`dist/uugamebooster.zh-cn.lmo`（用 `tools/po2lmo.py` 生成，
与当前 po 一致；改过 po 要重新生成）。
