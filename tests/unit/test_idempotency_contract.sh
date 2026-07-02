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
