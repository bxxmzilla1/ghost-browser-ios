import Foundation

/// Builds the JavaScript that is injected at document start (all frames) to
/// present the spoofed identity to page scripts.
enum SpoofScript {

    private struct Config: Encodable {
        struct Navigator: Encodable {
            var userAgent: String
            var appVersion: String
            var platform: String
            var vendor: String
            var productSub: String
            var oscpu: String?
            var language: String
            var languages: [String]
            var hardwareConcurrency: Int
            var deviceMemory: Int?
            var maxTouchPoints: Int
            var doNotTrack: String?
            var kind: String
        }
        struct Screen: Encodable {
            var width: Int
            var height: Int
            var availWidth: Int
            var availHeight: Int
            var colorDepth: Int
            var pixelDepth: Int
            var devicePixelRatio: Double
        }
        struct WebGL: Encodable {
            var vendor: String
            var renderer: String
        }

        var navigator: Navigator?
        var screen: Screen?
        var timeZone: String?
        var locale: String?
        var webgl: WebGL?
        var canvas: Bool
        var audio: Bool
        var seed: UInt32
    }

    static func source(for p: FingerprintProfile) -> String {
        var cfg = Config(canvas: p.spoofCanvas, audio: p.spoofAudio, seed: p.seed)
        if p.spoofNavigator {
            cfg.navigator = Config.Navigator(
                userAgent: p.userAgent,
                appVersion: p.appVersion,
                platform: p.platform,
                vendor: p.vendor,
                productSub: p.productSub,
                oscpu: p.oscpu,
                language: p.language,
                languages: p.languages,
                hardwareConcurrency: p.hardwareConcurrency,
                deviceMemory: p.deviceMemory,
                maxTouchPoints: p.maxTouchPoints,
                doNotTrack: p.doNotTrack ? "1" : nil,
                kind: p.kind.rawValue
            )
            cfg.locale = p.language
        }
        if p.spoofScreen {
            cfg.screen = Config.Screen(
                width: p.screenWidth, height: p.screenHeight,
                availWidth: p.availWidth, availHeight: p.availHeight,
                colorDepth: p.colorDepth, pixelDepth: p.colorDepth,
                devicePixelRatio: p.devicePixelRatio
            )
        }
        if p.spoofTimezone { cfg.timeZone = p.timeZone }
        if p.spoofWebGL { cfg.webgl = Config.WebGL(vendor: p.webglVendor, renderer: p.webglRenderer) }

        let json: String
        if let data = try? JSONEncoder().encode(cfg), let s = String(data: data, encoding: .utf8) {
            json = s
        } else {
            json = "{}"
        }
        return template.replacingOccurrences(of: "__CONFIG__", with: json)
    }

