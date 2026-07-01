# LAN Proxy Route LuCI Service Design

## Purpose

Build a lightweight OpenWrt LuCI service that routes selected foreign traffic from LAN clients to a single LAN-side X86 transparent proxy host. OpenWrt remains responsible for DNS entry control, domain/IP set management, packet marking, policy routing, and diagnostics. The X86 host remains responsible for proxy logic, transparent interception, and outbound proxy selection.

The first implementation targets OpenWrt 25.12 with `firewall4`, `nftables`, `dnsmasq-full`, and `nftset`. A compatibility backend supports QSDK12.5/QWRT with `ipset`, while keeping the same LuCI configuration model. QSDK also uses the modern LuCI JavaScript view structure, so no legacy CGI LuCI entry is required.

## Goals

- Route foreign-domain or foreign-IP traffic for selected LAN clients to one X86 transparent proxy host.
- Keep proxy cores such as dae, mihomo, or ssrplus off the OpenWrt router.
- Preserve a clean default forwarding path for domestic and bypass traffic to improve the chance that NSS/offload paths remain useful.
- Use `nftset` as the primary backend and `ipset` as a compatibility backend.
- Force LAN DNS port 53 to OpenWrt dnsmasq so domain-based set filling is reliable.
- Support `real-ip`, `fake-ip`, and `mixed` DNS result modes.
- Include source client allow/block controls, because only some LAN hosts may need foreign traffic routed to the X86 proxy.
- Provide diagnostics that explain whether DNS, sets, marks, routes, and X86 reachability are working.

## Non-Goals

- Do not run a proxy core on OpenWrt.
- Do not support multiple X86 proxy nodes in the first version.
- Do not implement complex policy logic on OpenWrt, such as per-application routing, automatic proxy selection, node health balancing, or multi-WAN policies. These belong on the X86 proxy host.
- Do not use OSPF or dynamic routing for the first version.
- Do not use `mwan3` as the main model, because the problem is LAN-side transparent proxy routing, not multi-WAN failover or load balancing.
- Do not promise that marked policy-routed flows always use NSS fast paths. The design minimizes interference with normal forwarding, but final NSS behavior must be measured on target firmware.
- Do not enable IPv6 routing in the first version. IPv6 can be added after IPv4 behavior is stable.

## Architecture

Traffic flow:

```text
LAN client
  -> OpenWrt forces DNS 53 to dnsmasq
  -> dnsmasq handles ad blocking, local domains, domestic DNS, and proxy DNS forwarding
  -> proxy domains populate nftset/ipset entries
  -> OpenWrt marks allowed source traffic whose destination matches proxy sets
  -> ip rule selects a dedicated route table
  -> route table sends marked traffic to the X86 transparent proxy host
  -> X86 dae eBPF tc/TProxy or equivalent proxy logic intercepts and proxies traffic
```

OpenWrt owns:

- LAN DNS entry point.
- Ad filtering and domain list wiring.
- `nftset`/`ipset` population.
- Source client allow/block policy.
- Bypass and anti-loop rules.
- Packet mark and policy route table.
- LuCI configuration and diagnostics.

The X86 host owns:

- Proxy DNS responses for selected domains.
- `real-ip` or `fake-ip` handling.
- Transparent proxy interception with dae eBPF tc/TProxy or equivalent.
- Actual proxy outbound selection and complex rules.

## Configuration Model

The UCI package is `lan_proxy_route`.

### Global

```text
config global
  option enabled '1'
  option backend 'auto'          # auto/nftset/ipset
  option dns_mode 'real-ip'      # real-ip/fake-ip/mixed
  option mark '0x210'
  option table '210'
  option priority '10210'
  option lan_if 'br-lan'
```

`auto` prefers `nftset` when `nft` and firewall4-style support are present. It falls back to `ipset` when running on QSDK/QWRT environments that need ipset compatibility.

### Proxy Host

```text
config proxy_node 'x86'
  option ip '192.168.1.2'
  option dns_port '53'
  option mode 'dae'
```

Only one X86 proxy host is supported in the first version. The `mode` value is informational and can drive UI hints or default text, but OpenWrt must not depend on dae-specific internals.

### DNS

```text
config dns
  option hijack_53 '1'
  option block_dot '1'
  list domestic_dns '114.114.114.114'
  list domestic_dns '223.5.5.5'
  list proxy_dns '192.168.1.2#53'
```

LAN client DNS port 53 is redirected to OpenWrt. DoT on TCP/853 can be blocked. DoH cannot be fully controlled in the first version; diagnostics and UI text should explain that browser or OS private DNS may bypass domain-based routing unless separately disabled or blocked by external lists.

### Domain Lists

