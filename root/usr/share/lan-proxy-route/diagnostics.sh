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

lpr_diag_bool() {
	if "$@" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
}

lpr_diag_file_present() {
	if [ -s "$1" ]; then
		printf true
	else
		printf false
	fi
}

lpr_diag_policy_rule_present() {
	mark="$1"
	table="$2"
	priority="$3"
	if ! command -v ip >/dev/null 2>&1; then
		printf false
		return 0
	fi
	if ip rule show 2>/dev/null | grep -F "lookup $table" | grep -F "priority $priority" >/dev/null 2>&1; then
		printf true
	elif ip rule show 2>/dev/null | grep -F "fwmark $mark" | grep -F "lookup $table" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
}

lpr_diag_policy_route_present() {
	table="$1"
	x86_ip="$2"
	lan_if="$3"
	if command -v ip >/dev/null 2>&1 && \
		ip route show table "$table" 2>/dev/null | grep -F "default via $x86_ip dev $lan_if" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
}

lpr_diag_backend_table_present() {
	backend="$1"
	case "$backend" in
		nftset)
			if command -v nft >/dev/null 2>&1 && nft list table inet "$LPR_TABLE_NAME" >/dev/null 2>&1; then
				printf true
			else
				printf false
			fi
			;;
		ipset)
			if command -v ipset >/dev/null 2>&1 && ipset list -n lpr_proxy_v4 >/dev/null 2>&1; then
				printf true
			else
				printf false
			fi
			;;
		*) printf false ;;
	esac
}

lpr_diag_set_present() {
	backend="$1"
	set_name="$2"
	case "$backend" in
		nftset)
			if command -v nft >/dev/null 2>&1 && nft list set inet "$LPR_TABLE_NAME" "$set_name" >/dev/null 2>&1; then
				printf true
			else
				printf false
			fi
			;;
		ipset)
			if command -v ipset >/dev/null 2>&1 && ipset list -n "$set_name" >/dev/null 2>&1; then
				printf true
			else
				printf false
			fi
			;;
		*) printf false ;;
	esac
}

lpr_diag_chain_present() {
	backend="$1"
	chain="$2"
	case "$backend" in
		nftset)
			if command -v nft >/dev/null 2>&1 && nft list chain inet "$LPR_TABLE_NAME" "$chain" >/dev/null 2>&1; then
				printf true
			else
				printf false
			fi
			;;
		ipset)
			case "$chain" in
				dns_hijack)
					if command -v iptables >/dev/null 2>&1 && iptables -t nat -S PREROUTING 2>/dev/null | grep -F -- "--dport 53" >/dev/null 2>&1; then
						printf true
					else
						printf false
					fi
					;;
				dns_dot_block)
					if command -v iptables >/dev/null 2>&1 && iptables -S FORWARD 2>/dev/null | grep -F -- "--dport 853" >/dev/null 2>&1; then
						printf true
					else
						printf false
					fi
					;;
			esac
			;;
		*) printf false ;;
	esac
}