    // swiftlint:disable line_length
    private static let template: String = #"""
(function () {
  if (window.__ghostApplied) { return; }
  try { Object.defineProperty(window, '__ghostApplied', { value: true, enumerable: false, configurable: false }); } catch (e) {}
  var cfg = __CONFIG__;

  // ---------- helpers ----------
  var nativeToString = Function.prototype.toString;
  var patched = new WeakMap();
  function mask(fn, orig) { try { if (orig) patched.set(fn, orig); } catch (e) {} return fn; }
  var newToString = function toString() { var o = patched.get(this); return nativeToString.call(o ? o : this); };
  patched.set(newToString, nativeToString);
  try { Function.prototype.toString = newToString; } catch (e) {}

  var hasOwn = function (o, k) { return Object.prototype.hasOwnProperty.call(o, k); };

  function define(obj, name, value) {
    try {
      var desc = Object.getOwnPropertyDescriptor(obj, name);
      var getter = function () { return value; };
      if (desc && typeof desc.get === 'function') { mask(getter, desc.get); }
      Object.defineProperty(obj, name, { get: getter, set: undefined, configurable: true, enumerable: desc ? desc.enumerable : true });
      return true;
    } catch (e) { return false; }
  }
  // Define on the prototype (where WebKit keeps accessors) unless the instance shadows it.
  function defineOn(Ctor, instance, name, value) {
    var proto = Ctor && Ctor.prototype;
    if (instance && hasOwn(instance, name)) { define(instance, name, value); return; }
    if (proto && define(proto, name, value)) { return; }
    if (instance) { define(instance, name, value); }
  }
  function remove(obj, name) { try { if (obj && (name in obj)) { delete obj[name]; } } catch (e) {} }

  // Deterministic per-profile hash -> 0..255
  var seed = (cfg.seed >>> 0) || 1;
  function rng(i) {
    var x = (seed ^ Math.imul(i | 0, 0x9E3779B1)) >>> 0;
    x = Math.imul(x ^ (x >>> 16), 0x85EBCA6B) >>> 0;
    x = Math.imul(x ^ (x >>> 13), 0xC2B2AE35) >>> 0;
    return (x ^ (x >>> 16)) & 0xFF;
  }

  // ---------- navigator ----------
  if (cfg.navigator) {
    var n = cfg.navigator;
    var N = window.Navigator, nav = window.navigator;
    defineOn(N, nav, 'userAgent', n.userAgent);
    defineOn(N, nav, 'appVersion', n.appVersion);
    defineOn(N, nav, 'platform', n.platform);
    defineOn(N, nav, 'vendor', n.vendor);
    defineOn(N, nav, 'vendorSub', '');
    defineOn(N, nav, 'productSub', n.productSub);
    defineOn(N, nav, 'language', n.language);
    defineOn(N, nav, 'languages', Object.freeze(n.languages.slice()));
    defineOn(N, nav, 'hardwareConcurrency', n.hardwareConcurrency);
    defineOn(N, nav, 'maxTouchPoints', n.maxTouchPoints);
    defineOn(N, nav, 'webdriver', false);

    if (n.deviceMemory != null) { defineOn(N, nav, 'deviceMemory', n.deviceMemory); }
    else { remove(N && N.prototype, 'deviceMemory'); remove(nav, 'deviceMemory'); }

    if (n.kind === 'safari') { remove(N && N.prototype, 'doNotTrack'); remove(nav, 'doNotTrack'); }
    else { defineOn(N, nav, 'doNotTrack', n.doNotTrack == null ? null : n.doNotTrack); }

    if (n.oscpu != null) { defineOn(N, nav, 'oscpu', n.oscpu); }
    if (n.kind === 'firefox') { defineOn(N, nav, 'buildID', '20181001000000'); }

    // iOS-only leak
    if (n.platform !== 'iPhone' && n.platform !== 'iPad') { remove(N && N.prototype, 'standalone'); remove(nav, 'standalone'); }

    var isMobileUA = /Mobile|Android/.test(n.userAgent);

    // Plugins: desktop Chrome/Firefox expose 5 PDF viewers, mobile exposes none, Safari stays native.
    if (n.kind !== 'safari') {
      var pluginDefs = isMobileUA ? [] : [
        { name: 'PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'Chrome PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'Chromium PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'Microsoft Edge PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'WebKit built-in PDF', filename: 'internal-pdf-viewer' }
      ];
      var mimeDefs = [
        { type: 'application/pdf', suffixes: 'pdf', description: 'Portable Document Format' },
        { type: 'text/pdf', suffixes: 'pdf', description: 'Portable Document Format' }
      ];
      function arrayLike(items, protoCtor, tag, keyFn) {
        var obj = {};
        try { if (protoCtor) Object.setPrototypeOf(obj, protoCtor.prototype); } catch (e) {}
        items.forEach(function (it, i) { obj[i] = it; var k = keyFn(it); if (k && !(k in obj)) obj[k] = it; });
        Object.defineProperty(obj, 'length', { value: items.length, enumerable: false, configurable: true });
        Object.defineProperty(obj, 'item', { value: function item(i) { return items[i] || null; }, enumerable: false, configurable: true });
        Object.defineProperty(obj, 'namedItem', { value: function namedItem(k) { for (var j = 0; j < items.length; j++) { if (keyFn(items[j]) === k) return items[j]; } return null; }, enumerable: false, configurable: true });
        Object.defineProperty(obj, Symbol.iterator, { value: function () { return items[Symbol.iterator](); }, enumerable: false, configurable: true });
        try { Object.defineProperty(obj, Symbol.toStringTag, { value: tag, configurable: true }); } catch (e) {}
        return obj;
      }
      var allMimes = [];
      var plugins = pluginDefs.map(function (pd) {
        var plugin = {};
        try { Object.setPrototypeOf(plugin, window.Plugin ? window.Plugin.prototype : Object.prototype); } catch (e) {}
        var mimes = mimeDefs.map(function (md) {
          var mt = {};
          try { Object.setPrototypeOf(mt, window.MimeType ? window.MimeType.prototype : Object.prototype); } catch (e) {}
          define(mt, 'type', md.type); define(mt, 'suffixes', md.suffixes); define(mt, 'description', md.description); define(mt, 'enabledPlugin', plugin);
          try { Object.defineProperty(mt, Symbol.toStringTag, { value: 'MimeType', configurable: true }); } catch (e) {}
          return mt;
        });
        define(plugin, 'name', pd.name); define(plugin, 'filename', pd.filename); define(plugin, 'description', 'Portable Document Format');
        define(plugin, 'length', mimes.length);
        mimes.forEach(function (m, i) { plugin[i] = m; plugin[m.type] = m; });
        Object.defineProperty(plugin, 'item', { value: function item(i) { return mimes[i] || null; }, enumerable: false });
        Object.defineProperty(plugin, 'namedItem', { value: function namedItem(k) { return plugin[k] || null; }, enumerable: false });
        Object.defineProperty(plugin, Symbol.iterator, { value: function () { return mimes[Symbol.iterator](); }, enumerable: false });
        try { Object.defineProperty(plugin, Symbol.toStringTag, { value: 'Plugin', configurable: true }); } catch (e) {}
        if (allMimes.length === 0) { allMimes = mimes; }
        return plugin;
      });
      var pluginArray = arrayLike(plugins, window.PluginArray, 'PluginArray', function (p) { return p.name; });
      Object.defineProperty(pluginArray, 'refresh', { value: function refresh() {}, enumerable: false });
      var mimeArray = arrayLike(plugins.length ? allMimes : [], window.MimeTypeArray, 'MimeTypeArray', function (m) { return m.type; });
      defineOn(N, nav, 'plugins', pluginArray);
      defineOn(N, nav, 'mimeTypes', mimeArray);
      defineOn(N, nav, 'pdfViewerEnabled', plugins.length > 0);
    }

    // Chrome extras: userAgentData + window.chrome
    if (n.kind === 'chrome') {
      var major = (/Chrome\/(\d+)/.exec(n.userAgent) || [0, '120'])[1];
      var full = (/Chrome\/([\d.]+)/.exec(n.userAgent) || [0, major + '.0.0.0'])[1];
      var uaPlatform = /Android/.test(n.userAgent) ? 'Android' : /Windows/.test(n.userAgent) ? 'Windows' : /Mac/.test(n.userAgent) ? 'macOS' : /CrOS/.test(n.userAgent) ? 'Chrome OS' : 'Linux';
      var mobile = /Mobile/.test(n.userAgent);
      var brands = [{ brand: 'Not)A;Brand', version: '8' }, { brand: 'Chromium', version: major }, { brand: 'Google Chrome', version: major }];
      var uad = {};
      define(uad, 'brands', brands); define(uad, 'mobile', mobile); define(uad, 'platform', uaPlatform);
      uad.getHighEntropyValues = function getHighEntropyValues(hints) {
        var r = { brands: brands, mobile: mobile, platform: uaPlatform };
        (hints || []).forEach(function (h) {
          if (h === 'architecture') r.architecture = uaPlatform === 'Android' ? 'arm' : 'x86';
          else if (h === 'bitness') r.bitness = '64';
          else if (h === 'model') r.model = uaPlatform === 'Android' ? ((/Android [^;]+; ([^)]+)\)/.exec(n.userAgent) || [0, ''])[1]) : '';
          else if (h === 'platformVersion') r.platformVersion = uaPlatform === 'Windows' ? '15.0.0' : uaPlatform === 'Android' ? '14.0.0' : uaPlatform === 'macOS' ? '14.6.1' : '6.5.0';
          else if (h === 'uaFullVersion') r.uaFullVersion = full;
          else if (h === 'fullVersionList') r.fullVersionList = [{ brand: 'Not)A;Brand', version: '8.0.0.0' }, { brand: 'Chromium', version: full }, { brand: 'Google Chrome', version: full }];
          else if (h === 'wow64') r.wow64 = false;
          else if (h === 'formFactors') r.formFactors = [mobile ? 'Mobile' : 'Desktop'];
        });
        return Promise.resolve(r);
      };
      uad.toJSON = function toJSON() { return { brands: brands, mobile: mobile, platform: uaPlatform }; };
      try { Object.defineProperty(uad, Symbol.toStringTag, { value: 'NavigatorUAData', configurable: true }); } catch (e) {}
      defineOn(N, nav, 'userAgentData', uad);
      if (!window.chrome) {
        try {
          window.chrome = {
            app: { isInstalled: false, getDetails: function getDetails() { return null; }, getIsInstalled: function getIsInstalled() { return false; }, runningState: function runningState() { return 'cannot_run'; } },
            runtime: {},
            loadTimes: function loadTimes() { return {}; },
            csi: function csi() { return {}; }
          };
        } catch (e) {}
      }
    } else {
      remove(N && N.prototype, 'userAgentData'); remove(nav, 'userAgentData');
    }

    // No touch on desktop identities
    if (n.maxTouchPoints === 0) {
      ['TouchEvent', 'Touch', 'TouchList'].forEach(function (k) { remove(window, k); });
      ['ontouchstart', 'ontouchend', 'ontouchmove', 'ontouchcancel'].forEach(function (k) {
        remove(window, k);
        remove(window.Window && window.Window.prototype, k);
        remove(window.HTMLElement && window.HTMLElement.prototype, k);
        remove(window.Document && window.Document.prototype, k);
        remove(window.Element && window.Element.prototype, k);
      });
    }
  }