```text
config list 'gfwlist'
  option enabled '1'
  option type 'domain'
  option dns_result 'real-ip'    # real-ip/fake-ip
  option source '/etc/lan-proxy-route/gfwlist.txt'
  option dns_upstream 'proxy'
```

Domain lists can be used for proxy routing, ad blocking, or bypass. In `mixed` DNS mode, each list chooses `real-ip` or `fake-ip`. The first version uses list-level mode selection, not per-domain mode selection.

### Client Access

```text
config access
  option mode 'all'              # all/allowlist/blocklist
  list allow_ip '192.168.1.10'
  list allow_ip '192.168.1.20'
  list allow_cidr '192.168.1.128/25'
  list block_ip '192.168.1.30'
```

Client access is the main policy dimension on OpenWrt. Complex proxy behavior after traffic reaches the X86 host is not modeled in this service.

The effective logic is:

```text
src matches access policy
AND dst matches proxy target policy
AND dst does not match bypass policy
=> mark
=> policy route to X86
```

The LuCI UI should encourage DHCP static leases for devices that are controlled by source IP.

### Bypass

```text
config bypass
  list cidr '192.168.0.0/16'
  list cidr '10.0.0.0/8'
  list cidr '172.16.0.0/12'
  list host '192.168.1.2'
  list host '114.114.114.114'
  list host '223.5.5.5'
```

Bypass entries always include OpenWrt addresses, the X86 proxy address, LAN/RFC1918 ranges, domestic DNS servers, multicast/broadcast/loopback ranges, and user-defined bypass entries.

The fake IP range is mode-dependent:

- `real-ip`: bypass `198.18.0.0/15` by default.
- `fake-ip`: route the configured fake IP CIDR to X86.
- `mixed`: follow list-generated proxy sets and show a warning for overlapping behavior.

## Rule Generation

### nftset Backend

The nft backend creates a dedicated table:

```text
table inet lan_proxy_route {
  set clients_v4
  set blocked_clients_v4
  set bypass_v4
  set proxy_v4

  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;
  }
}
```

Rule order:

1. Return immediately for non-LAN ingress.
2. Return for destinations in `bypass_v4`.
3. Apply client access policy.
4. Mark traffic whose destination is in `proxy_v4`.
5. In `fake-ip` mode, mark traffic whose destination is in the configured fake IP CIDR.

Example shape:

```text
iifname "br-lan" ip daddr @bypass_v4 return
iifname "br-lan" ip saddr @clients_v4 ip daddr @proxy_v4 meta mark set 0x210
iifname "br-lan" ip saddr @clients_v4 ip daddr 198.18.0.0/15 meta mark set 0x210
```

The exact generated rule set must account for `all`, `allowlist`, and `blocklist` modes without creating invalid empty set references.

### ipset Backend

The ipset backend creates:

```text
lpr_clients
lpr_blocked_clients
lpr_bypass_v4
lpr_proxy_v4
```

It installs mangle table rules with the same order as the nft backend:

1. Skip bypass destinations.
2. Apply client access policy.
3. Match proxy destinations.
4. Set fwmark.

### Policy Routing

Both backends manage the same policy route:

```text
ip rule add fwmark 0x210 lookup 210 priority 10210
ip route add default via <X86_IP> dev <LAN_IF> table 210
```

The service must clean up only rules and routes it owns. It must not flush user-created route tables or unrelated firewall state.

## DNS and List Handling

`dnsmasq.sh` generates `/tmp/dnsmasq.d/lan-proxy-route.conf`.

Responsibilities:

- Generate DNS hijack firewall rules for LAN port 53.
- Generate optional TCP/853 blocking.
- Generate ad blocking entries before proxy forwarding entries.
- Generate domestic DNS forwarding for normal domains.
- Generate proxy DNS forwarding for selected domain lists.
- Generate `nftset` or `ipset` options so resolved proxy domains populate `proxy_v4`.
- Preserve a clear separation between "use proxy DNS" and "route via proxy" even when the default UI maps them together.

For domain-to-set filling, `dnsmasq-full` is required. The package should declare dependencies or show a prominent missing dependency diagnostic when set filling is unavailable.

## LuCI UI

Use modern LuCI JavaScript views with rpcd ACLs. Do not add a legacy CGI route.

Tabs:

1. Overview
   - Service enabled state.
   - Active backend.
   - X86 reachability.
   - `ip rule` and route table status.
   - Set entry counts.
   - DNS hijack status.
   - Recent errors.

2. Basic Settings
   - X86 proxy IP and DNS port.
   - Backend: automatic, nftset, ipset.
   - DNS result mode: real-ip, fake-ip, mixed.
   - mark, route table, rule priority.
   - LAN interface.

