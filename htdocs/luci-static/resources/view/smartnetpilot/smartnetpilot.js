'use strict';
'require view';
'require form';
'require network';
'require uci';
'require ui';
'require dom';
'require rpc';
'require tools.widgets as widgets';

var callGetIp = rpc.declare({
	object: 'luci.smartnetpilot',
	method: 'get_ip',
	expect: { ip: '' }
});

var callArmApply = rpc.declare({
	object: 'luci.smartnetpilot',
	method: 'arm_apply',
	expect: { success: false }
});

var MODES = {
	pppoe: {
		title: _('PPPoE Dial-up'),
		short: _('Broadband account'),
		description: _('Dial up with the broadband account and password supplied by your ISP. Choose this when the line requires PPPoE authentication.'),
		accent: 'snp-accent-violet',
		icon: 'key'
	},
	dhcp: {
		title: _('DHCP Client'),
		short: _('Existing router'),
		description: _('Obtain an address automatically from an upstream modem or router. This is the usual choice for a new router behind an existing gateway.'),
		accent: 'snp-accent-cyan',
		icon: 'link'
	},
	siderouter: {
		title: _('Side Router'),
		short: _('Keep the main router'),
		description: _('Keep the existing main router and use this device for additional services. LAN clients use this device as their gateway.'),
		accent: 'snp-accent-emerald',
		icon: 'topology'
	}
};

var ICONS = {
	logo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l7 4v5c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9V7l7-4z"/><path d="M9.5 12.5l1.8 1.8 3.4-3.6"/></svg>',
	key: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="15" r="4"/><path d="M11 12l8-8"/><path d="M16 7l2 2"/><path d="M18 5l2 2"/></svg>',
	link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9.5 14.5l5-5"/><path d="M7.2 16.8l-1.1 1.1a3.4 3.4 0 01-4.8-4.8l3.4-3.4a3.4 3.4 0 014.8 0"/><path d="M16.8 7.2l1.1-1.1a3.4 3.4 0 014.8 4.8l-3.4 3.4a3.4 3.4 0 01-4.8 0"/></svg>',
	topology: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="6" height="5" rx="1.5"/><rect x="15" y="3" width="6" height="5" rx="1.5"/><rect x="9" y="16" width="6" height="5" rx="1.5"/><path d="M6 8v3.5h12V8"/><path d="M12 11.5V16"/></svg>',
	arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="M14 7l5 5-5 5"/></svg>',
	refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 11a8 8 0 10-2.3 5.7"/><path d="M20 4v7h-7"/></svg>',
	gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 00-1.9-.3 1.7 1.7 0 00-1 1.6v.2h-4V21a1.7 1.7 0 00-1-1.6 1.7 1.7 0 00-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 00.3-1.9 1.7 1.7 0 00-1.6-1H2.8v-4H3a1.7 1.7 0 001.6-1 1.7 1.7 0 00-.3-1.9L4.2 7 7 4.2l.1.1a1.7 1.7 0 001.9.3A1.7 1.7 0 0010 3V2.8h4V3a1.7 1.7 0 001 1.6 1.7 1.7 0 001.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 00-.3 1.9 1.7 1.7 0 001.6 1h.2v4H21a1.7 1.7 0 00-1.6 1z"/></svg>',
	check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6L9 17l-5-5"/></svg>',
	alert: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.3 3.7L2.3 17a2 2 0 001.7 3h16a2 2 0 001.7-3l-8-13.3a2 2 0 00-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>',
	wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 8.8a15 15 0 0120 0"/><path d="M5 12.4a10.5 10.5 0 0114 0"/><path d="M8.5 16a5.5 5.5 0 017 0"/><circle cx="12" cy="19.5" r="1"/></svg>',
	shield: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l7 3v5.5c0 4.2-2.9 7.3-7 8.5-4.1-1.2-7-4.3-7-8.5V6l7-3z"/></svg>',
	info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/></svg>'
};

var pendingRedirect = null;
var appliedListenerBound = false;
var themeListenerBound = false;

function icon(name, className) {
	return E('span', {
		'class': className || '',
		'innerHTML': ICONS[name] || ''
	});
}

function stripCidr(value) {
	if (typeof value !== 'string')
		return '';

	return value.split('/')[0];
}

function currentScriptPage() {
	return window.location.pathname + window.location.search;
}

function buildOrigin(host, useHttps) {
	if (!host)
		return null;

	var protocol = useHttps ? 'https:' : 'http:';
	var port = window.location.port;

	if (!port || port === '80' || port === '443')
		port = '';

	return protocol + '//' + host + (port ? ':' + port : '');
}