  // ---------- screen ----------
  if (cfg.screen) {
    var s = cfg.screen, S = window.Screen, scr = window.screen;
    defineOn(S, scr, 'width', s.width);
    defineOn(S, scr, 'height', s.height);
    defineOn(S, scr, 'availWidth', s.availWidth);
    defineOn(S, scr, 'availHeight', s.availHeight);
    defineOn(S, scr, 'availLeft', 0);
    defineOn(S, scr, 'availTop', 0);
    defineOn(S, scr, 'colorDepth', s.colorDepth);
    defineOn(S, scr, 'pixelDepth', s.pixelDepth);
    define(window, 'devicePixelRatio', s.devicePixelRatio);
    define(window, 'outerWidth', s.availWidth);
    define(window, 'outerHeight', s.availHeight);
    define(window, 'screenX', 0);
    define(window, 'screenY', 0);
    define(window, 'screenLeft', 0);
    define(window, 'screenTop', 0);
  }

  // ---------- locale / time zone ----------
  var tz = cfg.timeZone || null;
  var locale = cfg.locale || null;
  var OrigDTF = Intl.DateTimeFormat;
  var probe = null;
  if (tz) {
    try {
      probe = new OrigDTF('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' });
    } catch (e) { tz = null; probe = null; }
  }

  function wrapIntl(name) {
    var Orig = Intl[name];
    if (typeof Orig !== 'function') return;
    var W = function (locales, options) {
      if (locales === undefined && locale) { locales = locale; }
      if (name === 'DateTimeFormat' && tz) {
        options = Object.assign({}, options || {});
        if (options.timeZone === undefined) { options.timeZone = tz; }
      }
      return new Orig(locales, options);
    };
    try { W.prototype = Orig.prototype; } catch (e) {}
    try { Object.defineProperty(W, 'name', { value: Orig.name, configurable: true }); } catch (e) {}
    try { Object.defineProperty(W, 'length', { value: Orig.length, configurable: true }); } catch (e) {}
    Object.getOwnPropertyNames(Orig).forEach(function (k) {
      if (k === 'prototype' || k === 'name' || k === 'length') return;
      try { W[k] = Orig[k]; } catch (e) {}
    });
    mask(W, Orig);
    try { Intl[name] = W; } catch (e) {}
  }
  if (tz || locale) {
    ['DateTimeFormat', 'NumberFormat', 'Collator', 'PluralRules', 'RelativeTimeFormat', 'ListFormat', 'DisplayNames', 'Segmenter'].forEach(function (k) {
      if (k === 'DateTimeFormat' || locale) wrapIntl(k);
    });
  }

  if (tz && probe) {
    function pad(v) { return (v < 10 ? '0' : '') + v; }
    function offsetMinutes(date) {
      var parts = probe.formatToParts(date), m = {};
      for (var i = 0; i < parts.length; i++) { m[parts[i].type] = parts[i].value; }
      var asUTC = Date.UTC(+m.year, +m.month - 1, +m.day, (+m.hour) % 24, +m.minute, +m.second);
      var t = date.getTime(); t -= ((t % 1000) + 1000) % 1000;
      return Math.round((t - asUTC) / 60000);
    }
    function toLocal(d) { return new OrigDate(d.getTime() - offsetMinutes(d) * 60000); }
    function fromLocal(l) {
      var guess = l.getTime() + offsetMinutes(l) * 60000;
      var off2 = offsetMinutes(new OrigDate(guess));
      return l.getTime() + off2 * 60000;
    }
    var longNameFmt = null;
    try { longNameFmt = new OrigDTF('en-US', { timeZone: tz, timeZoneName: 'long' }); } catch (e) {}
    var partsFmt = new OrigDTF('en-US', { timeZone: tz, hourCycle: 'h23', weekday: 'short', year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' });
    function tzString(d) {
      var off = -offsetMinutes(d); var sign = off >= 0 ? '+' : '-'; off = Math.abs(off);
      var name = '';
      try { longNameFmt.formatToParts(d).forEach(function (p) { if (p.type === 'timeZoneName') name = p.value; }); } catch (e) {}
      return 'GMT' + sign + pad(Math.floor(off / 60)) + pad(off % 60) + (name ? ' (' + name + ')' : '');
    }
    function dateParts(d) { var m = {}; partsFmt.formatToParts(d).forEach(function (p) { m[p.type] = p.value; }); m.hour = pad((+m.hour) % 24); return m; }

    var OrigDate = Date;
    var DP = OrigDate.prototype;

    var origGetTZO = DP.getTimezoneOffset;
    DP.getTimezoneOffset = mask(function getTimezoneOffset() { var t = this.getTime(); if (isNaN(t)) return NaN; return offsetMinutes(this); }, origGetTZO);

    var origToString = DP.toString;
    DP.toString = mask(function toString() {
      var t = this.getTime(); if (isNaN(t)) return 'Invalid Date';
      var m = dateParts(this);
      return m.weekday + ' ' + m.month + ' ' + m.day + ' ' + m.year + ' ' + m.hour + ':' + m.minute + ':' + m.second + ' ' + tzString(this);
    }, origToString);
    DP.toTimeString = mask(function toTimeString() {
      var t = this.getTime(); if (isNaN(t)) return 'Invalid Date';
      var m = dateParts(this);
      return m.hour + ':' + m.minute + ':' + m.second + ' ' + tzString(this);
    }, DP.toTimeString);
    DP.toDateString = mask(function toDateString() {
      var t = this.getTime(); if (isNaN(t)) return 'Invalid Date';
      var m = dateParts(this);
      return m.weekday + ' ' + m.month + ' ' + m.day + ' ' + m.year;
    }, DP.toDateString);
    ['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString'].forEach(function (k) {
      var orig = DP[k];
      DP[k] = mask(function (locales, options) {
        if (locales === undefined && locale) { locales = locale; }
        options = Object.assign({}, options || {});
        if (options.timeZone === undefined) { options.timeZone = tz; }
        return orig.call(this, locales, options);
      }, orig);
    });
    ['FullYear', 'Month', 'Date', 'Day', 'Hours', 'Minutes', 'Seconds'].forEach(function (k) {
      var orig = DP['get' + k];
      DP['get' + k] = mask(function () { var t = this.getTime(); if (isNaN(t)) return NaN; return toLocal(this)['getUTC' + k](); }, orig);
    });
    ['FullYear', 'Month', 'Date', 'Hours', 'Minutes', 'Seconds'].forEach(function (k) {
      var orig = DP['set' + k];
      DP['set' + k] = mask(function () {
        var t = this.getTime(); if (isNaN(t)) return orig.apply(this, arguments);
        var l = toLocal(this); l['setUTC' + k].apply(l, arguments); return this.setTime(fromLocal(l));
      }, orig);
    });

    // Date constructor: local-time component form must be interpreted in the spoofed zone.
    var NewDate = function Date(a, b, c, d, e, f, g) {
      if (!(this instanceof NewDate)) { return new OrigDate().toString(); }
      var n = arguments.length;
      if (n === 0) return new OrigDate();
      if (n === 1) return new OrigDate(a);
      var l = new OrigDate(OrigDate.UTC(a, b, c === undefined ? 1 : c, d === undefined ? 0 : d, e === undefined ? 0 : e, f === undefined ? 0 : f, g === undefined ? 0 : g));
      return new OrigDate(fromLocal(l));
    };
    try { NewDate.prototype = DP; } catch (e) {}
    NewDate.now = OrigDate.now; NewDate.parse = OrigDate.parse; NewDate.UTC = OrigDate.UTC;
    try { Object.defineProperty(NewDate, 'length', { value: 7, configurable: true }); } catch (e) {}
    mask(NewDate, OrigDate);
    try { window.Date = NewDate; } catch (e) {}
  }

  // ---------- WebGL ----------
  if (cfg.webgl) {
    var gl = cfg.webgl;
    [window.WebGLRenderingContext, window.WebGL2RenderingContext].forEach(function (C) {
      if (!C || !C.prototype || !C.prototype.getParameter) return;
      var orig = C.prototype.getParameter;
      C.prototype.getParameter = mask(function getParameter(p) {
        if (p === 37445) return gl.vendor;
        if (p === 37446) return gl.renderer;
        return orig.apply(this, arguments);
      }, orig);
    });
  }

  // ---------- canvas ----------
  if (cfg.canvas && window.CanvasRenderingContext2D && window.HTMLCanvasElement) {
    var C2D = window.CanvasRenderingContext2D, HC = window.HTMLCanvasElement;
    function farble(data) {
      var pixels = data.length >> 2;
      var stride = pixels > 262144 ? Math.ceil(pixels / 262144) : 1;
      for (var p = 0; p < pixels; p += stride) {
        var h = rng(p);
        if (h < 12) {
          var i = p << 2;
          if (data[i + 3] !== 0) { data[i] ^= 1; data[i + 1] ^= (h & 1); data[i + 2] ^= ((h >> 1) & 1); }
        }
      }
    }
    var origGetImageData = C2D.prototype.getImageData;
    C2D.prototype.getImageData = mask(function getImageData() {
      var r = origGetImageData.apply(this, arguments);
      try { farble(r.data); } catch (e) {}
      return r;
    }, origGetImageData);

    // Export path: farble a copy so the visible canvas is untouched and repeated exports stay identical.
    function farbledCopy(canvas) {
      if (!canvas.width || !canvas.height) return null;
      var copy = document.createElement('canvas');
      copy.width = canvas.width; copy.height = canvas.height;
      var cctx = copy.getContext('2d');
      if (!cctx) return null;
      cctx.drawImage(canvas, 0, 0);
      var img = origGetImageData.call(cctx, 0, 0, copy.width, copy.height);
      farble(img.data);
      cctx.putImageData(img, 0, 0);
      return copy;
    }
    var origToDataURL = HC.prototype.toDataURL, origToBlob = HC.prototype.toBlob;
    HC.prototype.toDataURL = mask(function toDataURL() {
      var c = null; try { c = farbledCopy(this); } catch (e) {}
      return origToDataURL.apply(c || this, arguments);
    }, origToDataURL);
    HC.prototype.toBlob = mask(function toBlob() {
      var c = null; try { c = farbledCopy(this); } catch (e) {}
      return origToBlob.apply(c || this, arguments);
    }, origToBlob);
    if (window.OffscreenCanvas && window.OffscreenCanvas.prototype.convertToBlob) {
      var origCTB = window.OffscreenCanvas.prototype.convertToBlob;
      window.OffscreenCanvas.prototype.convertToBlob = mask(function convertToBlob() {
        try {
          var ctx = this.getContext('2d');
          if (ctx && this.width && this.height) {
            var img = origGetImageData.call(ctx, 0, 0, this.width, this.height);
            farble(img.data); ctx.putImageData(img, 0, 0);
          }
        } catch (e) {}
        return origCTB.apply(this, arguments);
      }, origCTB);
    }
  }

  // ---------- audio ----------
  if (cfg.audio) {
    if (window.AudioBuffer && window.AudioBuffer.prototype.getChannelData) {
      var origGCD = window.AudioBuffer.prototype.getChannelData;
      var seenBuffers = new WeakMap();
      window.AudioBuffer.prototype.getChannelData = mask(function getChannelData(ch) {
        var arr = origGCD.apply(this, arguments);
        try {
          var done = seenBuffers.get(this);
          if (!done) { done = {}; seenBuffers.set(this, done); }
          if (!done[ch]) {
            done[ch] = true;
            for (var i = 0; i < arr.length; i += 97) { arr[i] = arr[i] + (rng(i) - 128) * 1e-7; }
          }
        } catch (e) {}
        return arr;
      }, origGCD);
    }
    if (window.AnalyserNode) {
      var AP = window.AnalyserNode.prototype;
      if (AP.getFloatFrequencyData) {
        var origFFD = AP.getFloatFrequencyData;
        AP.getFloatFrequencyData = mask(function getFloatFrequencyData(arr) {
          var r = origFFD.apply(this, arguments);
          try { for (var i = 0; i < arr.length; i += 7) { arr[i] = arr[i] + (rng(i) - 128) * 1e-3; } } catch (e) {}
          return r;
        }, origFFD);
      }
      if (AP.getByteFrequencyData) {
        var origBFD = AP.getByteFrequencyData;
        AP.getByteFrequencyData = mask(function getByteFrequencyData(arr) {
          var r = origBFD.apply(this, arguments);
          try { for (var i = 0; i < arr.length; i += 11) { if (rng(i) < 32) arr[i] = arr[i] ^ 1; } } catch (e) {}
          return r;
        }, origBFD);
      }
    }
  }
})();
"""#
    // swiftlint:enable line_length
}
