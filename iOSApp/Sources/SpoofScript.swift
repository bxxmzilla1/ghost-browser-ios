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
        struct Geo: Encodable {
            var lat: Double
            var lon: Double
            var accuracy: Double
        }

        var navigator: Navigator?
        var screen: Screen?
        var timeZone: String?
        var locale: String?
        var webgl: WebGL?
        var geolocation: Geo?
        var canvas: Bool
        var audio: Bool
        var seed: UInt32
        /// "allow" | "mask" | "block"
        var webrtc: String
        var uploadSpoof: Bool
        /// CSS-px layout width forced on pages for desktop identities (nil = leave the page's viewport).
        var desktopViewport: Int?
    }

    /// Layout viewport used for desktop identities. WKWebView's desktop content mode does not
    /// override `width=device-width` (Safari does that with a private preference), so the page
    /// would otherwise still lay out at phone width and serve its phone UI.
    static let desktopLayoutWidth = 1280

    static func source(for p: FingerprintProfile) -> String {
        let rtc: String
        switch p.webrtcPolicy {
        case .allow: rtc = "allow"
        case .maskLocal: rtc = "mask"
        case .block: rtc = "block"
        }
        var cfg = Config(canvas: p.spoofCanvas, audio: p.spoofAudio, seed: p.seed, webrtc: rtc, uploadSpoof: p.uploadSpoof,
                         desktopViewport: p.isDesktopLike ? desktopLayoutWidth : nil)
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
        // Pinned geolocation (Camoufox: the map location follows the proxy exit IP). Accuracy is
        // derived from the seed so it is stable per identity but not a suspicious round number.
        if let la = p.latitude, let lo = p.longitude {
            let acc = p.geoAccuracy ?? Double(20 + Int(p.seed % 100))
            cfg.geolocation = Config.Geo(lat: la, lon: lo, accuracy: acc)
        }

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

  // Untouched natives, captured before any patching (the upload spoofer draws with these).
  var RAW = {
    getImageData: window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype.getImageData,
    toBlob: window.HTMLCanvasElement && HTMLCanvasElement.prototype.toBlob,
    toDataURL: window.HTMLCanvasElement && HTMLCanvasElement.prototype.toDataURL
  };

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

      // window.chrome as a real Chrome exposes it (Sessions X shape).
      if (!window.chrome) {
        try {
          var t0 = Date.now();
          window.chrome = {
            app: {
              isInstalled: false,
              InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
              RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
              getDetails: function getDetails() { return null; },
              getIsInstalled: function getIsInstalled() { return false; },
              runningState: function runningState() { return 'cannot_run'; }
            },
            csi: function csi() { return { startE: t0, onloadT: t0 + 300 + (seed % 400), pageT: 500 + (seed % 500), tran: 15 }; },
            loadTimes: function loadTimes() {
              var s = t0 / 1000;
              return { commitLoadTime: s + 0.2, connectionInfo: 'h2', finishDocumentLoadTime: s + 0.6, finishLoadTime: s + 0.9,
                firstPaintAfterLoadTime: 0, firstPaintTime: s + 0.4, navigationType: 'Other', npnNegotiatedProtocol: 'h2',
                requestTime: s, startLoadTime: s, wasAlternateProtocolAvailable: false, wasFetchedViaSpdy: true, wasNpnNegotiated: true };
            },
            runtime: {
              connect: function connect() {}, sendMessage: function sendMessage() {},
              onConnect: { addListener: function addListener() {}, removeListener: function removeListener() {} },
              onMessage: { addListener: function addListener() {}, removeListener: function removeListener() {} }
            }
          };
        } catch (e) {}
      }

      // Network Information API (Chromium only)
      var conn = {};
      define(conn, 'effectiveType', '4g'); define(conn, 'downlink', mobile ? 7.5 : 10); define(conn, 'rtt', mobile ? 100 : 50);
      define(conn, 'saveData', false); conn.onchange = null;
      conn.addEventListener = function addEventListener() {}; conn.removeEventListener = function removeEventListener() {};
      conn.dispatchEvent = function dispatchEvent() { return true; };
      try { Object.defineProperty(conn, Symbol.toStringTag, { value: 'NetworkInformation', configurable: true }); } catch (e) {}
      defineOn(N, nav, 'connection', conn);

      // Battery Status API (Chromium only) — level derived from the seed so it is stable.
      var battery = { charging: true, chargingTime: 0, dischargingTime: Infinity, level: Math.round((0.55 + (seed % 45) / 100) * 100) / 100,
        onchargingchange: null, onchargingtimechange: null, ondischargingtimechange: null, onlevelchange: null,
        addEventListener: function addEventListener() {}, removeEventListener: function removeEventListener() {}, dispatchEvent: function dispatchEvent() { return true; } };
      try { Object.defineProperty(battery, Symbol.toStringTag, { value: 'BatteryManager', configurable: true }); } catch (e) {}
      try { N.prototype.getBattery = mask(function getBattery() { return Promise.resolve(battery); }, null); } catch (e) {}
    } else {
      remove(N && N.prototype, 'userAgentData'); remove(nav, 'userAgentData');
      remove(N && N.prototype, 'connection'); remove(nav, 'connection');
      remove(N && N.prototype, 'getBattery');
    }

    // WKWebView-only surface that no shipping browser exposes.
    if (n.kind !== 'safari') { remove(window, 'webkit'); }

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
      // iOS-WebKit-only surface that desktop browsers never expose; Meta's mobile detection
      // keys on these even when the UA says desktop.
      ['orientation', 'onorientationchange'].forEach(function (k) {
        remove(window, k);
        remove(window.Window && window.Window.prototype, k);
      });
      remove(N && N.prototype, 'standalone'); remove(nav, 'standalone');
    }
  }

  // ---------- desktop layout viewport ----------
  // Pin <meta name=viewport> to a desktop width so responsive sites take their wide breakpoint
  // (WebKit honours live viewport meta changes; the page is scaled to fit and stays zoomable).
  if (cfg.desktopViewport && window === window.top) {
    var VIEWPORT = 'width=' + cfg.desktopViewport + ', user-scalable=yes';
    var pinning = false;
    function pinViewport() {
      if (pinning) return;
      pinning = true;
      try {
        var head = document.head || document.documentElement;
        var metas = document.querySelectorAll('meta[name="viewport" i]');
        if (metas.length === 0) {
          if (head) { var m = document.createElement('meta'); m.setAttribute('name', 'viewport'); m.setAttribute('content', VIEWPORT); head.appendChild(m); }
        } else {
          for (var i = 0; i < metas.length; i++) {
            if (i === 0) { if (metas[i].getAttribute('content') !== VIEWPORT) metas[i].setAttribute('content', VIEWPORT); }
            else if (metas[i].parentNode) metas[i].parentNode.removeChild(metas[i]);
          }
        }
      } catch (e) {}
      pinning = false;
    }
    pinViewport();
    try {
      new MutationObserver(function (muts) {
        for (var i = 0; i < muts.length; i++) {
          var mu = muts[i];
          if (mu.type === 'attributes') { if (mu.target && /^viewport$/i.test(mu.target.getAttribute('name') || '')) { pinViewport(); return; } continue; }
          for (var j = 0; j < mu.addedNodes.length; j++) {
            var nd = mu.addedNodes[j];
            if (nd.nodeType === 1 && (nd.tagName === 'META' || nd.tagName === 'HEAD' || nd.tagName === 'HTML')) { pinViewport(); return; }
          }
        }
      }).observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'name'] });
    } catch (e) {}
    document.addEventListener('DOMContentLoaded', pinViewport, true);
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
    // screen.orientation must agree with the spoofed geometry.
    try {
      var orientationType = s.width > s.height ? 'landscape-primary' : 'portrait-primary';
      if (window.ScreenOrientation && scr.orientation) {
        defineOn(window.ScreenOrientation, scr.orientation, 'type', orientationType);
        defineOn(window.ScreenOrientation, scr.orientation, 'angle', 0);
      } else if (scr && !scr.orientation) {
        define(scr, 'orientation', { type: orientationType, angle: 0, onchange: null,
          addEventListener: function addEventListener() {}, removeEventListener: function removeEventListener() {},
          dispatchEvent: function dispatchEvent() { return true; } });
      }
    } catch (e) {}
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

  // ---------- geolocation ----------
  // Camoufox-style pinned position: every getCurrentPosition/watchPosition call resolves to the
  // identity's coordinates (normally the proxy exit IP's city), with a small per-call wobble like
  // a real GPS fix. The page never sees the phone's real position or a permission prompt.
  if (cfg.geolocation && window.navigator && navigator.geolocation) {
    var G = cfg.geolocation;
    var geoWatches = {};
    var geoWatchSeq = 0;
    function wobble(i) { return (rng(i) - 128) / 128 * (G.accuracy / 111320) * 0.35; }
    function makePosition() {
      var t = Date.now();
      var coords = {
        latitude: G.lat + wobble(t & 0xFFFF), longitude: G.lon + wobble((t >> 3) & 0xFFFF),
        accuracy: Math.round(G.accuracy * (0.85 + (rng(t & 0xFF) / 255) * 0.3)),
        altitude: null, altitudeAccuracy: null, heading: null, speed: null
      };
      try { if (window.GeolocationCoordinates) Object.setPrototypeOf(coords, GeolocationCoordinates.prototype); } catch (e) {}
      var pos = { coords: coords, timestamp: t };
      try { if (window.GeolocationPosition) Object.setPrototypeOf(pos, GeolocationPosition.prototype); } catch (e) {}
      try { pos.toJSON = function toJSON() { return { coords: coords, timestamp: t }; }; } catch (e) {}
      return pos;
    }
    var GP = window.Geolocation ? Geolocation.prototype : Object.getPrototypeOf(navigator.geolocation);
    var origGCP = GP.getCurrentPosition, origWP = GP.watchPosition, origCW = GP.clearWatch;
    GP.getCurrentPosition = mask(function getCurrentPosition(success) {
      if (typeof success === 'function') { setTimeout(function () { try { success(makePosition()); } catch (e) {} }, 40 + rng(7) % 120); }
    }, origGCP);
    GP.watchPosition = mask(function watchPosition(success) {
      var id = ++geoWatchSeq;
      if (typeof success === 'function') {
        var fire = function () { if (geoWatches[id]) { try { success(makePosition()); } catch (e) {} } };
        geoWatches[id] = setInterval(fire, 5000 + rng(id) * 20);
        setTimeout(fire, 40 + rng(id) % 120);
      }
      return id;
    }, origWP);
    GP.clearWatch = mask(function clearWatch(id) {
      if (geoWatches[id]) { clearInterval(geoWatches[id]); delete geoWatches[id]; }
    }, origCW);
    // Permission query must agree: a real user already granted location.
    if (navigator.permissions && navigator.permissions.query) {
      var origPQ = navigator.permissions.query;
      navigator.permissions.query = mask(function query(desc) {
        if (desc && desc.name === 'geolocation') {
          var st = { state: 'granted', onchange: null, addEventListener: function addEventListener() {}, removeEventListener: function removeEventListener() {}, dispatchEvent: function dispatchEvent() { return true; } };
          try { if (window.PermissionStatus) Object.setPrototypeOf(st, PermissionStatus.prototype); } catch (e) {}
          return Promise.resolve(st);
        }
        return origPQ.apply(this, arguments);
      }, origPQ);
    }
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

  // ---------- WebRTC ----------
  if (cfg.webrtc === 'block') {
    ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCDataChannelEvent', 'RTCSessionDescription',
     'RTCIceCandidate', 'RTCPeerConnectionIceEvent', 'RTCPeerConnectionIceErrorEvent', 'RTCRtpSender', 'RTCRtpReceiver',
     'RTCRtpTransceiver', 'RTCDtlsTransport', 'RTCIceTransport', 'RTCSctpTransport', 'RTCTrackEvent', 'RTCCertificate',
     'RTCStatsReport', 'RTCError', 'RTCErrorEvent', 'RTCEncodedVideoFrame', 'RTCEncodedAudioFrame', 'RTCRtpScriptTransform'
    ].forEach(function (k) { remove(window, k); });
  } else if (cfg.webrtc === 'mask' && window.RTCPeerConnection) {
    // Hide LAN candidates: scrub private addresses from local SDP and drop host candidates that leak them.
    var PRIVATE_IP = /(^|[^\d.])(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|169\.254\.\d{1,3}\.\d{1,3}|fe80:[0-9a-f:]+)/i;
    var PC = window.RTCPeerConnection.prototype;
    function scrubSDP(sdp) {
      return String(sdp).split(/\r?\n/).filter(function (line) {
        return !(/^a=candidate:/i.test(line) && PRIVATE_IP.test(line));
      }).join('\r\n').replace(/(c=IN IP4 )(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)\S+/g, function (m, pre) { return pre + '0.0.0.0'; });
    }
    if (PC.setLocalDescription) {
      var origSLD = PC.setLocalDescription;
      PC.setLocalDescription = mask(function setLocalDescription(desc) {
        try {
          if (desc && typeof desc.sdp === 'string') {
            var clean = { type: desc.type, sdp: scrubSDP(desc.sdp) };
            var args = Array.prototype.slice.call(arguments); args[0] = clean;
            return origSLD.apply(this, args);
          }
        } catch (e) {}
        return origSLD.apply(this, arguments);
      }, origSLD);
    }
    function leaks(ev) { try { return ev && ev.candidate && typeof ev.candidate.candidate === 'string' && PRIVATE_IP.test(ev.candidate.candidate); } catch (e) { return false; } }
    var origAEL = PC.addEventListener;
    if (origAEL) {
      PC.addEventListener = mask(function addEventListener(type, listener) {
        if (type === 'icecandidate' && typeof listener === 'function') {
          var args = Array.prototype.slice.call(arguments);
          args[1] = function (ev) { if (!leaks(ev)) return listener.call(this, ev); };
          return origAEL.apply(this, args);
        }
        return origAEL.apply(this, arguments);
      }, origAEL);
    }
    var iceDesc = Object.getOwnPropertyDescriptor(PC, 'onicecandidate');
    if (iceDesc && iceDesc.set) {
      try {
        Object.defineProperty(PC, 'onicecandidate', {
          configurable: true, enumerable: iceDesc.enumerable,
          get: mask(function onicecandidate() { return iceDesc.get.call(this); }, iceDesc.get),
          set: mask(function onicecandidate(fn) {
            if (typeof fn !== 'function') return iceDesc.set.call(this, fn);
            return iceDesc.set.call(this, function (ev) { if (!leaks(ev)) return fn.call(this, ev); });
          }, iceDesc.set)
        });
      } catch (e) {}
    }
  }

  // ---------- upload spoofer ----------
  // Images picked into <input type=file> are re-encoded before the page sees them: random
  // sub-pixel rotation, crop + rescale, tone jitter, per-pixel noise, fresh JPEG quality and a
  // rebuilt EXIF block from a random real camera profile. Ported from Sessions X spoofer-media.
  if (cfg.uploadSpoof && window.File && window.DataTransfer && window.HTMLInputElement && RAW.getImageData && RAW.toBlob) {
    var IMAGE_MIME = /^image\/(jpeg|jpg|png|webp|bmp|heic|heif|tiff)$/i;
    var busy = new WeakSet();
    var justSet = new WeakSet();
    function urand(lo, hi) { return lo + Math.random() * (hi - lo); }
    function upick(a) { return a[Math.floor(Math.random() * a.length)]; }
    function pad2(v) { return (v < 10 ? '0' : '') + v; }

    var CAMERA_PROFILES = [
      { make: 'Canon', model: 'Canon EOS R5', software: 'Adobe Lightroom Classic 13.0', lens: 'RF 50mm F1.2 L USM', focals: [[50, 1]], fnums: [[12, 10], [14, 10], [18, 10]], res: 300 },
      { make: 'Canon', model: 'Canon EOS R6 Mark II', software: 'Adobe Lightroom Classic 12.4', lens: 'RF 24-70mm F2.8 L IS USM', focals: [[24, 1], [35, 1], [50, 1], [70, 1]], fnums: [[28, 10], [32, 10], [40, 10]], res: 300 },
      { make: 'SONY', model: 'ILCE-7M4', software: 'Capture One 23 Pro', lens: 'FE 35mm F1.8', focals: [[35, 1]], fnums: [[18, 10], [22, 10], [28, 10]], res: 240 },
      { make: 'NIKON CORPORATION', model: 'NIKON Z 6_2', software: 'Adobe Photoshop 25.5 (Windows)', lens: 'NIKKOR Z 50mm f/1.8 S', focals: [[50, 1]], fnums: [[18, 10], [22, 10], [28, 10]], res: 300 },
      { make: 'FUJIFILM', model: 'X-T5', software: 'Digital Camera X-T5 Ver1.04', lens: 'XF23mmF1.4 R LM WR', focals: [[23, 1]], fnums: [[14, 10], [20, 10], [28, 10]], res: 72 },
      { make: 'Apple', model: 'iPhone 15 Pro', software: '17.4.1', lens: 'iPhone 15 Pro back triple camera 6.765mm f/1.78', focals: [[6765, 1000]], fnums: [[178, 100]], res: 72 },
      { make: 'Apple', model: 'iPhone 16 Pro', software: '18.5', lens: 'iPhone 16 Pro back triple camera 6.765mm f/1.78', focals: [[6765, 1000]], fnums: [[178, 100]], res: 72 },
      { make: 'samsung', model: 'SM-S928B', software: 'S928BXXU2AXC7', lens: 'Samsung Galaxy S24 Ultra Rear Wide Camera', focals: [[64, 10]], fnums: [[17, 10]], res: 72 },
      { make: 'Google', model: 'Pixel 8 Pro', software: 'HDR+ 1.0.585804401zd', lens: 'Pixel 8 Pro back camera 6.9mm f/1.68', focals: [[69, 10]], fnums: [[168, 100]], res: 72 }
    ];
    var ISO_VALUES = [100, 125, 160, 200, 250, 320, 400, 500, 640, 800];
    var EXPOSURE_DENOMS = [60, 80, 100, 125, 160, 200, 250, 320, 400, 500];

    function randomExifDate() {
      var y = 2022 + Math.floor(Math.random() * 4), mo = 1 + Math.floor(Math.random() * 12), d = 1 + Math.floor(Math.random() * 28);
      return y + ':' + pad2(mo) + ':' + pad2(d) + ' ' + pad2(Math.floor(Math.random() * 24)) + ':' + pad2(Math.floor(Math.random() * 60)) + ':' + pad2(Math.floor(Math.random() * 60));
    }

    // Minimal little-endian TIFF/EXIF writer. types: 2 ASCII, 3 SHORT, 4 LONG, 5 RATIONAL.
    function encodeValue(e) {
      var out = [];
      if (e.type === 2) { var s = String(e.value); for (var i = 0; i < s.length; i++) out.push(s.charCodeAt(i) & 0xFF); out.push(0); return { bytes: out, count: out.length }; }
      if (e.type === 3) { var vs = [].concat(e.value); vs.forEach(function (v) { out.push(v & 0xFF, (v >> 8) & 0xFF); }); return { bytes: out, count: vs.length }; }
      if (e.type === 4) { var vl = [].concat(e.value); vl.forEach(function (v) { out.push(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >>> 24) & 0xFF); }); return { bytes: out, count: vl.length }; }
      if (e.type === 5) { var rs = e.value; rs.forEach(function (r) { [r[0], r[1]].forEach(function (v) { out.push(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >>> 24) & 0xFF); }); }); return { bytes: out, count: rs.length }; }
      return { bytes: out, count: 0 };
    }
    function buildIFD(entries, ifdOffset) {
      entries.sort(function (a, b) { return a.tag - b.tag; });
      var head = [], data = [];
      var dataStart = ifdOffset + 2 + entries.length * 12 + 4;
      head.push(entries.length & 0xFF, (entries.length >> 8) & 0xFF);
      entries.forEach(function (e) {
        var enc = encodeValue(e);
        head.push(e.tag & 0xFF, (e.tag >> 8) & 0xFF, e.type & 0xFF, (e.type >> 8) & 0xFF);
        head.push(enc.count & 0xFF, (enc.count >> 8) & 0xFF, (enc.count >> 16) & 0xFF, (enc.count >>> 24) & 0xFF);
        if (enc.bytes.length <= 4) {
          for (var i = 0; i < 4; i++) head.push(enc.bytes[i] || 0);
        } else {
          var off = dataStart + data.length;
          head.push(off & 0xFF, (off >> 8) & 0xFF, (off >> 16) & 0xFF, (off >>> 24) & 0xFF);
          data = data.concat(enc.bytes);
          if (data.length % 2) data.push(0);
        }
      });
      head.push(0, 0, 0, 0); // next IFD
      return head.concat(data);
    }
    function buildExifSegment() {
      var p = upick(CAMERA_PROFILES), dt = randomExifDate();
      var ifd0 = [
        { tag: 0x010F, type: 2, value: p.make }, { tag: 0x0110, type: 2, value: p.model }, { tag: 0x0112, type: 3, value: 1 },
        { tag: 0x011A, type: 5, value: [[p.res, 1]] }, { tag: 0x011B, type: 5, value: [[p.res, 1]] }, { tag: 0x0128, type: 3, value: 2 },
        { tag: 0x0131, type: 2, value: p.software }, { tag: 0x0132, type: 2, value: dt }, { tag: 0x8769, type: 4, value: 0 }
      ];
      var ifd0Bytes = buildIFD(ifd0, 8);
      var exifOffset = 8 + ifd0Bytes.length;
      ifd0.forEach(function (e) { if (e.tag === 0x8769) e.value = exifOffset; });
      ifd0Bytes = buildIFD(ifd0, 8);
      var exif = [
        { tag: 0x829A, type: 5, value: [[1, upick(EXPOSURE_DENOMS)]] }, { tag: 0x829D, type: 5, value: [upick(p.fnums)] },
        { tag: 0x8827, type: 3, value: upick(ISO_VALUES) }, { tag: 0x9003, type: 2, value: dt }, { tag: 0x9004, type: 2, value: dt },
        { tag: 0x9209, type: 3, value: 0 }, { tag: 0x920A, type: 5, value: [upick(p.focals)] }, { tag: 0xA001, type: 3, value: 1 },
        { tag: 0xA434, type: 2, value: p.lens }
      ];
      var exifBytes = buildIFD(exif, exifOffset);
      var tiff = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00].concat(ifd0Bytes, exifBytes);
      var app1 = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00].concat(tiff);
      var len = app1.length + 2;
      return new Uint8Array([0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF].concat(app1));
    }
    function injectExif(jpeg) {
      if (!(jpeg[0] === 0xFF && jpeg[1] === 0xD8)) return jpeg;
      var seg = buildExifSegment();
      var out = new Uint8Array(jpeg.length + seg.length);
      out[0] = 0xFF; out[1] = 0xD8;
      out.set(seg, 2);
      out.set(jpeg.subarray(2), 2 + seg.length);
      return out;
    }

    function loadImage(file) {
      return new Promise(function (resolve, reject) {
        var url = URL.createObjectURL(file);
        var img = new Image();
        img.onload = function () { URL.revokeObjectURL(url); resolve(img); };
        img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('decode')); };
        img.src = url;
      });
    }
    function toneAndNoise(data) {
      var gamma = urand(0.94, 1.06), contrast = urand(1.03, 1.05), sat = urand(1.06, 1.1), noiseAmp = urand(5, 9);
      var gainR = urand(0.985, 1.015), gainB = urand(0.985, 1.015);
      var lut = new Uint8ClampedArray(256);
      for (var v = 0; v < 256; v++) {
        var x = v / 255;
        x = Math.pow(x, 1 / gamma);
        x = (x - 0.5) * contrast + 0.5;
        x = 0.02 + x * 0.96;                       // curves 0/0.02 … 1/0.98
        lut[v] = Math.round(Math.max(0, Math.min(1, x)) * 255);
      }
      var st = (Math.random() * 0x7fffffff) | 0;
      for (var i = 0; i < data.length; i += 4) {
        var r = lut[data[i]], g = lut[data[i + 1]], b = lut[data[i + 2]];
        var l = 0.299 * r + 0.587 * g + 0.114 * b;
        r = l + (r - l) * sat; g = l + (g - l) * sat; b = l + (b - l) * sat;
        st = (Math.imul(st, 1103515245) + 12345) | 0;
        var nz = ((st >>> 16) & 0xFF) / 255 * 2 - 1;
        data[i] = r * gainR + nz * noiseAmp;
        st = (Math.imul(st, 1103515245) + 12345) | 0;
        data[i + 1] = g + (((st >>> 16) & 0xFF) / 255 * 2 - 1) * noiseAmp;
        st = (Math.imul(st, 1103515245) + 12345) | 0;
        data[i + 2] = b * gainB + (((st >>> 16) & 0xFF) / 255 * 2 - 1) * noiseAmp;
      }
    }
    function spoofImageFile(file) {
      return loadImage(file).then(function (img) {
        var w = img.naturalWidth, h = img.naturalHeight;
        if (!w || !h) throw new Error('empty');
        var scale = 1, maxPx = 12000000;
        if (w * h > maxPx) scale = Math.sqrt(maxPx / (w * h));
        var cropK = urand(0.975, 0.985), rescale = urand(0.99, 1.005);
        var dw = w * scale * rescale, dh = h * scale * rescale;
        var ow = Math.max(1, Math.round(dw * cropK)), oh = Math.max(1, Math.round(dh * cropK));
        var angle = urand(-0.35, 0.35) * Math.PI / 180;
        var c = document.createElement('canvas'); c.width = ow; c.height = oh;
        var ctx = c.getContext('2d');
        if (!ctx) throw new Error('ctx');
        ctx.imageSmoothingEnabled = true;
        try { ctx.imageSmoothingQuality = 'high'; } catch (e) {}
        ctx.translate(ow / 2, oh / 2);
        ctx.rotate(angle);
        ctx.drawImage(img, -dw / 2, -dh / 2, dw, dh);
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        var px = RAW.getImageData.call(ctx, 0, 0, ow, oh);
        toneAndNoise(px.data);
        ctx.putImageData(px, 0, 0);
        return new Promise(function (resolve, reject) {
          RAW.toBlob.call(c, function (b) { b ? resolve(b) : reject(new Error('encode')); }, 'image/jpeg', urand(0.86, 0.94));
        });
      }).then(function (blob) {
        return blob.arrayBuffer();
      }).then(function (buf) {
        var bytes = injectExif(new Uint8Array(buf));
        var stem = String(file.name || 'IMG').replace(/\.[^.]+$/, '') || 'IMG';
        var lastModified = Date.now() - Math.floor(urand(15, 540) * 86400000);
        return new File([bytes], stem + '.jpg', { type: 'image/jpeg', lastModified: lastModified });
      });
    }
    function isFileInput(el) { return el && el.tagName === 'INPUT' && String(el.type).toLowerCase() === 'file'; }
    function shouldSpoof(f) { return IMAGE_MIME.test(f.type) && !/gif/i.test(f.type); }

    window.addEventListener('input', function (e) {
      var el = e.target;
      if (!isFileInput(el) || justSet.has(el)) return;
      if (busy.has(el)) { e.stopImmediatePropagation(); return; }
      var files = Array.prototype.slice.call(el.files || []);
      if (files.some(shouldSpoof)) { e.stopImmediatePropagation(); }
    }, true);

    window.addEventListener('change', function (e) {
      var el = e.target;
      if (!isFileInput(el)) return;
      if (justSet.has(el)) { justSet.delete(el); return; }
      if (busy.has(el)) { e.stopImmediatePropagation(); return; }
      var files = Array.prototype.slice.call(el.files || []);
      if (!files.some(shouldSpoof)) return;
      e.stopImmediatePropagation();
      e.preventDefault();
      busy.add(el);
      Promise.all(files.map(function (f) {
        return shouldSpoof(f) ? spoofImageFile(f).catch(function () { return f; }) : Promise.resolve(f);
      })).then(function (out) {
        var dt = new DataTransfer();
        out.forEach(function (f) { try { dt.items.add(f); } catch (err) {} });
        try { el.files = dt.files; } catch (err) {}
      }).catch(function () {}).then(function () {
        busy.delete(el);
        justSet.add(el);
        try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (err) {}
        try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch (err) {}
        justSet.delete(el);
      });
    }, true);
  }
})();
"""#
    // swiftlint:enable line_length
}