function parseColor(value) {
	var match = /^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?\s*\)$/.exec(value || '');
	if (!match)
		return null;

	return {
		r: Number(match[1]),
		g: Number(match[2]),
		b: Number(match[3]),
		a: match[4] != null ? Number(match[4]) : 1
	};
}

function luminance(color) {
	function channel(value) {
		value /= 255;
		return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
	}

	return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

function themeFromNode(node) {
	if (!node)
		return null;

	var tokens = String(node.className || '').toLowerCase().split(/\s+/);
	var darkClasses = [ 'dark', 'dark-mode', 'darkmode', 'theme-dark', 'dark-theme', 'night' ];
	var lightClasses = [ 'light', 'light-mode', 'lightmode', 'theme-light', 'light-theme', 'day' ];
	var i;

	for (i = 0; i < darkClasses.length; i++)
		if (tokens.indexOf(darkClasses[i]) >= 0)
			return 'dark';

	for (i = 0; i < lightClasses.length; i++)
		if (tokens.indexOf(lightClasses[i]) >= 0)
			return 'light';

	var attrs = [ 'data-theme', 'data-mode', 'data-bs-theme', 'data-color-mode' ];
	for (i = 0; i < attrs.length; i++) {
		var value = String(node.getAttribute(attrs[i]) || '').toLowerCase();
		if (value === 'dark' || value === 'night')
			return 'dark';
		if (value === 'light' || value === 'day')
			return 'light';
	}

	return null;
}

function detectTheme() {
	var nodes = [
		document.documentElement,
		document.body,
		document.getElementById('maincontent'),
		document.querySelector('.main-content'),
		document.querySelector('#app'),
		document.querySelector('.app')
	];

	for (var i = 0; i < nodes.length; i++) {
		var marked = themeFromNode(nodes[i]);
		if (marked)
			return marked;
	}

	var probe = document.body;
	while (probe) {
		var color = parseColor(window.getComputedStyle(probe).backgroundColor);
		if (color && color.a >= 0.5)
			return luminance(color) < 0.42 ? 'dark' : 'light';
		probe = probe.parentElement;
	}

	return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function syncTheme() {
	document.documentElement.setAttribute('data-snp-theme', detectTheme());
}

function bindThemeWatchers() {
	if (themeListenerBound)
		return;

	themeListenerBound = true;
	syncTheme();

	var observer = new MutationObserver(syncTheme);
	var options = {
		attributes: true,
		attributeFilter: [ 'class', 'style', 'data-theme', 'data-mode', 'data-bs-theme', 'data-color-mode' ]
	};

	observer.observe(document.documentElement, options);
	if (document.body)
		observer.observe(document.body, options);

	var main = document.getElementById('maincontent');
	if (main)
		observer.observe(main, options);

	if (window.matchMedia) {
		var media = window.matchMedia('(prefers-color-scheme: dark)');
		if (media.addEventListener)
			media.addEventListener('change', syncTheme);
		else if (media.addListener)
			media.addListener(syncTheme);
	}

	window.addEventListener('load', syncTheme);
}

function ensureStyles() {
	if (document.getElementById('snp-styles'))
		return;

	document.head.appendChild(E('link', {
		'id': 'snp-styles',
		'rel': 'stylesheet',
		'href': L.resource('view/smartnetpilot/smartnetpilot.css')
	}));
}

function bindAppliedListener() {
	if (appliedListenerBound)
		return;

	appliedListenerBound = true;

	document.addEventListener('uci-applied', function() {
		var app = document.querySelector('.snp-app');

		if (!app)
			return;

		if (pendingRedirect) {
			var target = pendingRedirect;
			pendingRedirect = null;

			window.setTimeout(function() {
				window.location.replace(target);
			}, 2500);

			return;
		}

		var toast = E('div', { 'class': 'snp-toast is-success' }, [
			icon('check'),
			E('span', {}, _('Configuration applied successfully.'))
		]);

		app.appendChild(toast);
		window.setTimeout(function() {
			if (toast.parentNode)
				toast.parentNode.removeChild(toast);
		}, 4000);
	});
}

function modeInfo(mode) {
	return MODES[mode] || MODES.siderouter;
}

function modeNameFromNetwork(proto) {
	if (proto === 'pppoe')
		return 'pppoe';

	if (proto === 'dhcp' || proto === 'static')
		return 'dhcp';

	return 'siderouter';
}

function sectionValue(config, type, option) {
	var sections = uci.sections(config, type) || [];

	for (var i = 0; i < sections.length; i++)
		if (sections[i][option] != null)
			return sections[i][option];

	return null;
}

return view.extend({
	load: function() {
		ensureStyles();
		bindThemeWatchers();
		bindAppliedListener();

		return Promise.all([
			L.resolveDefault(network.getDevices(), []),
			L.resolveDefault(uci.load('wireless'), null),
			uci.load('network'),
			uci.load('smartnetpilot'),
			L.resolveDefault(callGetIp(), { ip: '' })
		]);
	},

	render: function(data) {
		var devices = data[0] || [];
		var lanIp = (data[4] && data[4].ip) ? data[4].ip : stripCidr(uci.get('network', 'lan', 'ipaddr'));
		var networkProto = uci.get('network', 'wan', 'proto');
		var storedMode = uci.get('smartnetpilot', 'default', 'wan_proto');
		var currentMode = MODES[storedMode] ? storedMode : modeNameFromNetwork(networkProto);
		var wifiSections = uci.sections('wireless', 'wifi-iface') || [];
		var wifiDeviceSections = uci.sections('wireless', 'wifi-device') || [];
		var ap = null;

		for (var i = 0; i < wifiSections.length; i++) {
			if (wifiSections[i].mode === 'ap') {
				ap = wifiSections[i];
				break;
			}
		}

		if (!ap && wifiSections.length)
			ap = wifiSections[0];

		this._devices = devices;
		this._lanIp = lanIp || '';
		this._wanFace = uci.get('network', 'wan', 'device') ||
			uci.get('network', 'wan', 'ifname') ||
			uci.get('smartnetpilot', 'default', 'wan_interface') || '';
		this._hasWifi = wifiSections.length > 0 || wifiDeviceSections.length > 0;
		this._currentMode = currentMode;
		this._wifiSsid = ap ? (ap.ssid || '') : '';
		this._wifiKey = ap ? (ap.key || '') : '';
		this._initialHttps = uci.get('smartnetpilot', 'default', 'https') === '1';
		this._initial = {
			lanIp: this._lanIp,
			https: this._initialHttps,
			wifiSsid: this._wifiSsid,
			wifiKey: this._wifiKey
		};

		var params = new URLSearchParams(window.location.search);
		var requested = params.get('mode');

		if (requested && MODES[requested])
			return this.renderConfig(requested, params.get('tab'));

		return this.renderChooser(currentMode);
	},

	renderChooser: function(currentMode) {
		var info = modeInfo(currentMode);
		var root = E('div', { 'class': 'snp-app snp-chooser' });
		var wifiLabel = this._hasWifi ? (this._wifiSsid || _('Not configured')) : _('No wireless radio');
		var httpsLabel = this._initialHttps ? _('Enabled') : _('Disabled');

		this._root = root;

		root.appendChild(E('section', { 'class': 'snp-hero' }, [
			E('div', { 'class': 'snp-hero-copy' }, [
				E('div', { 'class': 'snp-brand' }, [
					icon('logo', 'snp-logo'),
					E('div', {}, [
						E('div', { 'class': 'snp-brand-name' }, _('Smart NetPilot')),
						E('div', { 'class': 'snp-chip' }, _('Network setup'))
					])
				]),
				E('div', { 'class': 'snp-kicker' }, _('Guided setup')),
				E('h1', {}, _('Set up your network with confidence')),
				E('p', { 'class': 'snp-hero-subtitle' }, _('Choose how this router connects to the internet. Smart NetPilot guides you through the essential settings and applies them safely.')),
				E('div', { 'class': 'snp-hero-meta' }, [
					E('span', { 'class': 'snp-chip' }, [ E('span', { 'class': 'snp-chip-dot' }), _('Automatic light and dark theme') ]),
					E('span', { 'class': 'snp-chip' }, [ icon('shield'), _('Validated before apply') ]),
					E('span', { 'class': 'snp-chip' }, [ icon('wifi'), _('IPv4 and IPv6') ])
				])
			]),
			E('div', { 'class': 'snp-status' }, [
				this._stat(_('Current mode'), info.title),
				this._stat(_('Management address'), this._lanIp || _('Unknown')),
				this._stat(_('Wireless'), wifiLabel),
				this._stat(_('HTTPS management'), httpsLabel)
			])
		]));

		root.appendChild(E('section', { 'class': 'snp-section' }, [
			E('div', { 'class': 'snp-section-head' }, [
				E('div', {}, [
					E('h2', {}, _('Choose a connection mode')),
					E('p', {}, _('Pick the description that matches your internet line. You can change it later without losing the other settings.'))
				]),
				E('span', { 'class': 'snp-section-count' }, _('%d modes').format(3))
			]),
			E('div', { 'class': 'snp-mode-grid' }, [
				this._modeCard('pppoe', currentMode),
				this._modeCard('dhcp', currentMode),
				this._modeCard('siderouter', currentMode)
			]),
			E('div', { 'class': 'snp-help-strip' }, [
				icon('info'),
				E('span', {}, _('Not sure which one to choose? If another router already provides Wi-Fi, use “DHCP Client”. If your ISP gave you a broadband account, use “PPPoE Dial-up”.'))
			])
		]));

		window.setTimeout(syncTheme, 120);

		return root;
	},

	_stat: function(label, value) {
		return E('div', { 'class': 'snp-stat' }, [
			E('span', { 'class': 'snp-stat-label' }, label),
			E('span', { 'class': 'snp-stat-value' }, value)
		]);
	},

	_modeCard: function(mode, currentMode) {
		var info = MODES[mode];
		var self = this;

		return E('button', {
			'type': 'button',
			'class': 'snp-mode-card ' + info.accent + (mode === currentMode ? ' is-current' : ''),
			'aria-pressed': mode === currentMode ? 'true' : 'false',
			'click': function(ev) {
				return self._selectMode(mode, ev.currentTarget);
			}
		}, [
			E('div', { 'class': 'snp-mode-card-top' }, [
				icon(info.icon, 'snp-mode-icon'),
				mode === currentMode ? E('span', { 'class': 'snp-current-pill' }, _('Current')) : E('span')
			]),
			E('div', { 'class': 'snp-mode-body' }, [
				E('h3', { 'class': 'snp-mode-title' }, info.title),
				E('p', { 'class': 'snp-mode-desc' }, info.description)
			]),
			E('div', { 'class': 'snp-mode-foot' }, [
				E('span', {}, _('Configure %s').format(info.short)),
				icon('arrow', 'snp-mode-arrow')
			])
		]);
	},

	_selectMode: function(mode, button) {
		if (this._selecting)
			return;

		this._selecting = true;
		button.classList.add('is-busy');
		button.disabled = true;

		uci.set('smartnetpilot', 'default', 'wan_proto', mode);

		return uci.save().then(function() {
			window.location.href = L.url('admin/network/smartnetpilot') +
				'?mode=' + encodeURIComponent(mode) + '&tab=wansetup';
		}).catch(function(err) {
			this._selecting = false;
			button.classList.remove('is-busy');
			button.disabled = false;
			this._toast(_('Could not save the selected mode. %s').format(err && err.message ? err.message : ''), 'error');
		}.bind(this));
	},

	renderConfig: function(mode, requestedTab) {
		var info = modeInfo(mode);
		var self = this;
		var root = E('div', { 'class': 'snp-app snp-config' });

		this._root = root;
		this._mode = mode;

		root.appendChild(E('section', { 'class': 'snp-hero' }, [
			E('div', { 'class': 'snp-hero-copy' }, [
				E('div', { 'class': 'snp-brand' }, [
					icon('logo', 'snp-logo'),
					E('div', {}, [
						E('div', { 'class': 'snp-brand-name' }, _('Smart NetPilot')),
						E('div', { 'class': 'snp-chip' }, _('Guided setup'))
					])
				]),
				E('div', { 'class': 'snp-kicker' }, _('Configuration')),
				E('h1', {}, info.title),
				E('p', { 'class': 'snp-hero-subtitle' }, info.description)
			]),
			E('div', { 'class': 'snp-hero-actions' }, [
				E('div', { 'class': 'snp-mode-summary ' + info.accent }, [
					icon(info.icon, 'snp-mode-icon'),
					E('div', { 'class': 'snp-mode-summary-text' }, [
						E('strong', {}, _('Selected mode')),
						E('span', {}, info.short)
					])
				]),
				E('a', {
					'class': 'snp-btn snp-btn-ghost',
					'href': L.url('admin/network/smartnetpilot')
				}, [ icon('refresh'), _('Change mode') ])
			])
		]));

		var m = new form.Map('smartnetpilot', null, null);
		var s = m.section(form.NamedSection, 'default', 'smartnetpilot', null);
		s.addremove = false;
		s.anonymous = true;

		s.tab('modesetup', _('Network Mode'));
		s.tab('wansetup', _('WAN Settings'));
		if (this._hasWifi)
			s.tab('wifisetup', _('Wireless Settings'), _('Set the wireless name and password. For advanced options, open Network → Wireless.'));
		s.tab('othersetup', _('Other Settings'));

		this._addModeFields(s, mode);
		this._addWanFields(s);
		if (this._hasWifi)
			this._addWirelessFields(s);
		this._addOtherFields(s);

		this._map = m;

		var shell = E('div', { 'class': 'snp-form-shell' });
		root.appendChild(shell);

		return m.render().then(function(mapNode) {
			dom.append(shell, mapNode);

			self._decorateForm(root, mode);
			self._activateTab(root, requestedTab || 'wansetup');
			window.setTimeout(syncTheme, 120);

			return root;
		});
	},

	_decorateForm: function(root, mode) {
		var proto = root.querySelector('select[id$=".wan_proto"], input[id$=".wan_proto"]');
		if (proto) {
			var row = proto.closest('.cbi-value');
			if (row)
				row.classList.add('snp-hidden');
		}

		var pane = root.querySelector('[data-tab="modesetup"]');
		if (pane && !pane.querySelector('.snp-mode-overview')) {
			var info = modeInfo(mode);
			var overview = E('div', { 'class': 'snp-mode-overview ' + info.accent }, [
				icon(info.icon, 'snp-mode-icon'),
				E('div', { 'class': 'snp-mode-overview-copy' }, [
					E('strong', {}, info.title),
					E('span', {}, info.description)
				]),
				E('a', {
					'class': 'snp-btn snp-btn-ghost',
					'href': L.url('admin/network/smartnetpilot')
				}, [ icon('refresh'), _('Change mode') ])
			]);

			pane.insertBefore(overview, pane.firstChild);
		}
	},

	_activateTab: function(root, tab) {
		if (!tab)
			return;

		var link = root.querySelector('.cbi-tabmenu li[data-tab="' + tab + '"] > a');
		if (link && !link.parentNode.classList.contains('cbi-tab'))
			link.click();
	},

	_addModeFields: function(s, mode) {
		var o = s.taboption('modesetup', form.ListValue, 'wan_proto', _('Network Mode'));
		o.default = mode;
		o.value('dhcp', MODES.dhcp.title);
		o.value('pppoe', MODES.pppoe.title);
		o.value('siderouter', MODES.siderouter.title);
		o.readonly = true;
		o.rmempty = false;
		o.forcewrite = true;
		o.cfgvalue = function() {
			return mode;
		};
	},

	_addWanFields: function(s) {
		var o;

		o = s.taboption('wansetup', form.Flag, 'setlan', _('Configure LAN port addressing'));
		o.default = 0;
		o.rmempty = false;
		o.depends('wan_proto', 'pppoe');
		o.depends('wan_proto', 'dhcp');

		o = s.taboption('wansetup', form.ListValue, 'lan_proto', _('LAN address mode'),
			_('DHCP client mode takes the LAN address from the upstream router. Check the upstream lease table to find the new address.'));
		o.default = 'static';
		o.value('static', _('Static IPv4 address'));
		o.value('dhcp', _('DHCP client (assigned upstream)'));
		o.depends('wan_proto', 'siderouter');
		o.rmempty = false;

		o = s.taboption('wansetup', form.Value, 'lan_ipaddr', _('LAN IPv4 address'),
			_('The management address of this router. Choose an address outside the upstream DHCP pool.'));
		o.default = this._lanIp || '192.168.1.1';
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.depends({ 'wan_proto': 'pppoe', 'setlan': '1' });
		o.depends({ 'wan_proto': 'dhcp', 'setlan': '1' });
		o.depends({ 'wan_proto': 'siderouter', 'lan_proto': 'static' });

		o = s.taboption('wansetup', form.Value, 'lan_netmask', _('LAN IPv4 netmask'));
		o.default = uci.get('smartnetpilot', 'default', 'lan_netmask') || '255.255.255.0';
		o.datatype = 'ip4addr';
		o.value('255.255.255.0');
		o.value('255.255.0.0');
		o.value('255.0.0.0');
		o.rmempty = false;
		o.depends({ 'wan_proto': 'pppoe', 'setlan': '1' });
		o.depends({ 'wan_proto': 'dhcp', 'setlan': '1' });
		o.depends({ 'wan_proto': 'siderouter', 'lan_proto': 'static' });

		o = s.taboption('wansetup', form.Value, 'lan_gateway', _('LAN IPv4 gateway'),
			_('Side router only: enter the address of the main router. It must be in the same subnet as this router.'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.depends({ 'wan_proto': 'siderouter', 'lan_proto': 'static' });

		o = s.taboption('wansetup', form.ListValue, 'dhcp_proto', _('WAN address mode'),
			_('Choose how the WAN interface obtains its address.'));
		o.default = 'dhcp';
		o.value('static', _('Static IPv4 address'));
		o.value('dhcp', _('DHCP client'));
		o.rmempty = false;
		o.depends('wan_proto', 'dhcp');

		o = s.taboption('wansetup', form.DynamicList, 'lan_dns', _('Side router DNS servers'),
			_('DNS servers handed to LAN clients. Leave empty to use the defaults.'));
		o.default = '223.5.5.5';
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.value('223.5.5.5', _('Ali DNS: 223.5.5.5'));
		o.value('180.76.76.76', _('Baidu DNS: 180.76.76.76'));
		o.value('114.114.114.114', _('114 DNS: 114.114.114.114'));
		o.value('8.8.8.8', _('Google DNS: 8.8.8.8'));
		o.value('1.1.1.1', _('Cloudflare DNS: 1.1.1.1'));
		o.depends('wan_proto', 'siderouter');

		o = s.taboption('wansetup', widgets.DeviceSelect, 'wan_interface', _('WAN device'),
			_('Physical network port used for the internet connection.'));
		o.default = this._wanFace || '';
		o.nobridges = false;
		o.rmempty = false;
		o.depends({ 'wan_proto': 'pppoe', 'setlan': '1' });
		o.depends({ 'wan_proto': 'dhcp', 'setlan': '1' });

		o = s.taboption('wansetup', form.Value, 'wan_pppoe_user', _('PPPoE username'));
		o.rmempty = false;
		o.depends('wan_proto', 'pppoe');

		o = s.taboption('wansetup', form.Value, 'wan_pppoe_pass', _('PPPoE password'));
		o.password = true;
		o.rmempty = false;
		o.depends('wan_proto', 'pppoe');

		o = s.taboption('wansetup', form.Value, 'wan_ipaddr', _('WAN IPv4 address'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.depends({ 'wan_proto': 'dhcp', 'dhcp_proto': 'static' });

		o = s.taboption('wansetup', form.Value, 'wan_netmask', _('WAN IPv4 netmask'));
		o.default = '255.255.255.0';
		o.datatype = 'ip4addr';
		o.value('255.255.255.0');
		o.value('255.255.0.0');
		o.value('255.0.0.0');
		o.rmempty = false;
		o.depends({ 'wan_proto': 'dhcp', 'dhcp_proto': 'static' });

		o = s.taboption('wansetup', form.Value, 'wan_gateway', _('WAN IPv4 gateway'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.depends({ 'wan_proto': 'dhcp', 'dhcp_proto': 'static' });

		o = s.taboption('wansetup', form.DynamicList, 'wan_dns', _('Custom DNS servers'),
			_('Leave empty to obtain DNS servers automatically.'));
		o.datatype = 'ip4addr';
		o.value('223.5.5.5', _('Ali DNS: 223.5.5.5'));
		o.value('180.76.76.76', _('Baidu DNS: 180.76.76.76'));
		o.value('114.114.114.114', _('114 DNS: 114.114.114.114'));
		o.value('8.8.8.8', _('Google DNS: 8.8.8.8'));
		o.value('1.1.1.1', _('Cloudflare DNS: 1.1.1.1'));
		o.depends('wan_proto', 'pppoe');
		o.depends('wan_proto', 'dhcp');

		o = s.taboption('wansetup', form.Flag, 'ipv6', _('Enable IPv6'),
			_('Configure IPv6 on the WAN and LAN interfaces. Disable it if your ISP does not provide IPv6.'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('wansetup', form.Flag, 'lan_dhcp', _('Disable the LAN DHCP server'),
			_('Only one DHCP server should run on a network. Disable this router’s server when the main router already provides one.'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('wansetup', form.Flag, 'dnsset', _('Advertise a DNS server to LAN clients'),
			_('Force LAN clients to use the DNS server selected below.'));
		o.default = '0';
		o.rmempty = false;
		o.depends('lan_dhcp', '0');

		o = s.taboption('wansetup', form.ListValue, 'dns_tables', _('DNS server to advertise'));
		o.value('1', _('Use this router’s LAN address'));
		o.value('223.5.5.5', _('Ali DNS: 223.5.5.5'));
		o.value('180.76.76.76', _('Baidu DNS: 180.76.76.76'));
		o.value('114.114.114.114', _('114 DNS: 114.114.114.114'));
		o.value('8.8.8.8', _('Google DNS: 8.8.8.8'));
		o.value('1.1.1.1', _('Cloudflare DNS: 1.1.1.1'));
		o.rmempty = false;
		o.depends('dnsset', '1');

		o = s.taboption('wansetup', form.Flag, 'https', _('Redirect management to HTTPS'),
			_('Generate a local certificate and redirect HTTP requests to HTTPS.'));
		o.default = '0';
		o.rmempty = false;
	},

	_addWirelessFields: function(s) {
		var o = s.taboption('wifisetup', form.Value, 'wifi_ssid', _('Wireless name (SSID)'));
		o.default = this._wifiSsid || '';
		o.datatype = 'maxlength(32)';
		o.placeholder = _('Enter a wireless name');
		o.rmempty = true;

		o = s.taboption('wifisetup', form.Value, 'wifi_key', _('Wireless password'));
		o.default = this._wifiKey || '';
		o.password = true;
		o.datatype = 'wpakey';
		o.placeholder = _('At least 8 characters');
		o.rmempty = true;
	},

	_addOtherFields: function(s) {
		var o = s.taboption('othersetup', form.Flag, 'synflood', _('Enable SYN-flood protection'),
			_('Recommended. Protects the router and LAN clients from SYN-flood attacks.'));
		o.default = '1';
		o.rmempty = false;
	},

	_buildApplyPlan: function() {
		var mode = this._mode || uci.get('smartnetpilot', 'default', 'wan_proto') || 'siderouter';
		var setlan = uci.get('smartnetpilot', 'default', 'setlan') === '1';
		var lanProto = uci.get('smartnetpilot', 'default', 'lan_proto') || 'static';
		var lanIp = uci.get('smartnetpilot', 'default', 'lan_ipaddr') || '';
		var https = uci.get('smartnetpilot', 'default', 'https') === '1';
		var ssid = uci.get('smartnetpilot', 'default', 'wifi_ssid') || '';
		var key = uci.get('smartnetpilot', 'default', 'wifi_key') || '';
		var initial = this._initial || {};
		var initialIp = initial.lanIp || window.location.hostname || '';
		var lanDhcp = mode === 'siderouter' && lanProto === 'dhcp';
		var lanApplies = (mode === 'siderouter' && lanProto === 'static') ||
			((mode === 'pppoe' || mode === 'dhcp') && setlan);
		var desiredIp = lanApplies ? lanIp : null;
		var ipChanged = !lanDhcp && desiredIp && initialIp && desiredIp !== initialIp;
		var httpsChanged = https !== !!initial.https;
		var wifiChanged = this._hasWifi &&
			((ssid && ssid !== initial.wifiSsid) || (key && key !== initial.wifiKey));
		var warnings = [];
		var targetIp = null;

		if (ipChanged) {
			targetIp = desiredIp;
			warnings.push(_('The management address will change from %s to %s. The current page will disconnect and then open the new address.').format(initialIp, desiredIp));
		}
		else if (lanDhcp) {
			warnings.push(_('The LAN interface will become a DHCP client. Its new address is assigned by the upstream router, so it cannot be predicted. Find the lease in the upstream router after applying.'));
		}
		else if (httpsChanged) {
			targetIp = initialIp;
			warnings.push(https
				? _('Management access will switch to HTTPS after the configuration is applied.')
				: _('HTTPS redirection will be disabled. Management access will return to HTTP after the configuration is applied.'));
		}

		if (wifiChanged)
			warnings.push(_('The wireless name or password changed. Wireless clients will need to reconnect.'));

		var redirectTarget = null;
		if (targetIp && (ipChanged || httpsChanged))
			redirectTarget = buildOrigin(targetIp, https) + currentScriptPage();

		return {
			ipChanged: !!ipChanged,
			lanDhcp: lanDhcp,
			httpsChanged: httpsChanged,
			wifiChanged: wifiChanged,
			warnings: warnings,
			unchecked: !!(ipChanged || lanDhcp),
			redirectTarget: redirectTarget
		};
	},

	handleSaveApply: function(ev, mode) {
		var self = this;

		this._applying = true;

		return this.handleSave(ev).then(function() {
			var plan = self._buildApplyPlan();
			self._applying = false;

			var proceed = function() {
				pendingRedirect = plan.redirectTarget;

				return L.resolveDefault(callArmApply(), { success: false }).then(function(res) {
					if (!res || res.success !== true) {
						pendingRedirect = null;
						self._toast(_('Could not prepare the configuration apply. Please try again.'), 'error');
						return;
					}

					ui.changes.apply(mode == '0' && !plan.unchecked);
				});
			};

			if (!plan.warnings.length)
				return proceed();

			return self._confirmApply(plan).then(function(confirmed) {
				if (confirmed)
					return proceed();

				self._toast(_('Apply cancelled.'), 'error');
			});
		}).catch(function(err) {
			self._applying = false;
			self._toast(_('Configuration could not be saved. %s').format(err && err.message ? err.message : ''), 'error');
			throw err;
		});
	},

	_confirmApply: function(plan) {
		var self = this;

		return new Promise(function(resolve) {
			var cancelButton = E('button', {
				'type': 'button',
				'class': 'snp-btn snp-btn-ghost',
				'click': function() {
					self._closeModal();
					resolve(false);
				}
			}, _('Cancel'));

			var acceptButton = E('button', {
				'type': 'button',
				'class': 'snp-btn snp-btn-primary',
				'click': function() {
					self._closeModal();
					resolve(true);
				}
			}, plan.lanDhcp ? _('Apply and disconnect') : _('Continue and apply'));

			var notes = E('div', { 'class': 'snp-modal-note' }, [
				E('strong', {}, _('What will happen')),
				E('ul', {}, plan.warnings.map(function(warning) {
					return E('li', {}, warning);
				}))
			]);

			self._showModal({
				title: _('Review before applying'),
				icon: 'alert',
				iconClass: 'is-warning',
				body: [
					E('p', {}, _('These changes affect how you reach this device. Review them before continuing.')),
					notes,
					plan.redirectTarget
						? E('div', {}, [
							E('p', {}, _('New management address')),
							E('span', { 'class': 'snp-modal-address' }, plan.redirectTarget)
						])
						: E('span')
				],
				actions: [ cancelButton, acceptButton ],
				dismissible: true,
				onDismiss: function() {
					resolve(false);
				}
			});

			window.setTimeout(function() {
				if (acceptButton.parentNode)
					acceptButton.focus();
			}, 30);
		});
	},

	_showModal: function(options) {
		this._closeModal();

		var self = this;
		var backdrop = E('div', {
			'class': 'snp-modal-backdrop',
			'role': 'presentation'
		}, [
			E('div', {
				'class': 'snp-modal',
				'role': 'dialog',
				'aria-modal': 'true',
				'aria-label': options.title || ''
			}, [
				E('div', { 'class': 'snp-modal-icon ' + (options.iconClass || '') }, icon(options.icon || 'info')),
				E('h2', {}, options.title || ''),
				E('div', {}, options.body || []),
				E('div', { 'class': 'snp-modal-actions' }, options.actions || [])
			])
		]);

		if (options.dismissible) {
			backdrop.addEventListener('click', function(ev) {
				if (ev.target === backdrop) {
					self._closeModal();
					if (options.onDismiss)
						options.onDismiss();
				}
			});
		}

		this._modalKeyHandler = function(ev) {
			if (ev.key === 'Escape' && options.dismissible) {
				self._closeModal();
				if (options.onDismiss)
					options.onDismiss();
			}
		};

		document.addEventListener('keydown', this._modalKeyHandler);
		this._modalNode = backdrop;
		document.documentElement.style.overflow = 'hidden';
		this._root.appendChild(backdrop);
	},

	_closeModal: function() {
		if (this._modalKeyHandler) {
			document.removeEventListener('keydown', this._modalKeyHandler);
			this._modalKeyHandler = null;
		}

		if (this._modalNode && this._modalNode.parentNode)
			this._modalNode.parentNode.removeChild(this._modalNode);

		this._modalNode = null;
		document.documentElement.style.overflow = '';
	},

	_toast: function(message, type) {
		var root = this._root;
		if (!root)
			return;

		var toast = E('div', { 'class': 'snp-toast' + (type === 'error' ? ' is-error' : type === 'success' ? ' is-success' : '') }, [
			icon(type === 'error' ? 'alert' : 'check'),
			E('span', {}, message)
		]);

		root.appendChild(toast);

		window.setTimeout(function() {
			if (toast.parentNode)
				toast.parentNode.removeChild(toast);
		}, 4500);
	},

	addFooter: function() {
		if (!this._mode)
			return E([]);

		return view.prototype.addFooter.call(this);
	},

	_currentTab: function() {
		var root = this._root;
		var item = root ? root.querySelector('.cbi-tabmenu li.cbi-tab') : null;

		return item ? item.getAttribute('data-tab') : null;
	},

	handleSave: function(ev) {
		var self = this;
		var activeTab = this._currentTab();

		return view.prototype.handleSave.call(this, ev).then(function(result) {
			if (self._mode && self._root) {
				self._decorateForm(self._root, self._mode);
				self._activateTab(self._root, activeTab || 'wansetup');
			}

			if (!self._applying)
				self._toast(_('Configuration saved. Use “Save & Apply” to make it active.'), 'success');

			return result;
		});
	},

	handleReset: function(ev) {
		if (this._modalNode)
			this._closeModal();

		return view.prototype.handleReset.call(this, ev);
	}
});