lpr_diag_x86_reachable() {
	x86_ip="$1"
	if command -v ping >/dev/null 2>&1; then
		if ping -c 1 -W 1 "$x86_ip" >/dev/null 2>&1; then
			printf '"reachable"'
		else
			printf '"unreachable"'
		fi
	else
		printf '"unavailable"'
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
	dnsmasq_conf="${8:-/tmp/dnsmasq.d/lan-proxy-route.conf}"
	enabled="${9:-1}"
	nft_available="$(lpr_json_bool_cmd nft)"
	ipset_available="$(lpr_json_bool_cmd ipset)"
	dnsmasq_available="$(lpr_json_bool_cmd dnsmasq)"
	domain_set_available="$(lpr_diag_domain_set_available "$backend" "$backend_error" "$dnsmasq_available")"
	dnsmasq_config_present="$(lpr_diag_file_present "$dnsmasq_conf")"
	backend_table_present="$(lpr_diag_backend_table_present "$backend")"
	case "$backend" in
		nftset)
			proxy_set_present="$(lpr_diag_set_present "$backend" proxy_v4)"
			clients_set_present="$(lpr_diag_set_present "$backend" clients_v4)"
			blocked_clients_set_present="$(lpr_diag_set_present "$backend" blocked_clients_v4)"
			bypass_set_present="$(lpr_diag_set_present "$backend" bypass_v4)"
			;;
		ipset)
			proxy_set_present="$(lpr_diag_set_present "$backend" lpr_proxy_v4)"
			clients_set_present="$(lpr_diag_set_present "$backend" lpr_clients)"
			blocked_clients_set_present="$(lpr_diag_set_present "$backend" lpr_blocked_clients)"
			bypass_set_present="$(lpr_diag_set_present "$backend" lpr_bypass_v4)"
			;;
		*)
			proxy_set_present=false
			clients_set_present=false
			blocked_clients_set_present=false
			bypass_set_present=false
			;;
	esac
	policy_rule_present="$(lpr_diag_policy_rule_present "$mark" "$table" "$priority")"
	policy_route_present="$(lpr_diag_policy_route_present "$table" "$x86_ip" "$lan_if")"
	dns_hijack_present="$(lpr_diag_chain_present "$backend" dns_hijack)"
	dot_block_present="$(lpr_diag_chain_present "$backend" dns_dot_block)"
	x86_reachable="$(lpr_diag_x86_reachable "$x86_ip")"
	running=false
	if [ "$enabled" = "1" ] && [ "$backend_table_present" = true ] && \
		[ "$policy_rule_present" = true ] && [ "$policy_route_present" = true ] && \
		[ -z "$backend_error" ]; then
		running=true
	fi
	if [ "$enabled" = "1" ]; then
		enabled_json=true
	else
		enabled_json=false
	fi
	printf '%s\n' '{'
	printf '  "service":"lan-proxy-route",\n'
	printf '  "enabled":%s,\n' "$enabled_json"
	printf '  "running":%s,\n' "$running"
	printf '  "backend":"%s",\n' "$backend"
	printf '  "x86_ip":"%s",\n' "$x86_ip"
	printf '  "lan_if":"%s",\n' "$lan_if"
	printf '  "mark":"%s",\n' "$mark"
	printf '  "table":"%s",\n' "$table"
	printf '  "priority":"%s",\n' "$priority"
	printf '  "nft_available":%s,\n' "$nft_available"
	printf '  "ipset_available":%s,\n' "$ipset_available"
	printf '  "dnsmasq_available":%s,\n' "$dnsmasq_available"
	printf '  "domain_set_available":%s,\n' "$domain_set_available"
	printf '  "dnsmasq_config_present":%s,\n' "$dnsmasq_config_present"
	printf '  "backend_table_present":%s,\n' "$backend_table_present"
	printf '  "proxy_set_present":%s,\n' "$proxy_set_present"
	printf '  "clients_set_present":%s,\n' "$clients_set_present"
	printf '  "blocked_clients_set_present":%s,\n' "$blocked_clients_set_present"
	printf '  "bypass_set_present":%s,\n' "$bypass_set_present"
	printf '  "proxy_set_entries":"unknown",\n'
	printf '  "clients_set_entries":"unknown",\n'
	printf '  "blocked_clients_set_entries":"unknown",\n'
	printf '  "bypass_set_entries":"unknown",\n'
	printf '  "policy_rule_present":%s,\n' "$policy_rule_present"
	printf '  "policy_route_present":%s,\n' "$policy_route_present"
	printf '  "dns_hijack_present":%s,\n' "$dns_hijack_present"
	printf '  "dot_block_present":%s,\n' "$dot_block_present"
	printf '  "x86_reachable":%s' "$x86_reachable"
	if [ -n "$backend_error" ]; then
		printf ',\n  "backend_error":"%s"\n' "$backend_error"
	else
		printf '\n'
	fi
	printf '%s\n' '}'
}
