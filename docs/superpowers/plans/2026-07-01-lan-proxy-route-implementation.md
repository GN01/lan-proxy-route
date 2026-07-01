# LAN Proxy Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `luci-app-lan-proxy-route`, a lightweight OpenWrt LuCI service that routes selected LAN clients' foreign traffic to one LAN-side X86 transparent proxy host.

**Architecture:** OpenWrt owns DNS entry control, domain/IP set filling, source-client access control, packet marking, policy routing, and diagnostics. X86 owns transparent proxy interception and outbound proxy policy. The package uses a shared UCI model with an `nftset` backend for OpenWrt 25.12 and an `ipset` backend for QSDK12.5/QWRT.

**Tech Stack:** OpenWrt package Makefile, POSIX shell, UCI, procd init script, dnsmasq-full set options, nftables, ipset/iptables, iproute2 policy routing, rpcd, modern LuCI JavaScript views.

## Global Constraints

- The package name is `luci-app-lan-proxy-route`; the service name is `lan-proxy-route`.
- The UCI package is `lan_proxy_route`.
- The first implementation targets OpenWrt 25.12 with `firewall4`, `nftables`, `dnsmasq-full`, and `nftset`.
- QSDK12.5/QWRT compatibility uses `ipset` while keeping the same LuCI configuration model.
- QSDK also uses modern LuCI JavaScript views; no legacy CGI LuCI entry is required.
- OpenWrt must not run a proxy core.
- Only one X86 proxy host is supported in the first version.
- Complex proxy policy belongs on the X86 host, not OpenWrt.
- Do not use OSPF, dynamic routing, or `mwan3` as the main model.
- IPv4 is implemented first; IPv6 routing is not enabled in the first version.
- `real-ip`, `fake-ip`, and `mixed` DNS result modes are supported.
- LAN DNS port 53 can be forced to OpenWrt dnsmasq.
- Client source allow/block control is a primary OpenWrt-side policy dimension.
- Service stop and reload must be idempotent and must clean up only service-owned runtime state.

---

## File Structure

- `Makefile`: OpenWrt package metadata and install rules.
- `root/etc/config/lan_proxy_route`: default UCI configuration.
- `root/etc/init.d/lan-proxy-route`: procd-style init script that delegates to the service CLI.
- `root/etc/lan-proxy-route/gfwlist.txt`: bundled proxy-domain list seed.
- `root/etc/lan-proxy-route/adblock.txt`: bundled ad-block list seed.
- `root/etc/lan-proxy-route/custom-proxy-domains.txt`: user-editable local proxy domain list.
- `root/etc/lan-proxy-route/custom-bypass-domains.txt`: user-editable local bypass domain list.
- `root/usr/share/lan-proxy-route/common.sh`: shared validation, logging, backend detection, and dry-run helpers.
- `root/usr/share/lan-proxy-route/lan-proxy-route.sh`: main CLI entry point for validate, render, apply, cleanup, and diagnose.
- `root/usr/share/lan-proxy-route/backends/nft.sh`: nftables/nftset renderer and applier.
- `root/usr/share/lan-proxy-route/backends/ipset.sh`: ipset/iptables renderer and applier.
- `root/usr/share/lan-proxy-route/dnsmasq.sh`: dnsmasq config and DNS firewall rule renderer.
- `root/usr/share/lan-proxy-route/diagnostics.sh`: JSON diagnostics for CLI and rpcd.
- `root/usr/libexec/rpcd/lan-proxy-route`: rpcd executable wrapper.
- `root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json`: LuCI rpcd permissions.
- `root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json`: LuCI menu entries.
- `root/www/luci-static/resources/view/lan-proxy-route/overview.js`: status page.
- `root/www/luci-static/resources/view/lan-proxy-route/settings.js`: base settings form.
- `root/www/luci-static/resources/view/lan-proxy-route/dns.js`: DNS and filtering form.
- `root/www/luci-static/resources/view/lan-proxy-route/clients.js`: client access control form.
- `root/www/luci-static/resources/view/lan-proxy-route/rules.js`: bypass and diagnostics page.
- `tests/lib/assert.sh`: tiny POSIX shell assertion helpers.
- `tests/run.sh`: local test runner.
- `tests/unit/*.sh`: unit tests for shell renderers.
- `tests/static/*.sh`: static package and LuCI structure tests.
- `README.md`: development, install, and runtime notes.

## Task 1: Package Skeleton and Local Test Harness

**Files:**
- Create: `Makefile`
- Create: `root/etc/config/lan_proxy_route`
- Create: `root/etc/lan-proxy-route/gfwlist.txt`
- Create: `root/etc/lan-proxy-route/adblock.txt`
- Create: `root/etc/lan-proxy-route/custom-proxy-domains.txt`
- Create: `root/etc/lan-proxy-route/custom-bypass-domains.txt`
- Create: `tests/lib/assert.sh`
- Create: `tests/run.sh`
- Create: `tests/static/test_package_skeleton.sh`
- Create: `README.md`

**Interfaces:**
- Produces default UCI sections: `global`, `proxy_node x86`, `dns`, `access`, and `bypass`.
- Produces `tests/run.sh`, which all later tasks use as the local verification command.

- [ ] **Step 1: Write the failing skeleton test**

Create `tests/static/test_package_skeleton.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh

assert_file_exists Makefile
assert_file_exists root/etc/config/lan_proxy_route
assert_file_exists root/etc/lan-proxy-route/gfwlist.txt
assert_file_exists root/etc/lan-proxy-route/adblock.txt
assert_file_exists root/etc/lan-proxy-route/custom-proxy-domains.txt
assert_file_exists root/etc/lan-proxy-route/custom-bypass-domains.txt

assert_contains Makefile "PKG_NAME:=luci-app-lan-proxy-route"
assert_contains Makefile "LUCI_TITLE:=LuCI support for LAN Proxy Route"
assert_contains root/etc/config/lan_proxy_route "config global"
assert_contains root/etc/config/lan_proxy_route "option backend 'auto'"
assert_contains root/etc/config/lan_proxy_route "option dns_mode 'real-ip'"
assert_contains root/etc/config/lan_proxy_route "config proxy_node 'x86'"
assert_contains root/etc/config/lan_proxy_route "config access"
assert_contains root/etc/config/lan_proxy_route "option mode 'all'"
assert_contains root/etc/config/lan_proxy_route "config bypass"
```

Create `tests/lib/assert.sh`:

```sh
#!/bin/sh

fail() {
	printf 'not ok - %s\n' "$*" >&2
	exit 1
}

assert_file_exists() {
	[ -f "$1" ] || fail "missing file: $1"
}

assert_executable() {
	[ -x "$1" ] || fail "not executable: $1"
}

assert_contains() {
	file="$1"
	pattern="$2"
	grep -F "$pattern" "$file" >/dev/null 2>&1 || fail "$file does not contain: $pattern"
}

assert_not_contains() {
	file="$1"
	pattern="$2"
	if grep -F "$pattern" "$file" >/dev/null 2>&1; then
		fail "$file unexpectedly contains: $pattern"
	fi
}

assert_eq() {
	expected="$1"
	actual="$2"
	[ "$expected" = "$actual" ] || fail "expected [$expected], got [$actual]"
}
```

Create `tests/run.sh`:

```sh
#!/bin/sh
set -eu

for test_script in tests/static/*.sh tests/unit/*.sh; do
	[ -f "$test_script" ] || continue
	printf '==> %s\n' "$test_script"
	sh "$test_script"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
chmod +x tests/run.sh tests/static/test_package_skeleton.sh
sh tests/run.sh
```

Expected: FAIL with `missing file: Makefile`.

- [ ] **Step 3: Create package skeleton files**

Create `Makefile`:

