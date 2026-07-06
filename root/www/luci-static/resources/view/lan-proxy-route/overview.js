'use strict';
'require view';
'require rpc';
'require uci';
'require dom';

var callStatus = rpc.declare({
	object: 'lan-proxy-route',
	method: 'status',
	expect: {}
});

var callLogs = rpc.declare({
	object: 'lan-proxy-route',
	method: 'logs',
	expect: { log: '' }
});

function statusLabel(ok, yesText, noText) {
	var cls = ok ? 'success' : 'warning';
	return E('span', { 'class': 'label ' + cls }, _(ok ? yesText : noText));
}

function boolRow(label, value) {
	var ok = value === true;
	return E('tr', {}, [
		E('td', { 'width': '33%' }, label),
		E('td', {}, statusLabel(ok, _('Yes'), _('No')))
	]);
}

function textRow(label, value) {
	return E('tr', {}, [
		E('td', { 'width': '33%' }, label),
		E('td', {}, value != null && value !== '' ? String(value) : E('em', {}, _('Unknown')))
	]);
}

function renderServiceStatus(enabled, running, st) {
	if (enabled === false || enabled === 0 || enabled === '0')
		return E('div', { 'class': 'alert-message warning' }, _('Disabled'));

	if (running === true)
		return E('div', { 'class': 'alert-message success' }, _('Running'));

	if (st && st.backend_error)
		return E('div', { 'class': 'alert-message error' },
			_('Stopped') + ': ' + st.backend_error);

	return E('div', { 'class': 'alert-message warning' }, _('Stopped'));
}

function renderStatusTable(st) {
	var rows = [
		textRow(_('Active backend'), st.backend),
		textRow(_('Proxy host'), st.x86_ip),
		textRow(_('LAN interface'), st.lan_if),
		textRow(_('Reachability'), _(st.x86_reachable || 'unknown')),
		boolRow(_('Backend table'), st.backend_table_present),
		boolRow(_('Policy rule'), st.policy_rule_present),
		boolRow(_('Policy route'), st.policy_route_present),
		boolRow(_('DNS hijack'), st.dns_hijack_present),
		boolRow(_('DoT block'), st.dot_block_present),
		boolRow(_('dnsmasq config'), st.dnsmasq_config_present),
		boolRow(_('Domain set support'), st.domain_set_available)
	];

	if (st.backend_error)
		rows.push(textRow(_('Backend error'), st.backend_error));

	return E('table', { 'class': 'table' }, rows);
}

function renderCommands() {
	var cmds = [
		[_('Validate configuration'), '/usr/share/lan-proxy-route/lan-proxy-route.sh validate'],
		[_('Preview commands without applying'), 'LPR_DRY_RUN=1 /usr/share/lan-proxy-route/lan-proxy-route.sh render'],
		[_('Apply with verbose logging (stop on first error)'), 'LPR_VERBOSE=1 /usr/share/lan-proxy-route/lan-proxy-route.sh apply'],
		[_('Run diagnostics'), '/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose'],
		[_('View syslog'), 'logread -e lan-proxy-route | tail -n 80'],
		[_('Restart service'), '/etc/init.d/lan-proxy-route restart']
	];

	return E('div', {}, cmds.map(function(item) {
		return E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, item[0]),
			E('div', { 'class': 'cbi-value-field' },
				E('pre', { 'style': 'white-space:pre-wrap;margin:0;' }, item[1]))
		]);
	}));
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lan_proxy_route'),
			callStatus().catch(function() { return { error: true }; }),
			callLogs().catch(function() { return { log: '' }; })
		]);
	},

	render: function(data) {
		var cfgEnabled = uci.get('lan_proxy_route', 'global', 'enabled') === '1';
		var st = data[1] || {};
		var logs = (data[2] && data[2].log) ? data[2].log : '';

		if (st.error)
			st = {};

		var body = [
			E('h3', {}, _('Service Status')),
			renderServiceStatus(cfgEnabled, st.running, st)
		];

		if (!st.error && st.backend)
			body.push(renderStatusTable(st));

		body.push(E('h3', {}, _('Recent Logs')));
		body.push(E('pre', {
			'style': 'max-height:240px;overflow:auto;white-space:pre-wrap;'
		}, logs || _('No log entries yet. Run the service or use verbose apply to populate syslog.')));

		body.push(E('h3', {}, _('Debug Commands')));
		body.push(renderCommands());

		body.push(E('h3', {}, _('Raw diagnostics JSON')));
		body.push(E('pre', {}, JSON.stringify(st, null, 2)));

		var map = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LAN Proxy Route')),
			E('div', { 'class': 'cbi-section' }, body)
		]);

		return map;
	}
});