3. DNS and Filtering
   - Force LAN DNS 53 to OpenWrt.
   - Block DoT 853.
   - Domestic DNS servers.
   - Proxy DNS servers.
   - Ad block list source.
   - GFW/proxy domain list sources.
   - Custom proxy and bypass domain lists.

4. Client Control
   - Access mode: all, allowlist, blocklist.
   - Allow IP and CIDR entries.
   - Block IP and CIDR entries.
   - Optional selection from DHCP leases/static leases.

5. Rules and Diagnostics
   - Bypass CIDR and host entries.
   - fake IP CIDR.
   - Reload service.
   - Test domain resolution.
   - Test whether a source IP and destination IP would be routed to X86.
   - Show generated dnsmasq, nft/ipset, `ip rule`, and route table summaries.

## Package Structure

```text
Makefile
root/
  etc/
    config/lan_proxy_route
    init.d/lan-proxy-route
    lan-proxy-route/
      gfwlist.txt
      adblock.txt
      custom-proxy-domains.txt
      custom-bypass-domains.txt
  usr/
    share/lan-proxy-route/
      lan-proxy-route.sh
      backends/
        nft.sh
        ipset.sh
      dnsmasq.sh
      diagnostics.sh
    libexec/rpcd/lan-proxy-route
    share/rpcd/acl.d/luci-app-lan-proxy-route.json
    share/luci/menu.d/luci-app-lan-proxy-route.json
    share/luci-static/resources/view/lan-proxy-route/
      overview.js
      settings.js
      dns.js
      clients.js
      rules.js
```

`init.d/lan-proxy-route`:

- Provides `start`, `reload`, and `stop`.
- Calls the main service script.
- Reloads dnsmasq and firewall state as needed.
- Cleans up only service-owned runtime state on stop.

`lan-proxy-route.sh`:

- Reads and validates UCI.
- Selects backend.
- Validates X86 IP, LAN interface, mark, table, and priority.
- Calls DNS, backend, and diagnostics modules.

`backends/nft.sh`:

- Manages service-owned nft table, sets, and mark rules.
- Manages policy route and rule.

`backends/ipset.sh`:

- Manages service-owned ipsets and iptables mangle rules.
- Manages policy route and rule.

`dnsmasq.sh`:

- Generates runtime dnsmasq configuration.
- Handles ad blocking, proxy domains, domestic DNS, proxy DNS, DNS hijack, and optional DoT blocking.

`diagnostics.sh`:

- Outputs JSON for rpcd/LuCI.
- Reports backend, dependency status, set counts, rules, routes, DNS config, X86 reachability, and test results.

## Error Handling

- Missing X86 IP: refuse to start and show LuCI validation error.
- X86 unreachable: warn but do not necessarily refuse start, because the host may be temporarily offline.
- Missing `dnsmasq-full` set support: warn and mark domain-based routing unavailable.
- Backend auto-detection failure: refuse to start with a clear backend diagnostic.
- Conflicting mark/table/priority: warn and show generated command context.
- Invalid CIDR/IP/domain entries: reject at validation time in LuCI and in shell scripts.
- Stop/reload must be idempotent.

## Testing

Local tests:

- `sh -n` for all shell scripts.
- Fixture-based command generation tests for nft backend.
- Fixture-based command generation tests for ipset backend.
- Fixture-based dnsmasq config generation tests.
- UCI validation tests for IP, CIDR, mark, table, priority, and DNS mode.

OpenWrt tests:

- OpenWrt 25.12: verify `nftset`, `fw4`, `dnsmasq-full`, policy route, and LuCI views.
- QSDK12.5/QWRT: verify `ipset`, iptables mangle, dnsmasq set filling, and modern LuCI views.

Integration tests:

- Allowed client visits proxy domain: DNS resolves, set entry appears, mark rule matches, route table sends traffic to X86.
- Non-allowed client visits proxy domain: DNS may resolve but route mark does not apply.
- X86 IP, OpenWrt IPs, LAN CIDRs, and domestic DNS servers never route to X86.
- `fake-ip` mode routes configured fake IP CIDR to X86.
- `real-ip` mode does not accidentally route `198.18.0.0/15` unless configured.
- Service reload does not duplicate rules.
- Service stop removes only service-owned rules and leaves unrelated firewall/routing state intact.

## Implementation Defaults

- Use `luci-app-lan-proxy-route` as the package name and `lan-proxy-route` as the service name.
- Ship with static list files and local custom list files in the first version. A list downloader or subscription updater can be added later.
- Include a minimal CLI diagnostic path through the same scripts used by rpcd so LuCI and shell diagnostics report the same state.
