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
	backend_error="${7:-}"
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
  "domain_set_available":$dnsmasq_available$(if [ -n "$backend_error" ]; then
	cat <<ERR
,
  "backend_error":"$backend_error"
ERR
fi)
}
EOF
}
