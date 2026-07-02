# LAN Proxy Route

`luci-app-lan-proxy-route` 是一个轻量级 OpenWrt LuCI 服务，用于把选定 LAN 客户端的国外域名/IP 流量路由到一台局域网内的 X86 透明代理主机。

它的定位不是在 OpenWrt 上运行代理核心，而是让 OpenWrt 负责 DNS 入口、域名/IP 集合、客户端访问控制、打 mark、策略路由和诊断；X86 主机负责 dae、mihomo、TProxy、eBPF tc 等真正的透明代理与出站策略。

## 适用场景

- OpenWrt 路由器希望保持轻量，不直接运行代理核心。
- 局域网内已有一台 X86 设备运行 dae、mihomo 或其他透明代理方案。
- 希望只有部分客户端或部分国外域名/IP 走 X86，其余流量继续走普通转发路径。
- 希望广告过滤、DNS 53 劫持、DoT 阻断和分流诊断统一在 OpenWrt LuCI 中管理。
- 希望 OpenWrt 25.12 使用 `nftset`，同时兼容 QSDK12.5/QWRT 上的 `ipset` 方案。

## 不适用场景

- 需要多 X86 节点、自动选路、健康检查或复杂代理策略。这些逻辑应该放在 X86 代理主机上。
- 希望通过本项目让所有代理流量都获得 NSS 硬件 offload。被 fwmark/PBR 分流到 X86 的流量不应假设能走 NSS fast path。
- 当前 OpenWrt 本机运行代理时 CPU、温度、延迟都很低，并且没有维护复杂度问题。这种情况下迁移到 X86 的收益可能不明显。
- 需要完整 IPv6 分流。本项目第一版只实现 IPv4 数据面。

## 架构

```text
LAN client
  -> OpenWrt 强制 DNS 53 到 dnsmasq
  -> dnsmasq 处理广告过滤、国内 DNS、代理 DNS、域名集合填充
  -> nftset/ipset 命中代理目标
  -> OpenWrt 对允许的源客户端流量打 mark
  -> ip rule 选择独立路由表
  -> 默认路由下一跳指向 X86 透明代理主机
  -> X86 负责透明代理和复杂出站策略
```

OpenWrt 负责：

- LAN DNS 入口控制
- `gfwlist`、广告过滤、自定义代理/绕过域名列表
- `nftset` 或 `ipset` 集合填充
- 源客户端 allowlist/blocklist
- bypass 和防回环目标
- fwmark、独立路由表和诊断
- LuCI 配置界面

X86 负责：

- 透明代理拦截
- `real-ip`、`fake-ip` 或混合 DNS 策略
- 节点选择、规则分流、订阅维护
- 代理日志和复杂策略

## NSS/offload 说明

本项目的目标是降低 OpenWrt 上代理核心的复杂度，而不是保证代理流量获得 NSS 硬件 offload。

被分流到 X86 的流量会经过：

```text
nftset/ipset match -> fwmark -> ip rule -> table 210 -> X86 next-hop
```

这类被 mark 并进入独立 routing table 的流量，在 IPQ8072A/QSDK/NSS 环境中不应假设可以继续走硬件 offload。真正更可能保留 NSS 的，是未被本项目分流的普通 LAN 转发流量。

如果你的 OpenWrt 本机运行 TProxy/dae/mihomo 时 CPU 已经很低，例如 4K/8K 流媒体下也不超过 20%，那么本项目不一定能带来性能收益。更合理的使用方式是：只把少量客户端、特定域名或测试 VLAN 分流到 X86，其余流量继续普通转发。

## 后端

- OpenWrt 25.12：优先使用 `nftset`、`nftables`、`firewall4`、`dnsmasq-full`。
- QSDK12.5/QWRT：兼容 `ipset`、`iptables`、`dnsmasq-full`。

运行依赖已经写入 `Makefile`。部分 QSDK feed 可能会重命名或拆分 `iptables`/`ipset` 相关包；如果目标 feed 没有 `iptables-mod-ipset`，请安装提供 `-m set` 支持的等价包。

## 本地测试

```sh
sh tests/run.sh
```

测试覆盖：

- OpenWrt 包结构
- shell 语法
- nft/ipset 渲染
- dnsmasq 配置渲染
- service CLI
- diagnostics/rpcd
- 幂等 cleanup 契约
- 最终 review 回归用例

## GitHub Actions

仓库包含 `.github/workflows/ci.yml`：

- `shell-tests`：执行 `sh tests/run.sh`
- `package-build`：下载 OpenWrt `25.12.5` x86/64 SDK，编译 IPK
- `Smoke test IPK contents`：展开生成的 `.ipk`，检查 init、service CLI、rpcd、LuCI menu/view、ACL 等关键安装文件
- `openwrt-ipk`：上传构建出的 IPK artifact

当前 CI 使用 x86/64 SDK 做通用打包验证。后续可以增加 IPQ807x/QSDK 目标矩阵，但 QSDK feed 的包名和 SDK 获取方式通常需要单独适配。

## 安装

从 GitHub Actions artifact 下载生成的 IPK 后，在 OpenWrt 上安装：

```sh
opkg install ./luci-app-lan-proxy-route_*.ipk
```

如果依赖缺失，先安装对应依赖：

```sh
opkg update
opkg install dnsmasq-full ip-full firewall4 nftables ipset iptables iptables-mod-ipset
```

## OpenWrt 25.12 nftset 验证

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
nft list table inet lan_proxy_route
ip rule show
ip route show table 210
```

## QSDK12.5/QWRT ipset 验证

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
ipset list lpr_proxy_v4
iptables -t mangle -S LAN_PROXY_ROUTE
ip rule show
ip route show table 210
```

## DNS 验证

```sh
nslookup google.com 192.168.1.1
nslookup doubleclick.net 192.168.1.1
```

广告过滤命中时应返回 `0.0.0.0`。代理域名应写入 `nftset` 或 `ipset`。

## 路由验证

```sh
ip route get 8.8.8.8 mark 0x210
```

期望看到流量进入 table `210`，下一跳指向 X86 代理主机。

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