```make
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-lan-proxy-route
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Gin
PKG_LICENSE:=MIT

LUCI_TITLE:=LuCI support for LAN Proxy Route
LUCI_DESCRIPTION:=Route selected LAN clients foreign traffic to one LAN-side transparent proxy host.
LUCI_DEPENDS:=+luci-base +rpcd +dnsmasq-full +ip-full
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
```

Create `root/etc/config/lan_proxy_route`:

```text
config global
	option enabled '0'
	option backend 'auto'
	option dns_mode 'real-ip'
	option mark '0x210'
	option table '210'
	option priority '10210'
	option lan_if 'br-lan'
	option fake_ip_cidr '198.18.0.0/15'

config proxy_node 'x86'
	option ip '192.168.1.2'
	option dns_port '53'
	option mode 'dae'

config dns
	option hijack_53 '1'
	option block_dot '1'
	list domestic_dns '114.114.114.114'
	list domestic_dns '223.5.5.5'
	list proxy_dns '192.168.1.2#53'

config list 'gfwlist'
	option enabled '1'
	option type 'domain'
	option role 'proxy'
	option dns_result 'real-ip'
	option source '/etc/lan-proxy-route/gfwlist.txt'
	option dns_upstream 'proxy'

config list 'adblock'
	option enabled '1'
	option type 'domain'
	option role 'adblock'
	option source '/etc/lan-proxy-route/adblock.txt'

config access
	option mode 'all'

config bypass
	list cidr '10.0.0.0/8'
	list cidr '172.16.0.0/12'
	list cidr '192.168.0.0/16'
	list cidr '127.0.0.0/8'
	list cidr '224.0.0.0/4'
	list cidr '255.255.255.255/32'
```

Create list seed files:

```text
# root/etc/lan-proxy-route/gfwlist.txt
# One domain per line. Leading dots are accepted by the renderer.
google.com
youtube.com
github.com
```

```text
# root/etc/lan-proxy-route/adblock.txt
# One domain per line.
doubleclick.net
googlesyndication.com
```

```text
# root/etc/lan-proxy-route/custom-proxy-domains.txt
# Local proxy domains. One domain per line.
```

```text
# root/etc/lan-proxy-route/custom-bypass-domains.txt
# Local bypass domains. One domain per line.
```

Create `README.md`:

````markdown
# LAN Proxy Route

`luci-app-lan-proxy-route` is a lightweight OpenWrt LuCI service that routes selected LAN clients' foreign traffic to one LAN-side X86 transparent proxy host.

OpenWrt handles DNS entry control, set filling, packet marks, policy routing, and diagnostics. The X86 host handles transparent proxy interception and outbound proxy policy.

The primary backend is `nftset` for OpenWrt 25.12. The compatibility backend is `ipset` for QSDK12.5/QWRT.

## Local Checks

Run:

```sh
sh tests/run.sh
```
````

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with one `==>` line and no `not ok` output.

- [ ] **Step 5: Commit**

```bash
git add Makefile README.md root/etc/config/lan_proxy_route root/etc/lan-proxy-route tests
git commit -m "feat: add package skeleton"
```

## Task 2: Common Shell Validation and Backend Detection

**Files:**
- Create: `root/usr/share/lan-proxy-route/common.sh`
- Create: `tests/unit/test_common.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces `lpr_is_ipv4 VALUE`, `lpr_is_cidr VALUE`, `lpr_is_domain VALUE`, `lpr_is_uint VALUE`, `lpr_is_mark VALUE`.
- Produces `lpr_detect_backend REQUESTED`, returning `nftset` or `ipset`.
- Produces `lpr_cmd COMMAND...`, which prints commands when `LPR_DRY_RUN=1` and executes them otherwise.

- [ ] **Step 1: Write the failing common tests**

Create `tests/unit/test_common.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh

lpr_is_ipv4 192.168.1.2 || fail "valid IPv4 rejected"
lpr_is_ipv4 0.0.0.0 || fail "zero IPv4 rejected"
lpr_is_ipv4 255.255.255.255 || fail "broadcast IPv4 rejected"
if lpr_is_ipv4 999.1.1.1; then fail "invalid IPv4 accepted"; fi
if lpr_is_ipv4 abc.def.ghi.jkl; then fail "text IPv4 accepted"; fi

lpr_is_cidr 192.168.1.0/24 || fail "valid CIDR rejected"
lpr_is_cidr 198.18.0.0/15 || fail "fake CIDR rejected"
if lpr_is_cidr 192.168.1.0/33; then fail "invalid CIDR prefix accepted"; fi
if lpr_is_cidr 192.168.1.1; then fail "plain IP accepted as CIDR"; fi

lpr_is_domain google.com || fail "valid domain rejected"
lpr_is_domain .youtube.com || fail "leading dot domain rejected"
if lpr_is_domain "bad domain.com"; then fail "domain with space accepted"; fi
if lpr_is_domain "-bad.example"; then fail "leading dash accepted"; fi

lpr_is_uint 210 || fail "valid uint rejected"
if lpr_is_uint abc; then fail "text uint accepted"; fi

lpr_is_mark 0x210 || fail "hex mark rejected"
lpr_is_mark 528 || fail "decimal mark rejected"
if lpr_is_mark 0xzz; then fail "invalid hex mark accepted"; fi

PATH="$PWD/tests/fixtures/nft-bin:$PATH"
mkdir -p tests/fixtures/nft-bin
printf '#!/bin/sh\nexit 0\n' > tests/fixtures/nft-bin/nft
chmod +x tests/fixtures/nft-bin/nft
assert_eq nftset "$(lpr_detect_backend auto)"
assert_eq nftset "$(lpr_detect_backend nftset)"
assert_eq ipset "$(lpr_detect_backend ipset)"
```

Modify `tests/run.sh` to include unit tests after static tests:

```sh
#!/bin/sh
set -eu

for test_script in tests/static/*.sh tests/unit/*.sh; do
	[ -f "$test_script" ] || continue
	printf '==> %s\n' "$test_script"
	sh "$test_script"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `. ./root/usr/share/lan-proxy-route/common.sh: No such file`.

- [ ] **Step 3: Implement common helpers**

Create `root/usr/share/lan-proxy-route/common.sh`:

```sh
#!/bin/sh

LPR_NAME="lan-proxy-route"
LPR_TABLE_NAME="lan_proxy_route"

lpr_log() {
	logger -t "$LPR_NAME" "$*" 2>/dev/null || printf '%s\n' "$*" >&2
}

lpr_die() {
	printf '%s\n' "$*" >&2
	exit 1
}

lpr_is_uint() {
	case "${1:-}" in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

lpr_is_ipv4() {
	value="${1:-}"
	old_ifs="$IFS"
	IFS=.
	set -- $value
	IFS="$old_ifs"
	[ "$#" -eq 4 ] || return 1
	for octet in "$@"; do
		lpr_is_uint "$octet" || return 1
		[ "$octet" -ge 0 ] 2>/dev/null || return 1
		[ "$octet" -le 255 ] 2>/dev/null || return 1
	done
	return 0
}

lpr_is_cidr() {
	value="${1:-}"
	case "$value" in
		*/*) ip="${value%/*}"; prefix="${value#*/}" ;;
		*) return 1 ;;
	esac
	lpr_is_ipv4 "$ip" || return 1
	lpr_is_uint "$prefix" || return 1
	[ "$prefix" -ge 0 ] 2>/dev/null || return 1
	[ "$prefix" -le 32 ] 2>/dev/null || return 1
}

lpr_is_domain() {
	value="${1:-}"
	[ -n "$value" ] || return 1
	case "$value" in
		.*) value="${value#.}" ;;
	esac
	case "$value" in
		*' '*|*'/'*|'-'*|*'.-'*|*'..'*|''|'.') return 1 ;;
	esac
	case "$value" in
		*[!A-Za-z0-9.-]*) return 1 ;;
	esac
	case "$value" in
		*.*) return 0 ;;
		*) return 1 ;;
	esac
}

