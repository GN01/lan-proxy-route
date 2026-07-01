'use strict';
'require view';
'require form';

var moduleName = 'view';
return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'dns', 'dns', _('DNS and Filtering'));

		o = s.option(form.Flag, 'hijack_53', _('Force LAN DNS 53 to OpenWrt'));
		o.default = '1';

		o = s.option(form.Flag, 'block_dot', _('Block DoT TCP/853'));
		o.default = '1';

		o = s.option(form.DynamicList, 'domestic_dns', _('Domestic DNS servers'));
		o.datatype = 'hostport';

		o = s.option(form.DynamicList, 'proxy_dns', _('Proxy DNS servers'));
		o.datatype = 'hostport';

		s = m.section(form.GridSection, 'list', _('Domain Lists'));
		s.addremove = true;
		s.anonymous = false;
		s.option(form.Flag, 'enabled', _('Enabled'));
		o = s.option(form.ListValue, 'role', _('Role'));
		o.value('proxy', _('Proxy'));
		o.value('adblock', _('Ad block'));
		o.value('bypass', _('Bypass'));
		o = s.option(form.ListValue, 'dns_result', _('DNS result'));
		o.value('real-ip', _('real-ip'));
		o.value('fake-ip', _('fake-ip'));
		s.option(form.Value, 'source', _('Source file'));
		o = s.option(form.ListValue, 'dns_upstream', _('DNS upstream'));
		o.value('domestic', _('Domestic'));
		o.value('proxy', _('Proxy'));

		return m.render();
	}
});
