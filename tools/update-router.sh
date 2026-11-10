#!/bin/sh
# 在路由器上直接更新 UU 加速器插件（不用重新编译固件）。
#
#   wget -O - https://raw.githubusercontent.com/alexzhong233/luci-app-uugamebooster/master/tools/update-router.sh | sh
#
# 拉不动 raw（国内常见）就换镜像：
#   UU_MIRROR=https://cdn.jsdelivr.net/gh/alexzhong233/luci-app-uugamebooster@master \
#     wget -O - https://cdn.jsdelivr.net/gh/alexzhong233/luci-app-uugamebooster@master/tools/update-router.sh | sh
#
# 只覆盖运行文件，**不动 /etc/config/uuplugin**（设备白名单、开关状态都在里面）。
# 结束前会在本机做语法校验，再重启服务并打印状态。
set -e

BASE="${UU_MIRROR:-https://raw.githubusercontent.com/alexzhong233/luci-app-uugamebooster/master}"
BASE="${BASE%/}"
WORK=/tmp/uu-update.$$

[ "$(id -u)" = "0" ] || { echo "要用 root 跑"; exit 1; }

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { echo "!! $*" >&2; exit 1; }

command -v wget >/dev/null 2>&1 || die "没有 wget"
[ -f /etc/config/uuplugin ] || die "这台机器没装 luci-app-uugamebooster"

mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- 文件清单
# 目标路径|仓库内相对路径|权限
FILES="
/etc/init.d/uuplugin|luci-app-uugamebooster/root/etc/init.d/uuplugin|755
/etc/uci-defaults/45_luci-uuplugin|luci-app-uugamebooster/root/etc/uci-defaults/45_luci-uuplugin|755
/usr/libexec/uuplugin/uu-lib.sh|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-lib.sh|644
/usr/libexec/uuplugin/uu-detect|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-detect|755
/usr/libexec/uuplugin/uu-view|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-view|755
/usr/libexec/uuplugin/xt/iptables|luci-app-uugamebooster/root/usr/libexec/uuplugin/xt/iptables|755
/usr/libexec/uuplugin/uu-sync|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-sync|755
/usr/libexec/uuplugin/uu-sync.d/openclash.sh|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-sync.d/openclash.sh|644
/usr/libexec/uuplugin/uu-sync.d/nikki.sh|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-sync.d/nikki.sh|644
/usr/libexec/uuplugin/uu-sync.d/homeproxy.sh|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-sync.d/homeproxy.sh|644
/usr/libexec/uuplugin/uu-sync.d/ua3f.sh|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-sync.d/ua3f.sh|644
/usr/libexec/uuplugin/uu-passwall-sync|luci-app-uugamebooster/root/usr/libexec/uuplugin/uu-passwall-sync|755
/usr/lib/lua/luci/controller/uuplugin.lua|luci-app-uugamebooster/luasrc/controller/uuplugin.lua|644
/usr/lib/lua/luci/model/cbi/uuplugin.lua|luci-app-uugamebooster/luasrc/model/cbi/uuplugin.lua|644
/usr/lib/lua/luci/view/uuplugin/uuplugin_status.htm|luci-app-uugamebooster/luasrc/view/uuplugin/uuplugin_status.htm|644
/usr/lib/lua/luci/view/uuplugin/uuplugin_howto.htm|luci-app-uugamebooster/luasrc/view/uuplugin/uuplugin_howto.htm|644
/usr/lib/lua/luci/i18n/uugamebooster.zh-cn.lmo|dist/uugamebooster.zh-cn.lmo|644
"

# ---------------------------------------------------------------- 下载
log "下载文件（$BASE）"
FAILED=""
mkdir -p "$WORK/src"
echo "$FILES" | while IFS='|' read -r DST SRC MODE; do
	[ -n "$DST" ] || continue
	OUT="$WORK/src/$(echo "$SRC" | tr '/' '_')"
	url="$BASE/$SRC"
	if wget -q -T 45 -O "$OUT" "$url" && [ -s "$OUT" ]; then
		printf '    %-58s %8s 字节\n' "$SRC" "$(wc -c < "$OUT" | tr -d ' ')"
	else
		rm -f "$OUT"
		printf '    下载失败: %s\n' "$url"
		echo "$SRC" >> "$WORK/failed"
	fi
done

if [ -f "$WORK/failed" ]; then
	die "有文件没下下来（$(wc -l < "$WORK/failed" | tr -d ' ') 个），已中止，什么都没改"
fi

# ---------------------------------------------------------------- 安装
log "安装"
echo "$FILES" | while IFS='|' read -r DST SRC MODE; do
	[ -n "$DST" ] || continue
	OUT="$WORK/src/$(echo "$SRC" | tr '/' '_')"
	mkdir -p "$(dirname "$DST")"
	cp -f "$OUT" "$DST"
	chmod "$MODE" "$DST"
	# 去掉可能混进来的 CR，否则路由器上的 sh/lua 会报 unexpected word
	sed -i 's/\r$//' "$DST" 2>/dev/null || true
done

# 旧版遗留的独立守护，PR#14 之后由 uu-sync 引擎接管，留着会同时插两套规则
for OLD in uu-openclash-sync uu-ua3f-sync uu-homeproxy-sync; do
	if [ -f "/usr/libexec/uuplugin/$OLD" ]; then
		rm -f "/usr/libexec/uuplugin/$OLD"
		echo "    移除旧守护 $OLD"
	fi
done

# ---------------------------------------------------------------- 补新选项
if ! uci -q get uuplugin.@uuplugin[0].nikki_mode >/dev/null 2>&1; then
	uci set uuplugin.@uuplugin[0].nikki_mode='cooperative'
	uci commit uuplugin
	echo "    补上 nikki_mode=cooperative"
fi

# ---------------------------------------------------------------- 校验
log "语法校验"
fail=0
for f in /etc/init.d/uuplugin /usr/libexec/uuplugin/uu-sync \
         /usr/libexec/uuplugin/uu-passwall-sync /usr/libexec/uuplugin/uu-sync.d/*.sh \
         /usr/libexec/uuplugin/uu-lib.sh /usr/libexec/uuplugin/uu-detect; do
	sh -n "$f" 2>/dev/null || { echo "    SYNTAX $f"; fail=1; }
done
if command -v lua >/dev/null 2>&1; then
	for f in /usr/lib/lua/luci/controller/uuplugin.lua /usr/lib/lua/luci/model/cbi/uuplugin.lua; do
		lua -e "assert(loadfile('$f'))" 2>/dev/null || { echo "    LUA $f"; fail=1; }
	done
else
	echo "    （没有 lua 解释器，跳过 Lua 校验）"
fi
if [ "$fail" = "0" ]; then
	echo "    全部通过"
else
	echo "    有文件没通过，服务可能起不来"
fi

# ---------------------------------------------------------------- 重启
log "重启并清理界面缓存"
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uuplugin restart >/dev/null 2>&1 || true
sleep 3

echo "--- 共存进程 ---"
ps w 2>/dev/null | grep -E "uu-sync|uu-passwall-sync" | grep -v grep | sed 's/^/    /' || echo "    (无)"
echo "--- 最近日志 ---"
logread -e uuplugin 2>/dev/null | tail -8 | sed 's/^/    /' || true

log "完成。浏览器 Ctrl+F5，服务 → UU 加速器 → 共存"