lpr_is_mark() {
	value="${1:-}"
	case "$value" in
		0x*) hex="${value#0x}" ;;
		0X*) hex="${value#0X}" ;;
		*) lpr_is_uint "$value" && return 0; return 1 ;;
	esac
	[ -n "$hex" ] || return 1
	case "$hex" in
		*[!0-9A-Fa-f]*) return 1 ;;
		*) return 0 ;;
	esac
}

lpr_have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

lpr_detect_backend() {
	requested="${1:-auto}"
	case "$requested" in
		nftset|ipset) printf '%s\n' "$requested"; return 0 ;;
		auto)
			if lpr_have_cmd nft; then
				printf '%s\n' nftset
			elif lpr_have_cmd ipset; then
				printf '%s\n' ipset
			else
				return 1
			fi
			;;
		*) return 1 ;;
	esac
}

lpr_cmd() {
	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		printf '%s\n' "$*"
	else
		"$@"
	fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with static and common tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/lan-proxy-route/common.sh tests/run.sh tests/unit/test_common.sh
git commit -m "feat: add common validation helpers"
```

## Task 3: nftset Backend Renderer

**Files:**
- Create: `root/usr/share/lan-proxy-route/backends/nft.sh`
- Create: `tests/unit/test_nft_backend.sh`

**Interfaces:**
- Consumes validation helpers from `common.sh`.
- Produces `lpr_nft_render_table LAN_IF MARK ACCESS_MODE DNS_MODE FAKE_CIDR`.
- Produces `lpr_nft_render_policy_route MARK TABLE PRIORITY X86_IP LAN_IF`.
- Produces `lpr_nft_render_cleanup MARK TABLE PRIORITY`.

- [ ] **Step 1: Write the failing nft backend tests**

Create `tests/unit/test_nft_backend.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh

out="$(lpr_nft_render_table br-lan 0x210 all real-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-all.out
assert_contains /tmp/lpr-nft-all.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-nft-all.out "set bypass_v4"
assert_contains /tmp/lpr-nft-all.out "set proxy_v4"
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @bypass_v4 return'
assert_contains /tmp/lpr-nft-all.out 'iifname "br-lan" ip daddr @proxy_v4 meta mark set 0x210'
assert_not_contains /tmp/lpr-nft-all.out "@clients_v4 ip daddr @proxy_v4"
assert_not_contains /tmp/lpr-nft-all.out "198.18.0.0/15 meta mark"

out="$(lpr_nft_render_table br-lan 0x210 allowlist fake-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-allow.out
assert_contains /tmp/lpr-nft-allow.out "set clients_v4"
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip saddr @clients_v4 ip daddr @proxy_v4 meta mark set 0x210'
assert_contains /tmp/lpr-nft-allow.out 'iifname "br-lan" ip saddr @clients_v4 ip daddr 198.18.0.0/15 meta mark set 0x210'

out="$(lpr_nft_render_table br-lan 0x210 blocklist mixed 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-nft-block.out
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip saddr @blocked_clients_v4 return'
assert_contains /tmp/lpr-nft-block.out 'iifname "br-lan" ip daddr @proxy_v4 meta mark set 0x210'

routes="$(lpr_nft_render_policy_route 0x210 210 10210 192.168.1.2 br-lan)"
printf '%s\n' "$routes" > /tmp/lpr-nft-routes.out
assert_contains /tmp/lpr-nft-routes.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-nft-routes.out "ip route replace default via 192.168.1.2 dev br-lan table 210"

cleanup="$(lpr_nft_render_cleanup 0x210 210 10210)"
printf '%s\n' "$cleanup" > /tmp/lpr-nft-cleanup.out
assert_contains /tmp/lpr-nft-cleanup.out "nft delete table inet lan_proxy_route"
assert_contains /tmp/lpr-nft-cleanup.out "ip rule del fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-nft-cleanup.out "ip route flush table 210"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `. ./root/usr/share/lan-proxy-route/backends/nft.sh: No such file`.

- [ ] **Step 3: Implement nft renderer**

Create `root/usr/share/lan-proxy-route/backends/nft.sh`:

```sh
#!/bin/sh

lpr_nft_client_prefix() {
	lan_if="$1"
	access_mode="$2"
	case "$access_mode" in
		all) printf 'iifname "%s"' "$lan_if" ;;
		allowlist) printf 'iifname "%s" ip saddr @clients_v4' "$lan_if" ;;
		blocklist) printf 'iifname "%s"' "$lan_if" ;;
		*) return 1 ;;
	esac
}

lpr_nft_render_table() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"
	dns_mode="$4"
	fake_cidr="$5"
	prefix="$(lpr_nft_client_prefix "$lan_if" "$access_mode")" || return 1

	cat <<EOF
table inet lan_proxy_route {
	set clients_v4 {
		type ipv4_addr
		flags interval
	}

	set blocked_clients_v4 {
		type ipv4_addr
		flags interval
	}

	set bypass_v4 {
		type ipv4_addr
		flags interval
	}

	set proxy_v4 {
		type ipv4_addr
		flags interval
	}

	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname "$lan_if" ip daddr @bypass_v4 return
EOF
	if [ "$access_mode" = "blocklist" ]; then
		cat <<EOF
		iifname "$lan_if" ip saddr @blocked_clients_v4 return
EOF
	fi
	cat <<EOF
		$prefix ip daddr @proxy_v4 meta mark set $mark
EOF
	case "$dns_mode" in
		fake-ip)
			cat <<EOF
		$prefix ip daddr $fake_cidr meta mark set $mark
EOF
			;;
	esac
	cat <<EOF
	}
}
EOF
}

lpr_nft_render_policy_route() {
	mark="$1"
	table="$2"
	priority="$3"
	x86_ip="$4"
	lan_if="$5"
	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace default via %s dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
}

lpr_nft_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"
	printf 'nft delete table inet lan_proxy_route\n'
	printf 'ip rule del fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route flush table %s\n' "$table"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with nft backend tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/lan-proxy-route/backends/nft.sh tests/unit/test_nft_backend.sh
git commit -m "feat: add nft backend renderer"
```

## Task 4: ipset Backend Renderer

**Files:**
- Create: `root/usr/share/lan-proxy-route/backends/ipset.sh`
- Create: `tests/unit/test_ipset_backend.sh`

**Interfaces:**
- Consumes validation helpers from `common.sh`.
- Produces `lpr_ipset_render_setup`.
- Produces `lpr_ipset_render_mangle LAN_IF MARK ACCESS_MODE DNS_MODE FAKE_CIDR`.
- Produces `lpr_ipset_render_policy_route MARK TABLE PRIORITY X86_IP LAN_IF`.
- Produces `lpr_ipset_render_cleanup MARK TABLE PRIORITY`.

- [ ] **Step 1: Write the failing ipset backend tests**

Create `tests/unit/test_ipset_backend.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$setup" > /tmp/lpr-ipset-setup.out
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_clients hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_bypass_v4 hash:net family inet -exist"
assert_contains /tmp/lpr-ipset-setup.out "ipset create lpr_proxy_v4 hash:net family inet -exist"

out="$(lpr_ipset_render_mangle br-lan 0x210 all real-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-all.out
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -N LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A PREROUTING -i br-lan -j LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN"
assert_contains /tmp/lpr-ipset-all.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_proxy_v4 dst -j MARK --set-mark 0x210"
assert_not_contains /tmp/lpr-ipset-all.out "lpr_clients src"

out="$(lpr_ipset_render_mangle br-lan 0x210 allowlist fake-ip 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-allow.out
assert_contains /tmp/lpr-ipset-allow.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_clients src -m set --match-set lpr_proxy_v4 dst -j MARK --set-mark 0x210"
assert_contains /tmp/lpr-ipset-allow.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_clients src -d 198.18.0.0/15 -j MARK --set-mark 0x210"

out="$(lpr_ipset_render_mangle br-lan 0x210 blocklist mixed 198.18.0.0/15)"
printf '%s\n' "$out" > /tmp/lpr-ipset-block.out
assert_contains /tmp/lpr-ipset-block.out "iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN"

cleanup="$(lpr_ipset_render_cleanup 0x210 210 10210)"
printf '%s\n' "$cleanup" > /tmp/lpr-ipset-cleanup.out
assert_contains /tmp/lpr-ipset-cleanup.out "iptables -t mangle -D PREROUTING -j LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-ipset-cleanup.out "ipset destroy lpr_proxy_v4"
assert_contains /tmp/lpr-ipset-cleanup.out "ip route flush table 210"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `. ./root/usr/share/lan-proxy-route/backends/ipset.sh: No such file`.

- [ ] **Step 3: Implement ipset renderer**

Create `root/usr/share/lan-proxy-route/backends/ipset.sh`:

```sh
#!/bin/sh

lpr_ipset_render_setup() {
	cat <<'EOF'
ipset create lpr_clients hash:net family inet -exist
ipset create lpr_blocked_clients hash:net family inet -exist
ipset create lpr_bypass_v4 hash:net family inet -exist
ipset create lpr_proxy_v4 hash:net family inet -exist
EOF
}

lpr_ipset_proxy_match() {
	access_mode="$1"
	case "$access_mode" in
		all) printf -- '-m set --match-set lpr_proxy_v4 dst' ;;
		allowlist) printf -- '-m set --match-set lpr_clients src -m set --match-set lpr_proxy_v4 dst' ;;
		blocklist) printf -- '-m set --match-set lpr_proxy_v4 dst' ;;
		*) return 1 ;;
	esac
}

