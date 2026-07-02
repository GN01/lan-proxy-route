'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'global', 'global', _('Basic Settings'));

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';

		o = s.option(form.ListValue, 'backend', _('Backend'));
		o.value('auto', _('Automatic'));
		o.value('nftset', _('nftset'));
		o.value('ipset', _('ipset'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'dns_mode', _('DNS result mode'));
		o.value('real-ip', _('real-ip'));
		o.value('fake-ip', _('fake-ip'));
		o.value('mixed', _('mixed'));
		o.default = 'real-ip';

		s.option(form.Value, 'lan_if', _('LAN interface')).default = 'br-lan';
		s.option(form.Value, 'mark', _('Firewall mark')).default = '0x210';
		s.option(form.Value, 'table', _('Route table')).datatype = 'uinteger';
		s.option(form.Value, 'priority', _('Rule priority')).datatype = 'uinteger';
		s.option(form.Value, 'fake_ip_cidr', _('Fake IP CIDR')).datatype = 'cidr4';

		s = m.section(form.NamedSection, 'x86', 'proxy_node', _('X86 Proxy Host'));
		s.option(form.Value, 'ip', _('Proxy host IP')).datatype = 'ip4addr';
		s.option(form.Value, 'dns_port', _('Proxy DNS port')).datatype = 'port';
		s.option(form.Value, 'mode', _('Proxy mode')).default = 'dae';

		return m.render();
	}
});
