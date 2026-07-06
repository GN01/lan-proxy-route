# LAN Proxy Route

`luci-app-lan-proxy-route` 是一个轻量级 OpenWrt LuCI 服务，基于预装的国内 IPv4 库（GeoIP）做目的地址分流：国内与保留地址直连，其余流量视为国外，打 mark 后通过策略路由转发到一台局域网内的 X86 透明代理主机。

它的定位不是在 OpenWrt 上运行代理核心，而是让 OpenWrt 负责 GeoIP 集合、客户端访问控制、打 mark、策略路由和诊断；X86 主机负责 dae、mihomo、TProxy、eBPF tc 等真正的透明代理与出站策略。

## 适用场景

- OpenWrt 路由器希望保持轻量，不直接运行代理核心。
- 局域网内已有一台 X86 设备运行 dae、mihomo 或其他透明代理方案。
- 希望只有部分客户端走 X86 分流，其余流量继续走普通转发路径。
- 希望 OpenWrt 25.x 使用 `nftset`，同时兼容 QSDK12.5/QWRT 上的 `ipset` 方案。

## 不适用场景

- 需要多 X86 节点、自动选路、健康检查或复杂代理策略。这些逻辑应该放在 X86 代理主机上。
- 希望通过本项目让所有代理流量都获得 NSS 硬件 offload。被 fwmark/PBR 分流到 X86 的流量不应假设能走 NSS fast path。
- 需要完整 IPv6 分流。当前版本只实现 IPv4 数据面。
- 需要按域名精细分流。本项目自 v0.2.0 起改为纯 GeoIP 目的地址分流，不再依赖 dnsmasq/DNS。

## 流量模型

```text
LAN client
  -> 客户端过滤（all / allowlist / blocklist）
  -> 目的地址是保留地址 / 自定义绕过网段 (bypass_v4)  -> 正常转发
  -> 目的地址是国内 IP (china_v4)                     -> 正常转发
  -> 其余（视为国外）-> mark 0x210 -> table 210 -> X86 next-hop (onlink)
  -> X86 负责透明代理和复杂出站策略
```

OpenWrt 负责：

- 预装国内 IPv4 库（`/etc/lan-proxy-route/china_ip4.txt`）与在线更新
- `nftset` 或 `ipset` 集合填充（分块批量加载，数千条 CIDR 秒级完成）
- 源客户端 allowlist/blocklist
- bypass 与防回环目标
- fwmark、独立路由表和诊断
- LuCI 配置界面

X86 负责：

- 透明代理拦截
- DNS 策略（在 X86 上处理，OpenWrt 不再劫持 DNS）
- 节点选择、规则分流、订阅维护
- 代理日志和复杂策略

## 国内 IP 库

- 随包预装 `china_ip4.txt`（CIDR 列表）与 `china_ip4.ver`（版本号），数据来自 [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) 的 `china_ip4` 资源。
- LuCI「概况」页显示当前库版本与条目数，并提供「更新国内 IP 库」按钮在线更新。
- 命令行更新：

```sh
# 对比远端版本，有更新才下载（下载后自动 reload 服务）
/usr/share/lan-proxy-route/update-chnroute.sh update

# 强制重新下载
/usr/share/lan-proxy-route/update-chnroute.sh force-update

# 查看本地版本
/usr/share/lan-proxy-route/update-chnroute.sh version
```

- 默认更新源为 homeproxy 仓库 raw 地址，可在「基本设置」的 `chnroute_url`（国内 IP 库更新源）覆盖，值为包含 `china_ip4.txt`/`china_ip4.ver` 的目录 URL。
- 下载内容会逐行做 CIDR 格式校验且要求至少 1000 条，校验失败不会替换本地文件。

## NSS/offload 说明

本项目的目标是降低 OpenWrt 上代理核心的复杂度，而不是保证代理流量获得 NSS 硬件 offload。

被分流到 X86 的流量会经过：

```text
china_v4/bypass_v4 未命中 -> fwmark -> ip rule -> table 210 -> X86 next-hop
```

这类被 mark 并进入独立 routing table 的流量，在 IPQ8072A/QSDK/NSS 环境中不应假设可以继续走硬件 offload。真正更可能保留 NSS 的，是命中国内/保留地址、未被分流的普通 LAN 转发流量。

## 后端

- OpenWrt 25.x：优先使用 `nftset`、`nftables`、`firewall4`。
- QSDK12.5/QWRT：兼容 `ipset`、`iptables`。

运行依赖已经写入 `Makefile`，默认面向 OpenWrt 25.x / ImmortalWrt 的 `nftset` 后端（`firewall4`、`nftables`、`ip-full`）。