lpr_ipset_fake_match() {
	access_mode="$1"
	fake_cidr="$2"
	case "$access_mode" in
		all) printf -- '-d %s' "$fake_cidr" ;;
		allowlist) printf -- '-m set --match-set lpr_clients src -d %s' "$fake_cidr" ;;
		blocklist) printf -- '-d %s' "$fake_cidr" ;;
		*) return 1 ;;
	esac
}

lpr_ipset_render_mangle() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"
	dns_mode="$4"
	fake_cidr="$5"
	proxy_match="$(lpr_ipset_proxy_match "$access_mode")" || return 1

	cat <<EOF
iptables -t mangle -N LAN_PROXY_ROUTE
iptables -t mangle -A PREROUTING -i $lan_if -j LAN_PROXY_ROUTE
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN
EOF
	if [ "$access_mode" = "blocklist" ]; then
		cat <<'EOF'
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN
EOF
	fi
	cat <<EOF
iptables -t mangle -A LAN_PROXY_ROUTE $proxy_match -j MARK --set-mark $mark
EOF
	if [ "$dns_mode" = "fake-ip" ]; then
		fake_match="$(lpr_ipset_fake_match "$access_mode" "$fake_cidr")" || return 1
		cat <<EOF
iptables -t mangle -A LAN_PROXY_ROUTE $fake_match -j MARK --set-mark $mark
EOF
	fi
}

lpr_ipset_render_policy_route() {
	mark="$1"
	table="$2"
	priority="$3"
	x86_ip="$4"
	lan_if="$5"
	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace default via %s dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
}

lpr_ipset_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"
	cat <<EOF
iptables -t mangle -D PREROUTING -j LAN_PROXY_ROUTE
iptables -t mangle -F LAN_PROXY_ROUTE
iptables -t mangle -X LAN_PROXY_ROUTE
ipset destroy lpr_clients
ipset destroy lpr_blocked_clients
ipset destroy lpr_bypass_v4
ipset destroy lpr_proxy_v4
ip rule del fwmark $mark lookup $table priority $priority
ip route flush table $table
EOF
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with ipset backend tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/lan-proxy-route/backends/ipset.sh tests/unit/test_ipset_backend.sh
git commit -m "feat: add ipset backend renderer"
```

## Task 5: dnsmasq Renderer and DNS Firewall Rules

**Files:**
- Create: `root/usr/share/lan-proxy-route/dnsmasq.sh`
- Create: `tests/unit/test_dnsmasq.sh`

**Interfaces:**
- Consumes validation helpers from `common.sh`.
- Produces `lpr_dns_domain_lines FILE ROLE BACKEND DNS_RESULT PROXY_DNS`.
- Produces `lpr_dnsmasq_render_config BACKEND DOMESTIC_DNS_CSV PROXY_DNS FILE...`.
- Produces `lpr_dns_render_firewall BACKEND LAN_IF ROUTER_IP HIJACK_53 BLOCK_DOT`.

- [ ] **Step 1: Write the failing dnsmasq tests**

Create `tests/unit/test_dnsmasq.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/dnsmasq.sh

tmp_domains="/tmp/lpr-domains.txt"
cat > "$tmp_domains" <<'EOF'
# comment
google.com
.youtube.com
bad domain.test
EOF

out="$(lpr_dns_domain_lines "$tmp_domains" proxy nftset real-ip 192.168.1.2#53)"
printf '%s\n' "$out" > /tmp/lpr-dns-nft.out
assert_contains /tmp/lpr-dns-nft.out "server=/google.com/192.168.1.2#53"
assert_contains /tmp/lpr-dns-nft.out "nftset=/google.com/4#inet#lan_proxy_route#proxy_v4"
assert_contains /tmp/lpr-dns-nft.out "server=/youtube.com/192.168.1.2#53"
assert_not_contains /tmp/lpr-dns-nft.out "bad domain.test"

out="$(lpr_dns_domain_lines "$tmp_domains" proxy ipset real-ip 192.168.1.2#53)"
printf '%s\n' "$out" > /tmp/lpr-dns-ipset.out
assert_contains /tmp/lpr-dns-ipset.out "ipset=/google.com/lpr_proxy_v4"

out="$(lpr_dns_domain_lines "$tmp_domains" adblock nftset real-ip 192.168.1.2#53)"
printf '%s\n' "$out" > /tmp/lpr-dns-adblock.out
assert_contains /tmp/lpr-dns-adblock.out "address=/google.com/0.0.0.0"
assert_not_contains /tmp/lpr-dns-adblock.out "server=/google.com/"

fw="$(lpr_dns_render_firewall nftset br-lan 192.168.1.1 1 1)"
printf '%s\n' "$fw" > /tmp/lpr-dns-fw.out
assert_contains /tmp/lpr-dns-fw.out "nft add rule inet lan_proxy_route dns_hijack iifname \"br-lan\" udp dport 53 redirect to :53"
assert_contains /tmp/lpr-dns-fw.out "nft add rule inet lan_proxy_route dns_hijack iifname \"br-lan\" tcp dport 853 reject"

fw="$(lpr_dns_render_firewall ipset br-lan 192.168.1.1 1 1)"
printf '%s\n' "$fw" > /tmp/lpr-dns-fw-ipset.out
assert_contains /tmp/lpr-dns-fw-ipset.out "iptables -t nat -A PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53"
assert_contains /tmp/lpr-dns-fw-ipset.out "iptables -A FORWARD -i br-lan -p tcp --dport 853 -j REJECT"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `. ./root/usr/share/lan-proxy-route/dnsmasq.sh: No such file`.

- [ ] **Step 3: Implement dnsmasq renderer**

Create `root/usr/share/lan-proxy-route/dnsmasq.sh`:

```sh
#!/bin/sh

lpr_clean_domain() {
	line="$1"
	line="${line%%#*}"
	line="$(printf '%s' "$line" | sed 's/^[	 ]*//; s/[	 ]*$//')"
	case "$line" in
		.*) line="${line#.}" ;;
	esac
	printf '%s\n' "$line"
}

lpr_dns_domain_lines() {
	file="$1"
	role="$2"
	backend="$3"
	dns_result="$4"
	proxy_dns="$5"
	[ -f "$file" ] || return 0

	while IFS= read -r raw || [ -n "$raw" ]; do
		domain="$(lpr_clean_domain "$raw")"
		lpr_is_domain "$domain" || continue
		case "$role" in
			adblock)
				printf 'address=/%s/0.0.0.0\n' "$domain"
				;;
			proxy)
				printf 'server=/%s/%s\n' "$domain" "$proxy_dns"
				case "$backend" in
					nftset) printf 'nftset=/%s/4#inet#lan_proxy_route#proxy_v4\n' "$domain" ;;
					ipset) printf 'ipset=/%s/lpr_proxy_v4\n' "$domain" ;;
				esac
				if [ "$dns_result" = "fake-ip" ]; then
					printf '# fake-ip domain %s is expected to be restored by the X86 proxy\n' "$domain"
				fi
				;;
			bypass)
				printf '# bypass-domain %s\n' "$domain"
				;;
		esac
	done < "$file"
}

lpr_dnsmasq_render_config() {
	backend="$1"
	domestic_dns_csv="$2"
	proxy_dns="$3"
	shift 3
	printf '# generated by lan-proxy-route\n'
	IFS=,
	for dns in $domestic_dns_csv; do
		[ -n "$dns" ] && printf 'server=%s\n' "$dns"
	done
	unset IFS
	for spec in "$@"; do
		file="${spec%%:*}"
		rest="${spec#*:}"
		role="${rest%%:*}"
		dns_result="${rest#*:}"
		lpr_dns_domain_lines "$file" "$role" "$backend" "$dns_result" "$proxy_dns"
	done
}

lpr_dns_render_firewall() {
	backend="$1"
	lan_if="$2"
	router_ip="$3"
	hijack_53="$4"
	block_dot="$5"
	[ "$hijack_53" = "1" ] || return 0
	case "$backend" in
		nftset)
			cat <<EOF
nft add chain inet lan_proxy_route dns_hijack '{ type nat hook prerouting priority dstnat; policy accept; }'
nft add rule inet lan_proxy_route dns_hijack iifname "$lan_if" udp dport 53 redirect to :53
nft add rule inet lan_proxy_route dns_hijack iifname "$lan_if" tcp dport 53 redirect to :53
EOF
			[ "$block_dot" = "1" ] && printf 'nft add rule inet lan_proxy_route dns_hijack iifname "%s" tcp dport 853 reject\n' "$lan_if"
			;;
		ipset)
			cat <<EOF
iptables -t nat -A PREROUTING -i $lan_if -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i $lan_if -p tcp --dport 53 -j REDIRECT --to-ports 53
EOF
			[ "$block_dot" = "1" ] && printf 'iptables -A FORWARD -i %s -p tcp --dport 853 -j REJECT\n' "$lan_if"
			;;
	esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with dnsmasq tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/lan-proxy-route/dnsmasq.sh tests/unit/test_dnsmasq.sh
git commit -m "feat: add dnsmasq renderer"
```

## Task 6: Main Service CLI and Init Script

**Files:**
- Create: `root/usr/share/lan-proxy-route/lan-proxy-route.sh`
- Create: `root/etc/init.d/lan-proxy-route`
- Create: `tests/unit/test_service_cli.sh`
- Modify: `tests/static/test_package_skeleton.sh`

**Interfaces:**
- Consumes `common.sh`, `dnsmasq.sh`, `backends/nft.sh`, and `backends/ipset.sh`.
- Produces CLI commands: `validate`, `render`, `apply`, `cleanup`, `diagnose`.
- Init script calls `/usr/share/lan-proxy-route/lan-proxy-route.sh apply`, `cleanup`, and `diagnose`.

- [ ] **Step 1: Write the failing service tests**

Create `tests/unit/test_service_cli.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh

svc=./root/usr/share/lan-proxy-route/lan-proxy-route.sh
init=./root/etc/init.d/lan-proxy-route

assert_file_exists "$svc"
assert_file_exists "$init"

sh -n "$svc"
sh -n "$init"

LPR_DRY_RUN=1 LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" render > /tmp/lpr-service-render.out
assert_contains /tmp/lpr-service-render.out "table inet lan_proxy_route"
assert_contains /tmp/lpr-service-render.out "ip rule add fwmark 0x210 lookup 210 priority 10210"
assert_contains /tmp/lpr-service-render.out "server=/google.com/192.168.1.2#53"

LPR_DRY_RUN=1 LPR_BACKEND=ipset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh "$svc" cleanup > /tmp/lpr-service-clean.out
assert_contains /tmp/lpr-service-clean.out "ipset destroy lpr_proxy_v4"

if LPR_BACKEND=nftset LPR_X86_IP=999.1.1.1 sh "$svc" validate >/tmp/lpr-invalid.out 2>&1; then
	fail "invalid X86 IP passed validation"
fi
assert_contains /tmp/lpr-invalid.out "invalid proxy IP"
```

Modify `tests/static/test_package_skeleton.sh` by appending:

```sh
assert_file_exists root/etc/init.d/lan-proxy-route
assert_file_exists root/usr/share/lan-proxy-route/lan-proxy-route.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `missing file: ./root/usr/share/lan-proxy-route/lan-proxy-route.sh`.

- [ ] **Step 3: Implement service CLI and init script**

Create `root/usr/share/lan-proxy-route/lan-proxy-route.sh`:

```sh
#!/bin/sh
set -eu

BASE_DIR="${LPR_BASE_DIR:-/usr/share/lan-proxy-route}"
if [ -f "./root/usr/share/lan-proxy-route/common.sh" ]; then
	BASE_DIR="./root/usr/share/lan-proxy-route"
fi

. "$BASE_DIR/common.sh"
. "$BASE_DIR/dnsmasq.sh"
. "$BASE_DIR/backends/nft.sh"
. "$BASE_DIR/backends/ipset.sh"

LPR_BACKEND="${LPR_BACKEND:-auto}"
LPR_DNS_MODE="${LPR_DNS_MODE:-real-ip}"
LPR_MARK="${LPR_MARK:-0x210}"
LPR_TABLE="${LPR_TABLE:-210}"
LPR_PRIORITY="${LPR_PRIORITY:-10210}"
LPR_LAN_IF="${LPR_LAN_IF:-br-lan}"
LPR_X86_IP="${LPR_X86_IP:-192.168.1.2}"
LPR_PROXY_DNS="${LPR_PROXY_DNS:-192.168.1.2#53}"
LPR_FAKE_CIDR="${LPR_FAKE_CIDR:-198.18.0.0/15}"
LPR_ACCESS_MODE="${LPR_ACCESS_MODE:-all}"
LPR_HIJACK_53="${LPR_HIJACK_53:-1}"
LPR_BLOCK_DOT="${LPR_BLOCK_DOT:-1}"
LPR_ETC_DIR="${LPR_ETC_DIR:-/etc/lan-proxy-route}"
if [ -d "./root/etc/lan-proxy-route" ]; then
	LPR_ETC_DIR="./root/etc/lan-proxy-route"
fi

lpr_service_validate() {
	lpr_is_ipv4 "$LPR_X86_IP" || lpr_die "invalid proxy IP: $LPR_X86_IP"
	lpr_is_mark "$LPR_MARK" || lpr_die "invalid mark: $LPR_MARK"
	lpr_is_uint "$LPR_TABLE" || lpr_die "invalid table: $LPR_TABLE"
	lpr_is_uint "$LPR_PRIORITY" || lpr_die "invalid priority: $LPR_PRIORITY"
	lpr_is_cidr "$LPR_FAKE_CIDR" || lpr_die "invalid fake IP CIDR: $LPR_FAKE_CIDR"
	case "$LPR_DNS_MODE" in real-ip|fake-ip|mixed) : ;; *) lpr_die "invalid DNS mode: $LPR_DNS_MODE" ;; esac
	case "$LPR_ACCESS_MODE" in all|allowlist|blocklist) : ;; *) lpr_die "invalid access mode: $LPR_ACCESS_MODE" ;; esac
	lpr_detect_backend "$LPR_BACKEND" >/dev/null || lpr_die "unable to detect backend"
}

