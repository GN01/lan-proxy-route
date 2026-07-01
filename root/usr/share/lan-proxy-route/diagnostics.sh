#!/bin/sh

lpr_json_bool_cmd() {
	if command -v "$1" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
}

lpr_diag_domain_set_available() {
	backend="$1"
	backend_error="${2:-}"
	dnsmasq_available="$3"

	case "$backend" in
		nftset|ipset)
			if [ -z "$backend_error" ] && [ "$dnsmasq_available" = true ]; then
				printf true
			else
				printf false
			fi
			;;
		*)
			printf false
			;;
	esac
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
	domain_set_available="$(lpr_diag_domain_set_available "$backend" "$backend_error" "$dnsmasq_available")"
	printf '%s\n' '{'
	printf '  "service":"lan-proxy-route",\n'
	printf '  "backend":"%s",\n' "$backend"
	printf '  "x86_ip":"%s",\n' "$x86_ip"
	printf '  "lan_if":"%s",\n' "$lan_if"
	printf '  "mark":"%s",\n' "$mark"
	printf '  "table":"%s",\n' "$table"
	printf '  "priority":"%s",\n' "$priority"
	printf '  "nft_available":%s,\n' "$nft_available"
	printf '  "ipset_available":%s,\n' "$ipset_available"
	printf '  "dnsmasq_available":%s,\n' "$dnsmasq_available"
	printf '  "domain_set_available":%s\n' "$domain_set_available"
	if [ -n "$backend_error" ]; then
		printf '  ,"backend_error":"%s"\n' "$backend_error"
	fi
	printf '%s\n' '}'
}
