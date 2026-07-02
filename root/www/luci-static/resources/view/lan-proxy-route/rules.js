'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'global', 'global', _('Route Rules'));
		o = s.option(form.Value, 'fake_ip_cidr', _('Fake IP CIDR'));
		o.datatype = 'cidr4';

		s = m.section(form.NamedSection, 'bypass', 'bypass', _('Bypass Destinations'));
		o = s.option(form.DynamicList, 'cidr', _('Bypass CIDR'));
		o.datatype = 'cidr4';
		o = s.option(form.DynamicList, 'host', _('Bypass host IP'));
		o.datatype = 'ip4addr';

		return m.render();
	}
});
