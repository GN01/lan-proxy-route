'use strict';
'require view';
'require rpc';
'require uci';
'require dom';
'require ui';

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

var callCheckChnroute = rpc.declare({
	object: 'lan-proxy-route',
	method: 'check_chnroute',
	expect: {}
});

var callUpdateChnroute = rpc.declare({
	object: 'lan-proxy-route',
	method: 'update_chnroute',
	expect: {}
});

var DEFAULT_CHNROUTE_URL =
	'https://raw.githubusercontent.com/immortalwrt/homeproxy/master/root/etc/homeproxy/resources';

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
		boolRow(_('国内 IP 集合'), st.china_set_present)
	];

	if (st.backend_error)
		rows.push(textRow(_('后端错误'), st.backend_error));

	return E('table', { 'class': 'table' }, rows);
}

function renderResourceManagement(st, initialUrl, view) {
	var versionLabel = E('span', {
		'class': 'label success',
		'style': 'margin-left:0.5em;'
	}, st.china_list_version || _('未知'));

	var entriesLabel = E('span', {
		'class': 'label',
		'style': 'margin-left:0.5em;'
	}, st.china_list_entries != null ? String(st.china_list_entries) : _('未知'));

	var statusBox = E('div', {
		'class': 'cbi-value-description',
		'style': 'margin-top:0.5em;'
	}, '');

	var urlInput = E('input', {
		'class': 'cbi-input-text',
		'style': 'width:100%;max-width:42em;',
		'placeholder': DEFAULT_CHNROUTE_URL,
		'value': initialUrl || ''
	});

	function refreshStatus() {
		return callStatus().then(function(next) {
			if (next && !next.error) {
				versionLabel.textContent = next.china_list_version || _('未知');
				entriesLabel.textContent = next.china_list_entries != null
					? String(next.china_list_entries) : _('未知');
			}
		});
	}

	function setStatus(text, isError) {
		statusBox.textContent = text;
		statusBox.style.color = isError ? '#c44' : '';
	}

	var checkBtn = E('button', {
		'class': 'btn cbi-button cbi-button-action',
		'click': function(ev) {
			var button = ev.target;
			button.disabled = true;
			setStatus(_('检查中…'), false);
			callCheckChnroute().then(function(res) {
				if (!res || res.ok === false)
					throw new Error((res && res.error) || _('检查失败'));

				if (res.update_available) {
					setStatus(_('发现新版本') + ' ' + res.remote_version + '，' + _('正在更新…'), false);
					return callUpdateChnroute().then(function(updateRes) {
						if (!updateRes || updateRes.ok === false)
							throw new Error((updateRes && updateRes.error) || _('更新失败'));
						setStatus(updateRes.message || _('更新完成'), false);
						return refreshStatus();
					});
				}

				setStatus(_('已是最新版本') + ' (' + res.local_version + ')', false);
			}).catch(function(err) {
				setStatus(String(err), true);
			}).finally(function() {
				button.disabled = false;
			});
		}
	}, _('检查更新'));

	var saveBtn = E('button', {
		'class': 'btn cbi-button cbi-button-save',
		'style': 'margin-left:0.5em;',
		'click': function(ev) {
			var button = ev.target;
			var url = urlInput.value.trim();
			button.disabled = true;
			uci.set('lan_proxy_route', 'global', 'chnroute_url', url);
			uci.save().then(function() {
				ui.addNotification(null, E('p', {}, _('自定义更新源已保存')));
			}).catch(function(err) {
				ui.addNotification(null, E('p', { 'class': 'error' }, String(err)));
			}).finally(function() {
				button.disabled = false;
			});
		}
	}, _('保存'));

	return E('div', {}, [
		E('h3', {}, _('资源管理')),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('国内 IPv4 库版本')),
			E('div', { 'class': 'cbi-value-field' }, [ checkBtn, versionLabel ])
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('国内 IP 库条目数')),
			E('div', { 'class': 'cbi-value-field' }, entriesLabel)
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('自定义更新源')),
			E('div', { 'class': 'cbi-value-field' }, [
				urlInput,
				saveBtn,
				E('div', { 'class': 'cbi-value-description' },
					_('留空则使用 HomeProxy 默认源；目录 URL 需包含 china_ip4.txt 与 china_ip4.ver'))
			])
		]),
		statusBox
	]);
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
		var chnrouteUrl = uci.get('lan_proxy_route', 'global', 'chnroute_url') || '';
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

		body.push(renderResourceManagement(st, chnrouteUrl, this));

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
