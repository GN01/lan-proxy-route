'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN 代理路由'));
		s = m.section(form.NamedSection, 'global', 'global', _('路由规则'));
		o = s.option(form.Value, 'fake_ip_cidr', _('虚假 IP 网段'));
		o.datatype = 'cidr4';

		s = m.section(form.NamedSection, 'bypass', 'bypass', _('绕过目标'));
		o = s.option(form.DynamicList, 'cidr', _('绕过网段'));
		o.datatype = 'cidr4';
		o = s.option(form.DynamicList, 'host', _('绕过主机 IP'));
		o.datatype = 'ip4addr';

		return m.render();
	}
});
