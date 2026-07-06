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

		s.option(form.Value, 'lan_if', _('LAN 接口')).default = 'br-lan';
		s.option(form.Value, 'mark', _('防火墙标记')).default = '0x210';
		s.option(form.Value, 'table', _('路由表')).datatype = 'uinteger';
		s.option(form.Value, 'priority', _('规则优先级')).datatype = 'uinteger';

		o = s.option(form.Value, 'chnroute_url', _('国内 IP 库更新源'));
		o.placeholder = 'https://raw.githubusercontent.com/immortalwrt/homeproxy/master/root/etc/homeproxy/resources';
		o.optional = true;

		s = m.section(form.NamedSection, 'x86', 'proxy_node', _('X86 代理主机'));
		s.option(form.Value, 'ip', _('代理主机 IP')).datatype = 'ip4addr';
		s.option(form.Value, 'mode', _('代理模式')).default = 'dae';

		return m.render();
	}
});