lpr_service_render() {
	backend="$(lpr_detect_backend "$LPR_BACKEND")"
	case "$backend" in
		nftset)
			lpr_nft_render_table "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$LPR_DNS_MODE" "$LPR_FAKE_CIDR"
			lpr_nft_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
		ipset)
			lpr_ipset_render_setup
			lpr_ipset_render_mangle "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$LPR_DNS_MODE" "$LPR_FAKE_CIDR"
			lpr_ipset_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
	esac
	lpr_dnsmasq_render_config "$backend" "114.114.114.114,223.5.5.5" "$LPR_PROXY_DNS" \
		"$LPR_ETC_DIR/adblock.txt:adblock:real-ip" \
		"$LPR_ETC_DIR/gfwlist.txt:proxy:$LPR_DNS_MODE"
	lpr_dns_render_firewall "$backend" "$LPR_LAN_IF" "192.168.1.1" "$LPR_HIJACK_53" "$LPR_BLOCK_DOT"
}

lpr_service_apply() {
	lpr_service_validate
	lpr_service_render | while IFS= read -r line; do
		[ -n "$line" ] || continue
		case "$line" in \#*) continue ;; esac
		if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
			printf '%s\n' "$line"
		else
			sh -c "$line"
		fi
	done
}

lpr_service_cleanup() {
	backend="$(lpr_detect_backend "$LPR_BACKEND" 2>/dev/null || printf ipset)"
	case "$backend" in
		nftset) lpr_nft_render_cleanup "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" ;;
		ipset) lpr_ipset_render_cleanup "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" ;;
	esac
}

cmd="${1:-render}"
case "$cmd" in
	validate) lpr_service_validate ;;
	render) lpr_service_validate; lpr_service_render ;;
	apply) lpr_service_apply ;;
	cleanup|stop) lpr_service_cleanup ;;
	diagnose) printf '{"status":"diagnostics-not-wired"}\n' ;;
	*) lpr_die "usage: $0 validate|render|apply|cleanup|diagnose" ;;
esac
```

Create `root/etc/init.d/lan-proxy-route`:

```sh
#!/bin/sh /etc/rc.common

START=95
STOP=05
USE_PROCD=1

SERVICE=/usr/share/lan-proxy-route/lan-proxy-route.sh

start_service() {
	"$SERVICE" apply
}

reload_service() {
	"$SERVICE" cleanup
	"$SERVICE" apply
	/etc/init.d/dnsmasq reload >/dev/null 2>&1 || true
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
}

stop_service() {
	"$SERVICE" cleanup
}
```

Make both executable:

```bash
chmod +x root/usr/share/lan-proxy-route/lan-proxy-route.sh root/etc/init.d/lan-proxy-route
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with service CLI tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/lan-proxy-route/lan-proxy-route.sh root/etc/init.d/lan-proxy-route tests/static/test_package_skeleton.sh tests/unit/test_service_cli.sh
git commit -m "feat: add service orchestration"
```

## Task 7: Diagnostics and rpcd Bridge

**Files:**
- Create: `root/usr/share/lan-proxy-route/diagnostics.sh`
- Create: `root/usr/libexec/rpcd/lan-proxy-route`
- Create: `root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json`
- Create: `tests/unit/test_diagnostics.sh`
- Modify: `root/usr/share/lan-proxy-route/lan-proxy-route.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces `lpr_diag_json BACKEND X86_IP LAN_IF MARK TABLE PRIORITY`.
- rpcd exposes methods: `status`, `reload`, `test_route`.
- Service CLI `diagnose` sources `diagnostics.sh` and returns JSON.

- [ ] **Step 1: Write the failing diagnostics tests**

Create `tests/unit/test_diagnostics.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/diagnostics.sh

json="$(lpr_diag_json nftset 192.168.1.2 br-lan 0x210 210 10210)"
printf '%s\n' "$json" > /tmp/lpr-diag.json
assert_contains /tmp/lpr-diag.json '"backend":"nftset"'
assert_contains /tmp/lpr-diag.json '"x86_ip":"192.168.1.2"'
assert_contains /tmp/lpr-diag.json '"lan_if":"br-lan"'
assert_contains /tmp/lpr-diag.json '"mark":"0x210"'
assert_contains /tmp/lpr-diag.json '"table":"210"'
assert_contains /tmp/lpr-diag.json '"priority":"10210"'

rpc=./root/usr/libexec/rpcd/lan-proxy-route
assert_file_exists "$rpc"
sh -n "$rpc"

LPR_BACKEND=nftset LPR_X86_IP=192.168.1.2 LPR_LAN_IF=br-lan sh ./root/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose > /tmp/lpr-cli-diag.json
assert_contains /tmp/lpr-cli-diag.json '"backend":"nftset"'
assert_contains /tmp/lpr-cli-diag.json '"domain_set_available"'

assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"luci-app-lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"lan-proxy-route"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"status"'
assert_contains root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json '"reload"'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `. ./root/usr/share/lan-proxy-route/diagnostics.sh: No such file`.

- [ ] **Step 3: Implement diagnostics and rpcd files**

Create `root/usr/share/lan-proxy-route/diagnostics.sh`:

```sh
#!/bin/sh

lpr_json_bool_cmd() {
	if command -v "$1" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
}

lpr_diag_json() {
	backend="$1"
	x86_ip="$2"
	lan_if="$3"
	mark="$4"
	table="$5"
	priority="$6"
	nft_available="$(lpr_json_bool_cmd nft)"
	ipset_available="$(lpr_json_bool_cmd ipset)"
	dnsmasq_available="$(lpr_json_bool_cmd dnsmasq)"
	cat <<EOF
{
  "service":"lan-proxy-route",
  "backend":"$backend",
  "x86_ip":"$x86_ip",
  "lan_if":"$lan_if",
  "mark":"$mark",
  "table":"$table",
  "priority":"$priority",
  "nft_available":$nft_available,
  "ipset_available":$ipset_available,
  "dnsmasq_available":$dnsmasq_available,
  "domain_set_available":$dnsmasq_available
}
EOF
}
```

Modify `root/usr/share/lan-proxy-route/lan-proxy-route.sh` by adding:

```sh
. "$BASE_DIR/diagnostics.sh"
```

after backend imports, and replace the `diagnose)` case with:

```sh
	diagnose)
		backend="$(lpr_detect_backend "$LPR_BACKEND" 2>/dev/null || printf unknown)"
		lpr_diag_json "$backend" "$LPR_X86_IP" "$LPR_LAN_IF" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY"
		;;
```

Create `root/usr/libexec/rpcd/lan-proxy-route`:

```sh
#!/bin/sh

SERVICE=/usr/share/lan-proxy-route/lan-proxy-route.sh

case "${1:-list}" in
	list)
		cat <<'EOF'
{
  "status": {},
  "reload": {},
  "test_route": {
    "src": "String",
    "dst": "String"
  }
}
EOF
		;;
	call)
		method="$2"
		case "$method" in
			status) "$SERVICE" diagnose ;;
			reload) "$SERVICE" cleanup >/dev/null 2>&1; "$SERVICE" apply >/dev/null 2>&1; printf '{"ok":true}\n' ;;
			test_route) printf '{"ok":true,"matched":false,"reason":"test-route is rendered by diagnostics in first version"}\n' ;;
			*) printf '{"error":"unknown method"}\n'; exit 1 ;;
		esac
		;;
	*) printf '{"error":"usage"}\n'; exit 1 ;;
