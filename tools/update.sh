#!/bin/sh
# 把本地这份 tree 推到路由器，并保住路由器上已有的 UCI 配置。
#
# tools/deploy.sh 会把 etc/config/uuplugin 一起覆盖，那是出厂默认值 ——
# 设备白名单、开关状态、PassWall 模式都会回到默认。升级时通常不想这样，
# 所以这里先备份、推完再放回去。
#
# 用法（在仓库根目录，Git Bash / POSIX shell 都可）：
#   sh tools/update.sh                  # 默认 root@192.168.88.1
#   sh tools/update.sh root@192.168.1.1
#   sh tools/update.sh root@192.168.88.1 --keep-config=0   # 连配置一起重置
set -e

HOST="${1:-root@192.168.88.1}"
KEEP=1
for a in "$@"; do
	case "$a" in
		--keep-config=0) KEEP=0 ;;
	esac
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

say "备份路由器上的 /etc/config/uuplugin"
HAVE=0
if scp -q "$HOST:/etc/config/uuplugin" "$TMP/uuplugin.conf" 2>/dev/null; then
	HAVE=1
	printf '    已备份（%s 字节）\n' "$(wc -c < "$TMP/uuplugin.conf" | tr -d ' ')"
else
	echo "    路由器上没有这个文件，按全新安装处理"
fi

say "推送文件（tools/deploy.sh）"
sh "$ROOT/tools/deploy.sh" "$HOST"

if [ "$HAVE" = "1" ] && [ "$KEEP" = "1" ]; then
	say "还原 UCI 配置"
	scp -q "$TMP/uuplugin.conf" "$HOST:/etc/config/uuplugin"
	ssh "$HOST" 'chmod 644 /etc/config/uuplugin'
fi

say "重启并检查"
ssh "$HOST" '
	/etc/init.d/uuplugin restart >/dev/null 2>&1
	sleep 3
	echo "--- 进程 ---"
	ps w | grep -E "uu-(sync|passwall-sync)" | grep -v grep | awk "{print \$NF}" | sort -u | sed "s/^/    /"
	echo "--- 共存状态 ---"
	ubus call uuplugin status 2>/dev/null | tr "," "\n" | grep -E "sync|passwall|mode" | head -20
	echo "--- 日志 ---"
	logread -e uuplugin 2>/dev/null | tail -8 | sed "s/^/    /"
'

say "完成。浏览器 Ctrl+F5 后进「服务 → UU 加速器 → 共存」"
