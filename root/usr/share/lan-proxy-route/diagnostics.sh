#!/bin/sh

lpr_json_bool_cmd() {
	if command -v "$1" >/dev/null 2>&1; then
		printf true
	else
		printf false
	fi
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
			if command -v ipset >/dev/null 2>&1 && ipset list -n lpr_china_v4 >/dev/null 2>&1; then
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

lpr_diag_china_list_version() {
	ver_file="${LPR_CHINA_VER_FILE:-/etc/lan-proxy-route/china_ip4.ver}"
	if [ -s "$ver_file" ]; then
		head -n 1 "$ver_file" | tr -cd '0-9'
	else
		printf 'unknown'
	fi
}

lpr_diag_china_list_entries() {
	list_file="${LPR_CHINA_FILE:-/etc/lan-proxy-route/china_ip4.txt}"
	if [ -s "$list_file" ]; then
		count="$(grep -v '^#' "$list_file" 2>/dev/null | grep -c -v '^[[:space:]]*$' || true)"
		printf '%s' "${count:-0}"
	else
		printf 0
	fi
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
	enabled="${8:-1}"
	nft_available="$(lpr_json_bool_cmd nft)"
	ipset_available="$(lpr_json_bool_cmd ipset)"
	backend_table_present="$(lpr_diag_backend_table_present "$backend")"
	case "$backend" in
		nftset)
			china_set_present="$(lpr_diag_set_present "$backend" china_v4)"
			clients_set_present="$(lpr_diag_set_present "$backend" clients_v4)"
			blocked_clients_set_present="$(lpr_diag_set_present "$backend" blocked_clients_v4)"
			bypass_set_present="$(lpr_diag_set_present "$backend" bypass_v4)"
			;;
		ipset)
			china_set_present="$(lpr_diag_set_present "$backend" lpr_china_v4)"
			clients_set_present="$(lpr_diag_set_present "$backend" lpr_clients)"
			blocked_clients_set_present="$(lpr_diag_set_present "$backend" lpr_blocked_clients)"
			bypass_set_present="$(lpr_diag_set_present "$backend" lpr_bypass_v4)"
			;;
		*)
			china_set_present=false
			clients_set_present=false
			blocked_clients_set_present=false
			bypass_set_present=false
			;;
	esac
	china_list_version="$(lpr_diag_china_list_version)"
	china_list_entries="$(lpr_diag_china_list_entries)"
	policy_rule_present="$(lpr_diag_policy_rule_present "$mark" "$table" "$priority")"
	policy_route_present="$(lpr_diag_policy_route_present "$table" "$x86_ip" "$lan_if")"
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
	printf '  "backend_table_present":%s,\n' "$backend_table_present"
	printf '  "china_set_present":%s,\n' "$china_set_present"
	printf '  "china_list_version":"%s",\n' "$china_list_version"
	printf '  "china_list_entries":%s,\n' "$china_list_entries"
	printf '  "clients_set_present":%s,\n' "$clients_set_present"
	printf '  "blocked_clients_set_present":%s,\n' "$blocked_clients_set_present"
	printf '  "bypass_set_present":%s,\n' "$bypass_set_present"
	printf '  "policy_rule_present":%s,\n' "$policy_rule_present"
	printf '  "policy_route_present":%s,\n' "$policy_route_present"
	printf '  "x86_reachable":%s' "$x86_reachable"
	if [ -n "$backend_error" ]; then
		printf ',\n  "backend_error":"%s"\n' "$backend_error"
	else
		printf '\n'
	fi
	printf '%s\n' '}'
}