esac
```

Create `root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json`:

```json
{
  "luci-app-lan-proxy-route": {
    "description": "Grant access to LAN Proxy Route",
    "read": {
      "uci": [ "lan_proxy_route" ],
      "ubus": {
        "lan-proxy-route": [ "status", "test_route" ]
      }
    },
    "write": {
      "uci": [ "lan_proxy_route" ],
      "ubus": {
        "lan-proxy-route": [ "reload" ]
      }
    }
  }
}
```

Make rpcd executable:

```bash
chmod +x root/usr/libexec/rpcd/lan-proxy-route
```

Update `Makefile` dependencies to include rpcd:

```make
LUCI_DEPENDS:=+luci-base +rpcd +dnsmasq-full +ip-full
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with diagnostics tests.

- [ ] **Step 5: Commit**

```bash
git add Makefile root/usr/share/lan-proxy-route/diagnostics.sh root/usr/share/lan-proxy-route/lan-proxy-route.sh root/usr/libexec/rpcd/lan-proxy-route root/usr/share/rpcd/acl.d/luci-app-lan-proxy-route.json tests/unit/test_diagnostics.sh
git commit -m "feat: add diagnostics rpc bridge"
```

## Task 8: Modern LuCI JavaScript Views

**Files:**
- Create: `root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json`
- Create: `root/www/luci-static/resources/view/lan-proxy-route/overview.js`
- Create: `root/www/luci-static/resources/view/lan-proxy-route/settings.js`
- Create: `root/www/luci-static/resources/view/lan-proxy-route/dns.js`
- Create: `root/www/luci-static/resources/view/lan-proxy-route/clients.js`
- Create: `root/www/luci-static/resources/view/lan-proxy-route/rules.js`
- Create: `tests/static/test_luci_views.sh`

**Interfaces:**
- Consumes UCI package `lan_proxy_route`.
- Consumes rpcd executable via LuCI RPC declaration.
- Produces five modern LuCI tabs with no legacy CGI route.

- [ ] **Step 1: Write the failing LuCI static tests**

Create `tests/static/test_luci_views.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh

menu=root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json
assert_file_exists "$menu"
assert_contains "$menu" "admin/services/lan-proxy-route"
assert_contains "$menu" "view/lan-proxy-route/overview"
assert_contains "$menu" "view/lan-proxy-route/settings"
assert_contains "$menu" "view/lan-proxy-route/dns"
assert_contains "$menu" "view/lan-proxy-route/clients"
assert_contains "$menu" "view/lan-proxy-route/rules"

for view in overview settings dns clients rules; do
	file="root/www/luci-static/resources/view/lan-proxy-route/$view.js"
	assert_file_exists "$file"
	assert_contains "$file" "'view'"
	assert_contains "$file" "lan_proxy_route"
done

assert_contains root/www/luci-static/resources/view/lan-proxy-route/settings.js "'enabled'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/dns.js "'hijack_53'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/clients.js "'mode'"
assert_contains root/www/luci-static/resources/view/lan-proxy-route/rules.js "fake_ip_cidr"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
sh tests/run.sh
```

Expected: FAIL with `missing file: root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json`.

- [ ] **Step 3: Create menu and LuCI views**

Create `root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json`:

```json
{
  "admin/services/lan-proxy-route": {
    "title": "LAN Proxy Route",
    "order": 60,
    "action": {
      "type": "view",
      "path": "lan-proxy-route/overview"
    },
    "depends": {
      "acl": [ "luci-app-lan-proxy-route" ],
      "uci": { "lan_proxy_route": true }
    }
  },
  "admin/services/lan-proxy-route/overview": {
    "title": "Overview",
    "order": 10,
    "action": { "type": "view", "path": "lan-proxy-route/overview" }
  },
  "admin/services/lan-proxy-route/settings": {
    "title": "Basic Settings",
    "order": 20,
    "action": { "type": "view", "path": "lan-proxy-route/settings" }
  },
  "admin/services/lan-proxy-route/dns": {
    "title": "DNS and Filtering",
    "order": 30,
    "action": { "type": "view", "path": "lan-proxy-route/dns" }
  },
  "admin/services/lan-proxy-route/clients": {
    "title": "Client Control",
    "order": 40,
    "action": { "type": "view", "path": "lan-proxy-route/clients" }
  },
  "admin/services/lan-proxy-route/rules": {
    "title": "Rules and Diagnostics",
    "order": 50,
    "action": { "type": "view", "path": "lan-proxy-route/rules" }
  }
}
```

Create `root/www/luci-static/resources/view/lan-proxy-route/settings.js`:

```javascript
'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'global', 'global', _('Basic Settings'));

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';

		o = s.option(form.ListValue, 'backend', _('Backend'));
		o.value('auto', _('Automatic'));
		o.value('nftset', _('nftset'));
		o.value('ipset', _('ipset'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'dns_mode', _('DNS result mode'));
		o.value('real-ip', _('real-ip'));
		o.value('fake-ip', _('fake-ip'));
		o.value('mixed', _('mixed'));
		o.default = 'real-ip';

		s.option(form.Value, 'lan_if', _('LAN interface')).default = 'br-lan';
		s.option(form.Value, 'mark', _('Firewall mark')).default = '0x210';
		s.option(form.Value, 'table', _('Route table')).datatype = 'uinteger';
		s.option(form.Value, 'priority', _('Rule priority')).datatype = 'uinteger';
		s.option(form.Value, 'fake_ip_cidr', _('Fake IP CIDR')).datatype = 'cidr4';

		s = m.section(form.NamedSection, 'x86', 'proxy_node', _('X86 Proxy Host'));
		s.option(form.Value, 'ip', _('Proxy host IP')).datatype = 'ip4addr';
		s.option(form.Value, 'dns_port', _('Proxy DNS port')).datatype = 'port';
		s.option(form.Value, 'mode', _('Proxy mode')).default = 'dae';

		return m.render();
	}
});
```

Create `root/www/luci-static/resources/view/lan-proxy-route/dns.js`:

```javascript
'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'dns', 'dns', _('DNS and Filtering'));

		o = s.option(form.Flag, 'hijack_53', _('Force LAN DNS 53 to OpenWrt'));
		o.default = '1';

		o = s.option(form.Flag, 'block_dot', _('Block DoT TCP/853'));
		o.default = '1';

		o = s.option(form.DynamicList, 'domestic_dns', _('Domestic DNS servers'));
		o.datatype = 'hostport';

		o = s.option(form.DynamicList, 'proxy_dns', _('Proxy DNS servers'));
		o.datatype = 'hostport';

		s = m.section(form.GridSection, 'list', _('Domain Lists'));
		s.addremove = true;
		s.anonymous = false;
		s.option(form.Flag, 'enabled', _('Enabled'));
		o = s.option(form.ListValue, 'role', _('Role'));
		o.value('proxy', _('Proxy'));
		o.value('adblock', _('Ad block'));
		o.value('bypass', _('Bypass'));
		o = s.option(form.ListValue, 'dns_result', _('DNS result'));
		o.value('real-ip', _('real-ip'));
		o.value('fake-ip', _('fake-ip'));
		s.option(form.Value, 'source', _('Source file'));
		o = s.option(form.ListValue, 'dns_upstream', _('DNS upstream'));
		o.value('domestic', _('Domestic'));
		o.value('proxy', _('Proxy'));

		return m.render();
	}
});
```

Create `root/www/luci-static/resources/view/lan-proxy-route/clients.js`:

