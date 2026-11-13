# 测试分支：复现「永远卡在注册中」，并找出 UU 到底在哪生成文件

分支：`test/repro-activate-status`（从 `master` 的 `be149eb` 拉出）。

两个目的：

1. **按需把那个 bug 摆出来。** 2.5 的判据只看「进程在跑 + 控制连接已建立」，
   所以在 2.5 上这个 bug 已经不会出现（`tools/check-status-phase.py` 离线就能
   证明）。要给人看原始表现，就得把 2.4 的判据临时装回去 —— 这个分支给了一个
   UCI 开关，一条命令切换，不用重编固件。
2. **看核心自己写了哪些文件。** 不猜目录、不 `mkdir`，只用 `/proc/<pid>/fd`、
   cwd 和「打标记前后的差异」把它实际写的东西列出来。

## 装到路由器上

```sh
UU_MIRROR=https://cdn.jsdelivr.net/gh/alexzhong233/luci-app-uugamebooster@test/repro-activate-status \
  wget -O - https://cdn.jsdelivr.net/gh/alexzhong233/luci-app-uugamebooster@test/repro-activate-status/tools/update-router.sh | sh
```

（raw.githubusercontent 拉不动就用上面这个 jsDelivr；两个地址要指向同一个分支。）

它只覆盖运行文件，**不动 `/etc/config/uuplugin`**，UCI 开关默认不存在 = 关。

## 一、复现 bug

```sh
uu-trace strict on      # 页面刷新：「服务」那一行变回「Registering…」
uu-trace strict off     # 恢复正常
```

打开之后页面会多一行「复现开关」，把 `activate_status` 的原始值也显示出来
（通常就是 `(空)`）。这时候：

- `uu-detect` 里 `cloud=` 有值；
- `boosted=` 里有设备（App 里在加速）；
- 页面上却写「注册中」。

这就是 2.4 及更早的行为，也是这个 bug 的全部证据。截图连同 `uu-trace` 的报告
一起贴出去，比文字描述有力得多。

## 二、找文件：`uu-trace`

```sh
uu-trace                # 快照：进程、cwd、打开的 fd、候选目录、挂载
uu-trace watch 90       # 打标记 → 给你 90 秒去 App 里点加速 → 列差异
uu-trace restart 30     # 换成重启服务，看开机时它写什么
```

报告落在 `/root/uu-trace-<时间>.txt`（overlay，重启还在），屏幕上同时输出。

### 该看哪几段

| 段落 | 回答什么 |
|---|---|
| `-- 打开的文件` | **权威答案**：核心开着哪个 `.db`，就是在写哪个。列出来的是 `/proc/<pid>/fd`，不是猜测 |
| `-- 映射进来的文件` | 模拟运行时能看到 qemu 与 sysroot 里被映射的东西（`/opt/uu-oem/...`） |
| `运行目录` + `readlink -f` | `/var/tmp/uu` 到底是哪个真实路径 |
| `系统里像 UU 数据库的文件` | 全盘扫 `.uu*` / `uu*.db` / `activate_status` / `uu.conf` |
| `自 <marker> 之后新建 / 改动的文件` | `watch` / `restart` 的重点：这段时间它实际创建或改写了什么，带大小和时间 |

### 一个容易踩的点：`/var/tmp/uu` 不是 `/tmp/uu`

OpenWrt 上 `/var` 是 `/tmp` 的链接，所以本插件的运行目录
`/var/tmp/uu` 实际是 **`/tmp/tmp/uu`**。`/tmp/uu` 是**网易官方一键脚本**的目录，
本插件 `takeover` 时还会把它删掉。两者不是一回事 —— 只在 `/tmp/uu` 里找，
自然什么都找不到。

`uu-trace` 两个都列，并且每个都带 `readlink -f` 的真实路径。

## 三、怎么读结果

- `-- 打开的文件` 里出现 `/tmp/tmp/uu/.uu.db`（或类似的库）→ 核心确实落盘，
  位置就是它的运行目录。那 8693454 里「OEM 把注册记录存在 `/tmp/uu/.uu.db`」
  这句话只是路径写错了，结论可以留着。
- 只有 socket、没有数据库文件 → 这个 build 在网络正常时根本不落盘。那这句话
  应该整段删掉，别再让人去找一个不存在的文件。
- `watch` 的差异清单是空的 → 这段时间它什么都没写。换个时机：刚绑定完、或者
  正在加速的那一刻。空本身就是结论。

**不要**为了「让它写点什么」而手工 `mkdir -p /data/uu.uu.db` 之类的目录：万一
核心是按「目录存不存在」分支的，造出来的空目录反而把它带到另一条路上，之后就
分不清是它的行为还是你造出来的了。

## 合回 master 之前

这个分支上的三处东西**不要**合回 `master`：

- `luci-app-uugamebooster/luasrc/controller/uuplugin.lua` 里的 `e.repro` 与
  `registering` 分支（会把老判据带回去）；
- `luasrc/view/uuplugin/uuplugin_status.htm` 里的 `registering` 文案与
  「复现开关」那一行；
- `root/etc/config/uuplugin` 的 `repro_strict_phase`。

`uu-trace` 本身是可以合回去的诊断工具 —— 它的 `strict` 子命令在没有那个开关时
只会写一条 UCI，不影响判据（controller 不认这个键）。真要合，就把
`strict` 子命令一起删掉，只留 `snapshot` / `watch` / `restart`。
