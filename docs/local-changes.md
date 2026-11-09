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