若手动选择 `ipset` 后端（例如 QSDK12.5/QWRT），需自行安装 legacy 依赖。部分 feed 可能没有 `iptables-mod-ipset`，请安装提供 `-m set` 支持的等价包：

```sh
# opkg 系统
opkg install ipset iptables iptables-mod-ipset
```

## 本地测试

```sh
sh tests/run.sh
```

测试覆盖：

- OpenWrt 包结构（含预装国内库检查）
- shell 语法
- nft/ipset 渲染（含 china_v4 分块加载）
- 国内库在线更新脚本（假 fetcher，含损坏下载回退）
- service CLI
- diagnostics/rpcd（含 update_chnroute）
- 幂等 cleanup 契约
- 最终 review 回归用例

## GitHub Actions

仓库包含 `.github/workflows/ci.yml`，可通过 GitHub Actions 页面手动触发 `workflow_dispatch`，或推送 `v*` tag 触发：

- `shell-tests`：执行 `sh tests/run.sh`
- `package-build`：下载 OpenWrt `25.12.5` x86/64 SDK，编译 OpenWrt 软件包
- `Smoke test package contents`：展开生成的 `.apk`，检查 init、service CLI、rpcd、LuCI menu/view、ACL 等关键安装文件
- `openwrt-package`：上传构建出的 `.apk` artifact
- `Publish GitHub Release`：手动触发时默认开启，会按 Makefile 的 `PKG_VERSION`/`PKG_RELEASE` 自动创建 tag（如 `v0.2.0-r1`）并发布 Release；也可在触发时自定义 tag 或关闭发布

## 安装

从 GitHub Actions artifact 下载生成的软件包后安装。OpenWrt 25.x 默认使用 APK：

```sh
apk add --allow-untrusted ./luci-app-lan-proxy-route-*.apk
```

如果依赖缺失，OpenWrt 25.x / ImmortalWrt 使用 APK 安装对应依赖：

```sh
apk update
apk add ip-full firewall4 nftables
```

QSDK12.5/QWRT 或仍使用 opkg 的系统，若需 `ipset` 后端再额外安装：

```sh
opkg update
opkg install ip-full ipset iptables iptables-mod-ipset
```

## OpenWrt 25.x nftset 验证

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
nft list table inet lan_proxy_route
nft list set inet lan_proxy_route china_v4 | head
ip rule show
ip route show table 210
```

## QSDK12.5/QWRT ipset 验证

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
ipset list lpr_china_v4 | head
iptables -t mangle -S LAN_PROXY_ROUTE
ip rule show
ip route show table 210
```

## 启动调试

LuCI「概况」页会显示运行状态、诊断项和最近 syslog。若启动失败，可先在 SSH 中逐步执行：

```sh
# 1. 校验 UCI 配置是否合法
/usr/share/lan-proxy-route/lan-proxy-route.sh validate

# 2. 预览将执行的 nft/ip 命令（不实际运行）
LPR_DRY_RUN=1 /usr/share/lan-proxy-route/lan-proxy-route.sh render

# 或使用 init.d 封装
/etc/init.d/lan-proxy-route trace

# 3. 详细启动：写入 syslog，第一条失败命令即退出
LPR_VERBOSE=1 /usr/share/lan-proxy-route/lan-proxy-route.sh apply

# 4. 查看诊断 JSON（含 enabled / running / china_list_version 字段）
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose

# 5. 查看服务日志
logread -e lan-proxy-route | tail -n 80

# 6. 正式重启
/etc/init.d/lan-proxy-route restart
```

常见失败原因：

- `invalid proxy IP`：X86 代理 IP 未填或格式错误
- `china IP list missing`：国内 IP 库文件缺失，可执行 `update-chnroute.sh force-update` 重新下载
- `unable to detect backend`：缺少 `nft`/`fw4`（nftset）或 `ipset`（ipset 后端）
- `command failed`：配合 `LPR_VERBOSE=1 apply` 查看是哪条 nft/ip 命令失败

## 路由验证

```sh
# 国外地址：应进入 table 210，下一跳指向 X86 代理主机
ip route get 8.8.8.8 mark 0x210

# 国内地址：不应被 mark，走普通默认路由
ip route get 223.5.5.5
```

## 建议实测

如果你关注 NSS/offload 和 CPU 利用率，建议对比三组数据：

1. 当前 OpenWrt 本机 TProxy/dae/mihomo 模式
2. 本项目 fwmark + table 210 + X86 透明代理模式
3. 纯普通转发/NSS baseline

可以观察：

```sh
top
cat /proc/interrupts
ip rule show
ip route show table 210
nft list ruleset
conntrack -L | grep -E 'OFFLOAD|HW_OFFLOAD'
```

如果固件提供 NSS/ECM debugfs，也建议同时观察 NSS flow counter。
