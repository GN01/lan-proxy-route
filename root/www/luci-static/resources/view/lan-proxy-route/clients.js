'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
		m = new form.Map('lan_proxy_route', _('LAN Proxy Route'));
		s = m.section(form.NamedSection, 'access', 'access', _('Client Control'));

		o = s.option(form.ListValue, 'mode', _('Access mode'));
		o.value('all', _('All LAN clients'));
		o.value('allowlist', _('Only listed clients'));
		o.value('blocklist', _('All except blocked clients'));
		o.default = 'all';

		o = s.option(form.DynamicList, 'allow_ip', _('Allowed IP addresses'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'allow_cidr', _('Allowed CIDR ranges'));
		o.datatype = 'cidr4';

		o = s.option(form.DynamicList, 'block_ip', _('Blocked IP addresses'));
		o.datatype = 'ip4addr';

		o = s.option(form.DynamicList, 'block_cidr', _('Blocked CIDR ranges'));
		o.datatype = 'cidr4';

		return m.render();
	}
});
