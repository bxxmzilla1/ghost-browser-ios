#import "HZWebSpoof.h"

// Kept as plain Objective-C++ (not .xm) so Logos never scans the JavaScript for directives.
// Web counterpart of the Heavenzy identity reset: the real iPhone surface (UA, screen, iOS, time zone)
// is left alone, exactly like the native tweak, and only the per-device entropy changes — canvas and
// audio fingerprints are farbled from the container's seed, WebRTC stops leaking LAN addresses, and
// uploaded photos are re-encoded so the same file never hashes the same twice.
static const char *kHZWebSpoofTemplate = R"HZJS(/*heavenzy-webclip*/
(function () {
  if (window.__hzApplied) { return; }
  try { Object.defineProperty(window, '__hzApplied', { value: true, enumerable: false, configurable: false }); } catch (e) {}
  var cfg = __CONFIG__;

  var nativeToString = Function.prototype.toString;
  var patched = new WeakMap();
  function mask(fn, orig) { try { if (orig) patched.set(fn, orig); } catch (e) {} return fn; }
  var newToString = function toString() { var o = patched.get(this); return nativeToString.call(o ? o : this); };
  patched.set(newToString, nativeToString);
  try { Function.prototype.toString = newToString; } catch (e) {}

  var seed = (cfg.seed >>> 0) || 1;
  function rng(i) {
    var x = (seed ^ Math.imul(i | 0, 0x9E3779B1)) >>> 0;
    x = Math.imul(x ^ (x >>> 16), 0x85EBCA6B) >>> 0;
    x = Math.imul(x ^ (x >>> 13), 0xC2B2AE35) >>> 0;
    return (x ^ (x >>> 16)) & 0xFF;
  }

  var RAW = {
    getImageData: window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype.getImageData,
    toBlob: window.HTMLCanvasElement && HTMLCanvasElement.prototype.toBlob
  };

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

  // ---------- WebRTC: hide LAN candidates ----------
  if (cfg.webrtc === 'mask' && window.RTCPeerConnection) {
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
            var args = Array.prototype.slice.call(arguments); args[0] = { type: desc.type, sdp: scrubSDP(desc.sdp) };
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
  // Images picked into <input type=file> are re-encoded before the page sees them: sub-pixel rotation,
  // crop + rescale, tone jitter, per-pixel noise, fresh JPEG quality and a rebuilt EXIF block.
  if (cfg.upload && window.File && window.DataTransfer && window.HTMLInputElement && RAW.getImageData && RAW.toBlob) {
    var IMAGE_MIME = /^image\/(jpeg|jpg|png|webp|bmp|heic|heif|tiff)$/i;
    var busy = new WeakSet();
    var justSet = new WeakSet();
    function urand(lo, hi) { return lo + Math.random() * (hi - lo); }
    function upick(a) { return a[Math.floor(Math.random() * a.length)]; }
    function pad2(v) { return (v < 10 ? '0' : '') + v; }

    var CAMERA_PROFILES = [
      { make: 'Apple', model: 'iPhone 13', software: '17.5.1', lens: 'iPhone 13 back dual wide camera 5.1mm f/1.6', focals: [[51, 10]], fnums: [[16, 10]], res: 72 },
      { make: 'Apple', model: 'iPhone 14 Pro', software: '17.6.1', lens: 'iPhone 14 Pro back triple camera 6.86mm f/1.78', focals: [[686, 100]], fnums: [[178, 100]], res: 72 },
      { make: 'Apple', model: 'iPhone 15', software: '18.3.2', lens: 'iPhone 15 back dual wide camera 6.24mm f/1.6', focals: [[624, 100]], fnums: [[16, 10]], res: 72 },
      { make: 'Apple', model: 'iPhone 15 Pro', software: '17.4.1', lens: 'iPhone 15 Pro back triple camera 6.765mm f/1.78', focals: [[6765, 1000]], fnums: [[178, 100]], res: 72 },
      { make: 'Apple', model: 'iPhone 16 Pro', software: '18.5', lens: 'iPhone 16 Pro back triple camera 6.765mm f/1.78', focals: [[6765, 1000]], fnums: [[178, 100]], res: 72 }
    ];
    var ISO_VALUES = [32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400];
    var EXPOSURE_DENOMS = [60, 80, 100, 120, 160, 200, 250, 320, 400, 500, 1000];

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
      if (e.type === 5) { e.value.forEach(function (r) { [r[0], r[1]].forEach(function (v) { out.push(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >>> 24) & 0xFF); }); }); return { bytes: out, count: e.value.length }; }
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
      head.push(0, 0, 0, 0);
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
        var x = Math.pow(v / 255, 1 / gamma);
        x = (x - 0.5) * contrast + 0.5;
        x = 0.02 + x * 0.96;
        lut[v] = Math.round(Math.max(0, Math.min(1, x)) * 255);
      }
      var st = (Math.random() * 0x7fffffff) | 0;
      for (var i = 0; i < data.length; i += 4) {
        var r = lut[data[i]], g = lut[data[i + 1]], b = lut[data[i + 2]];
        var l = 0.299 * r + 0.587 * g + 0.114 * b;
        r = l + (r - l) * sat; g = l + (g - l) * sat; b = l + (b - l) * sat;
        st = (Math.imul(st, 1103515245) + 12345) | 0;
        data[i] = r * gainR + (((st >>> 16) & 0xFF) / 255 * 2 - 1) * noiseAmp;
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
)HZJS";

NSString *const HZWebSpoofMarker = @"/*heavenzy-webclip*/";

NSString *HZWebSpoofSource(NSDictionary *container) {
    id upload = container[@"upload"];
    NSDictionary *cfg = @{
        @"seed": @([container[@"seed"] unsignedIntValue] ?: 1u),
        @"canvas": @YES,
        @"audio": @YES,
        @"webrtc": @"mask",
        @"upload": @(upload ? [upload boolValue] : YES),
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:cfg options:0 error:nil];
    NSString *cfgString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    NSString *tpl = [NSString stringWithUTF8String:kHZWebSpoofTemplate];
    return [tpl stringByReplacingOccurrencesOfString:@"__CONFIG__" withString:cfgString];
}
