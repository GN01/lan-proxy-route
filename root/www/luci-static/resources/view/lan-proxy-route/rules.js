'use strict';
'require view';
'require form';
'require lan-proxy-route.apply as lprApply';

return view.extend({
	handleSaveApply: function(ev, mode) {
		return lprApply.handleSaveApply(this, ev, mode);
	},

	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN 代理路由'));

		s = m.section(form.NamedSection, 'bypass', 'bypass', _('绕过目标'));
		o = s.option(form.DynamicList, 'cidr', _('绕过网段'));
		o.datatype = 'cidr4';
		o = s.option(form.DynamicList, 'host', _('绕过主机 IP'));
		o.datatype = 'ip4addr';

		return m.render();
	}
});
