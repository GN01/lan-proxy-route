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

var callUpdateChnroute = rpc.declare({
	object: 'lan-proxy-route',
	method: 'update_chnroute',
	expect: {}
});

var REACH_LABELS = {
	reachable: _('可达'),
	unreachable: _('不可达'),
	unavailable: _('不可用'),
	unknown: _('未知')
};

function statusLabel(ok, yesText, noText) {
	var cls = ok ? 'success' : 'warning';
	return E('span', { 'class': 'label ' + cls }, ok ? yesText : noText);
}

function boolRow(label, value) {
	var ok = value === true;
	return E('tr', {}, [
		E('td', { 'width': '33%' }, label),
		E('td', {}, statusLabel(ok, _('是'), _('否')))
	]);
}

function textRow(label, value) {
	return E('tr', {}, [
		E('td', { 'width': '33%' }, label),
		E('td', {}, value != null && value !== '' ? String(value) : E('em', {}, _('未知')))
	]);
}

function renderServiceStatus(enabled, running, st) {
	if (enabled === false || enabled === 0 || enabled === '0')
		return E('div', { 'class': 'alert-message warning' }, _('已禁用'));

	if (running === true)
		return E('div', { 'class': 'alert-message success' }, _('运行中'));

	if (st && st.backend_error)
		return E('div', { 'class': 'alert-message error' },
			_('已停止') + '：' + st.backend_error);

	return E('div', { 'class': 'alert-message warning' }, _('已停止'));
}

function renderStatusTable(st) {
	var reach = REACH_LABELS[st.x86_reachable] || REACH_LABELS.unknown;
	var rows = [
		textRow(_('当前后端'), st.backend),
		textRow(_('代理主机'), st.x86_ip),
		textRow(_('LAN 接口'), st.lan_if),
		textRow(_('连通性'), reach),
		boolRow(_('后端规则表'), st.backend_table_present),
		boolRow(_('策略路由规则'), st.policy_rule_present),
		boolRow(_('策略路由'), st.policy_route_present),
		boolRow(_('国内 IP 集合'), st.china_set_present),
		textRow(_('国内 IP 库版本'), st.china_list_version),
		textRow(_('国内 IP 库条目数'), st.china_list_entries)
	];

	if (st.backend_error)
		rows.push(textRow(_('后端错误'), st.backend_error));

	return E('table', { 'class': 'table' }, rows);
}

function renderChnrouteUpdate() {
	var resultBox = E('pre', {
		'style': 'white-space:pre-wrap;margin-top:0.5em;display:none;'
	}, '');

	var btn = E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function(ev) {
			var button = ev.target;
			button.disabled = true;
			button.textContent = _('更新中…');
			resultBox.style.display = 'none';
			callUpdateChnroute().then(function(res) {
				resultBox.textContent = res.ok
					? (res.message || _('更新完成'))
					: (_('更新失败') + '：' + (res.error || _('未知错误')));
				resultBox.style.display = 'block';
			}).catch(function(err) {
				resultBox.textContent = _('更新失败') + '：' + err;
				resultBox.style.display = 'block';
			}).finally(function() {
				button.disabled = false;
				button.textContent = _('更新国内 IP 库');
			});
		}
	}, _('更新国内 IP 库'));

	return E('div', {}, [ btn, resultBox ]);
}

function renderCommands() {
	var cmds = [
		[_('校验配置'), '/usr/share/lan-proxy-route/lan-proxy-route.sh validate'],
		[_('预览命令（不执行）'), 'LPR_DRY_RUN=1 /usr/share/lan-proxy-route/lan-proxy-route.sh render'],
		[_('详细启动（记录日志，遇错即停）'), 'LPR_VERBOSE=1 /usr/share/lan-proxy-route/lan-proxy-route.sh apply'],
		[_('运行诊断'), '/usr/share/lan-proxy-route/lan-proxy-route.sh diagnose'],
		[_('查看系统日志'), 'logread -e lan-proxy-route | tail -n 80'],
		[_('重启服务'), '/etc/init.d/lan-proxy-route restart']
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
			E('h3', {}, _('服务状态')),
			renderServiceStatus(cfgEnabled, st.running, st)
		];

		if (!st.error && st.backend)
			body.push(renderStatusTable(st));

		body.push(E('h3', {}, _('国内 IP 库')));
		body.push(renderChnrouteUpdate());

		body.push(E('h3', {}, _('最近日志')));
		body.push(E('pre', {
			'style': 'max-height:240px;overflow:auto;white-space:pre-wrap;'
		}, logs || _('暂无日志。请启动服务或使用 verbose 模式 apply 写入 syslog。')));

		body.push(E('h3', {}, _('调试命令')));
		body.push(renderCommands());

		body.push(E('h3', {}, _('原始诊断 JSON')));
		body.push(E('pre', {}, JSON.stringify(st, null, 2)));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LAN 代理路由')),
			E('div', { 'class': 'cbi-section' }, body)
		]);
	}
});
