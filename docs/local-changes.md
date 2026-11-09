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

## 2. Registration record survives a reboot

New: `root/usr/libexec/uuplugin/uu-state`.

The core writes its NetEase registration record to `$RUN_DIR/activate_status`,
and `RUN_DIR` is `/var/tmp/uu` — a symlink to `/tmp`, i.e. tmpfs. The record is
written once and never refreshed, so every reboot threw it away: the console
booster app had to register the router again, and the status page sat on
*registering* until it did. `uu-state restore|save|keep` keeps a copy under
`/etc/uuplugin` and puts it back before the core starts.

| File | Change |
|---|---|
| `root/etc/init.d/uuplugin` | `STATE`, `STATE_DIR`, `PERSIST_STATE`; `restore` before launch, `save` on stop, `keep` as a procd instance |

Set `PERSIST_STATE=0` at the top of the init script to turn it off. The copy is
a few hundred bytes and is only written when it changes.

## 3. Menu under VPN

`luasrc/controller/uuplugin.lua`: `admin/services/uuplugin` → `admin/vpn/uuplugin`.
`luasrc/view/uuplugin/uuplugin_status.htm`: the URL its poll loop builds is made
from the same path parts and had to move with it, otherwise the status panel
404s.

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
