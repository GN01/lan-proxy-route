'use strict';
'require rpc';

var callReload = rpc.declare({
	object: 'lan-proxy-route',
	method: 'reload',
	expect: { ok: false }
});

return {
	callReload: callReload,
	handleSaveApply: function(view, ev, mode) {
		return view.handleSave(ev).then(function() {
			if (mode !== 'apply')
				return null;
			return callReload();
		}).then(function(res) {
			if (res && res.ok === false)
				throw new Error(res.error || 'reload failed');
		});
	}
};
