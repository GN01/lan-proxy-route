'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN 代理路由'));
		s = m.section(form.NamedSection, 'global', 'global', _('基本设置'));

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '0';

		o = s.option(form.ListValue, 'backend', _('后端'));
		o.value('auto', _('自动'));
		o.value('nftset', _('nftset'));
		o.value('ipset', _('ipset'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'dns_mode', _('DNS 解析模式'));
		o.value('real-ip', _('真实 IP'));
		o.value('fake-ip', _('虚假 IP'));
		o.value('mixed', _('混合'));
		o.default = 'real-ip';

		s.option(form.Value, 'lan_if', _('LAN 接口')).default = 'br-lan';
		s.option(form.Value, 'mark', _('防火墙标记')).default = '0x210';
		s.option(form.Value, 'table', _('路由表')).datatype = 'uinteger';
		s.option(form.Value, 'priority', _('规则优先级')).datatype = 'uinteger';
		s.option(form.Value, 'fake_ip_cidr', _('虚假 IP 网段')).datatype = 'cidr4';

		s = m.section(form.NamedSection, 'x86', 'proxy_node', _('X86 代理主机'));
		s.option(form.Value, 'ip', _('代理主机 IP')).datatype = 'ip4addr';
		s.option(form.Value, 'dns_port', _('代理 DNS 端口')).datatype = 'port';
		s.option(form.Value, 'mode', _('代理模式')).default = 'dae';

		return m.render();
	}
});