```javascript
'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'access', 'access', _('Client Control'));

		o = s.option(form.ListValue, 'mode', _('Access mode'));
		o.value('all', _('All LAN clients'));
		o.value('allowlist', _('Only listed clients'));
		o.value('blocklist', _('All except blocked clients'));
		o.default = 'all';

		o = s.option(form.DynamicList, 'allow_ip', _('Allowed IP addresses'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'allow_cidr', _('Allowed CIDR ranges'));
		o.datatype = 'cidr4';

		o = s.option(form.DynamicList, 'block_ip', _('Blocked IP addresses'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'block_cidr', _('Blocked CIDR ranges'));
		o.datatype = 'cidr4';

		return m.render();
	}
});
```

Create `root/www/luci-static/resources/view/lan-proxy-route/rules.js`:

```javascript
'use strict';
'require view';
'require form';
'require fs';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'global', 'global', _('Route Rules'));
		o = s.option(form.Value, 'fake_ip_cidr', _('Fake IP CIDR'));
		o.datatype = 'cidr4';

		s = m.section(form.NamedSection, 'bypass', 'bypass', _('Bypass Destinations'));
		o = s.option(form.DynamicList, 'cidr', _('Bypass CIDR'));
		o.datatype = 'cidr4';
		o = s.option(form.DynamicList, 'host', _('Bypass host IP'));
		o.datatype = 'ip4addr';

		return m.render();
	}
});
```

Create `root/www/luci-static/resources/view/lan-proxy-route/overview.js`:

```javascript
'use strict';
'require view';
'require rpc';
'require uci';

var callStatus = rpc.declare({
	object: 'lan-proxy-route',
	method: 'status',
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lan_proxy_route'),
			callStatus()
		]);
	},

	render: function(data) {
		var status = JSON.stringify(data[1] || {}, null, 2);
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LAN Proxy Route')),
			E('pre', {}, status)
		]);
	}
});
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
sh tests/run.sh
```

Expected: PASS with LuCI static tests.

- [ ] **Step 5: Commit**

```bash
git add root/usr/share/luci/menu.d/luci-app-lan-proxy-route.json root/www/luci-static/resources/view/lan-proxy-route tests/static/test_luci_views.sh
git commit -m "feat: add luci views"
```

## Task 9: Final Verification, Idempotency Checks, and Documentation

**Files:**
- Create: `tests/static/test_shell_syntax.sh`
- Create: `tests/unit/test_idempotency_contract.sh`
- Modify: `README.md`
- Modify: `root/usr/share/lan-proxy-route/backends/nft.sh`
- Modify: `root/usr/share/lan-proxy-route/backends/ipset.sh`

**Interfaces:**
- Produces final local verification command: `sh tests/run.sh`.
- Ensures renderer output uses idempotent commands where available.
- Documents OpenWrt and QSDK runtime verification commands.

- [ ] **Step 1: Write final static and idempotency tests**

Create `tests/static/test_shell_syntax.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh

for file in \
	root/etc/init.d/lan-proxy-route \
	root/usr/share/lan-proxy-route/common.sh \
	root/usr/share/lan-proxy-route/lan-proxy-route.sh \
	root/usr/share/lan-proxy-route/dnsmasq.sh \
	root/usr/share/lan-proxy-route/diagnostics.sh \
	root/usr/share/lan-proxy-route/backends/nft.sh \
	root/usr/share/lan-proxy-route/backends/ipset.sh \
	root/usr/libexec/rpcd/lan-proxy-route
do
	assert_file_exists "$file"
	sh -n "$file"
done
```

Create `tests/unit/test_idempotency_contract.sh`:

```sh
#!/bin/sh
set -eu

. ./tests/lib/assert.sh
. ./root/usr/share/lan-proxy-route/common.sh
. ./root/usr/share/lan-proxy-route/backends/nft.sh
. ./root/usr/share/lan-proxy-route/backends/ipset.sh

nft_cleanup="$(lpr_nft_render_cleanup 0x210 210 10210)"
printf '%s\n' "$nft_cleanup" > /tmp/lpr-final-nft-cleanup.out
assert_contains /tmp/lpr-final-nft-cleanup.out "nft delete table inet lan_proxy_route"
assert_contains /tmp/lpr-final-nft-cleanup.out "ip route flush table 210"

ipset_setup="$(lpr_ipset_render_setup)"
printf '%s\n' "$ipset_setup" > /tmp/lpr-final-ipset-setup.out
assert_contains /tmp/lpr-final-ipset-setup.out "-exist"

ipset_cleanup="$(lpr_ipset_render_cleanup 0x210 210 10210)"
printf '%s\n' "$ipset_cleanup" > /tmp/lpr-final-ipset-cleanup.out
assert_contains /tmp/lpr-final-ipset-cleanup.out "iptables -t mangle -F LAN_PROXY_ROUTE"
assert_contains /tmp/lpr-final-ipset-cleanup.out "ipset destroy lpr_clients"
```

- [ ] **Step 2: Run tests to verify failures or current gaps**

Run:

```bash
sh tests/run.sh
```

Expected: PASS if previous tasks already satisfy syntax and idempotency contracts; otherwise FAIL naming the exact command string to fix.

- [ ] **Step 3: Update cleanup renderers only if tests expose non-idempotent strings**

If `test_idempotency_contract.sh` fails because cleanup commands are too brittle, update the renderers to emit guarded shell commands:

```sh
nft list table inet lan_proxy_route >/dev/null 2>&1 && nft delete table inet lan_proxy_route
ip rule del fwmark "$mark" lookup "$table" priority "$priority" 2>/dev/null || true
ip route flush table "$table" 2>/dev/null || true
```

and for ipset:

```sh
iptables -t mangle -D PREROUTING -j LAN_PROXY_ROUTE 2>/dev/null || true
iptables -t mangle -F LAN_PROXY_ROUTE 2>/dev/null || true
iptables -t mangle -X LAN_PROXY_ROUTE 2>/dev/null || true
ipset destroy lpr_clients 2>/dev/null || true
ipset destroy lpr_blocked_clients 2>/dev/null || true
ipset destroy lpr_bypass_v4 2>/dev/null || true
ipset destroy lpr_proxy_v4 2>/dev/null || true
ip rule del fwmark "$mark" lookup "$table" priority "$priority" 2>/dev/null || true
ip route flush table "$table" 2>/dev/null || true
```

- [ ] **Step 4: Update README with runtime verification**

Append to `README.md`:

````markdown
## Runtime Verification

On OpenWrt 25.12 with nftset:

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
nft list table inet lan_proxy_route
ip rule show
ip route show table 210
```

On QSDK12.5/QWRT with ipset:

```sh
/etc/init.d/lan-proxy-route restart
/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose
ipset list lpr_proxy_v4
iptables -t mangle -S LAN_PROXY_ROUTE
ip rule show
ip route show table 210
```

DNS checks:

```sh
nslookup google.com 192.168.1.1
nslookup doubleclick.net 192.168.1.1
```

Traffic checks:

```sh
ip route get 8.8.8.8 mark 0x210
```
````

- [ ] **Step 5: Run full verification and commit**

Run:

```bash
sh tests/run.sh
git status --short
```

Expected: PASS for all tests. `git status --short` should show only files changed by Task 9 before committing.

Commit:

```bash
git add README.md root/usr/share/lan-proxy-route/backends tests/static/test_shell_syntax.sh tests/unit/test_idempotency_contract.sh
git commit -m "test: add final verification checks"
```

## Self-Review

- Spec coverage: package skeleton, default config, nftset backend, ipset backend, dnsmasq generation, DNS 53 hijack, DoT blocking, source client access policy, fake-ip/real-ip/mixed modes, diagnostics, modern LuCI views, and final verification are all mapped to tasks.
- The plan keeps one X86 node and does not add multi-node or multi-WAN policy logic.
- The plan keeps IPv4 as the first implemented data path.
- The plan avoids legacy CGI LuCI routing and uses modern menu/view files.
- The generated code paths are testable locally without an OpenWrt SDK because renderers produce command text in dry-run mode.
- Runtime OpenWrt and QSDK verification commands are documented in the final task.
