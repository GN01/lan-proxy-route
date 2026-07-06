'use strict';
'require view';
'require form';
'require lan-proxy-route.apply as lprApply';

return view.extend({
	handleSaveApply: function(ev, mode) {
		return (new lprApply()).saveAndApply(this, ev, mode);
	},

	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN 代理路由'));
		s = m.section(form.NamedSection, 'access', 'access', _('客户端控制'));

		o = s.option(form.ListValue, 'mode', _('访问模式'));
		o.value('all', _('全部 LAN 客户端'));
		o.value('allowlist', _('仅列表内客户端'));
		o.value('blocklist', _('除黑名单外全部'));
		o.default = 'all';

		o = s.option(form.DynamicList, 'allow_ip', _('允许的 IP 地址'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'allow_cidr', _('允许的网段'));
		o.datatype = 'cidr4';

		o = s.option(form.DynamicList, 'block_ip', _('屏蔽的 IP 地址'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'block_cidr', _('屏蔽的网段'));
		o.datatype = 'cidr4';

		return m.render();
	}
});
