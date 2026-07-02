'use strict';
'require view';
'require rpc';
'require uci';

var callStatus = rpc.declare({
	object: 'lan-proxy-route',
	method: 'status',
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lan_proxy_route'),
			callStatus().catch(function() {
				return {
					error: true
				};
			})
		]);
	},

	render: function(data) {
		var status = JSON.stringify(data[1] || {}, null, 2);
		if (data[1] && data[1].error)
			status = _('Status unavailable');

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LAN Proxy Route')),
			E('pre', {}, status)
		]);
	}
});
