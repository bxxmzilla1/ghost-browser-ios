import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    let onClearData: () -> Void

    @State private var draft: FingerprintProfile = FingerprintProfile.iphoneSafari
    @State private var proxyText: String = ""
    @State private var loaded = false
    @State private var showClearConfirm = false

    private var parsedProxy: ProxyConfig? { ProxyConfig.parse(proxyText) }
    private var proxyChanged: Bool { parsedProxy != store.proxy }
    private var proxyInvalid: Bool { !proxyText.trimmingCharacters(in: .whitespaces).isEmpty && parsedProxy == nil }

    private var timeZoneOptions: [String] {
        var list = TimeZones.common
        let current = TimeZone.current.identifier
        if !list.contains(current) { list.insert(current, at: 0) }
        if !list.contains(draft.timeZone) { list.insert(draft.timeZone, at: 0) }
        return list
    }

    private var hasChanges: Bool { draft != store.profile || (proxyChanged && !proxyInvalid) }

    var body: some View {
        NavigationView {
            Form {
                identitySection
                togglesSection
                proxySection
                networkSection
                navigatorSection
                screenSection
                localeSection
                graphicsSection
                privacySection
                aboutSection
            }
            .navigationTitle("Fingerprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        if !proxyInvalid { store.proxy = parsedProxy }
                        store.profile = draft
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(!hasChanges)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if !loaded {
                draft = store.profile
                proxyText = store.proxy?.text ?? ""
                loaded = true
            }
        }
    }

    // MARK: Proxy / network

    private var proxySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Proxy link").font(.caption).foregroundColor(.secondary)
                TextField("socks5://host:port:user:pass  ·  host:port", text: $proxyText)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            HStack {
                Text("Status")
                Spacer()
                if proxyInvalid {
                    Label("Unrecognised format", systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                } else if let p = parsedProxy {
                    Text(p.label + (p.user.isEmpty ? "" : " (auth)")).foregroundColor(.secondary)
                } else {
                    Text("direct").foregroundColor(.secondary)
                }
            }
            .font(.footnote)
            if !proxyText.isEmpty {
                Button("Remove proxy", role: .destructive) { proxyText = "" }
            }
        } header: {
            Text("Proxy (this session)")
        } footer: {
            if ProxyConfig.isSupported {
                Text("Accepted formats: socks5://host:port:user:pass · http://user:pass@host:port · host:port:user:pass · host:port. All traffic of this session goes through it; leave empty for a direct connection.")
            } else {
                Text("Per-session proxies need iOS 17 or later (WKWebView proxy support). The value is saved with the session but not applied on this device.")
            }
        }
    }

    private var networkSection: some View {
        Section {
            Toggle("Spoof request headers", isOn: $draft.spoofHeaders)
            Picker("WebRTC", selection: $draft.webrtcPolicy) {
                ForEach(WebRTCPolicy.allCases) { p in Text(p.label).tag(p) }
            }
            Toggle("Spoof uploaded images", isOn: $draft.uploadSpoof)
        } header: {
            Text("Network & uploads")
        } footer: {
            Text("Headers: Accept-Language and (for Chrome identities) Sec-CH-UA client hints are rewritten on top-level navigations to match the identity. Uploads: images chosen in file pickers are re-encoded with fresh noise, sub-pixel rotation, crop/rescale, tone jitter and a rebuilt EXIF block from a random camera profile — each upload gets a unique signature. Videos pass through untouched.")
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            TextField("Profile name", text: $draft.name)
            LabeledField("Device model (label / Android model)", text: $draft.deviceName)
            Menu {
                Section("Random device") {
                    Button { draft = FingerprintProfile.random(family: .ios) } label: { Label("iPhone · Safari", systemImage: "iphone") }
                    Button { draft = FingerprintProfile.random(family: .android) } label: { Label("Android · Chrome", systemImage: "candybarphone") }
                    Button { draft = FingerprintProfile.random(family: .desktop) } label: { Label("Desktop · Chrome", systemImage: "desktopcomputer") }
                    Button { draft = FingerprintProfile.random() } label: { Label("Any", systemImage: "dice") }
                }
                Section("Presets") {
                    ForEach(FingerprintProfile.presets) { preset in
                        Button(preset.name) { draft = preset }
                    }
                }
            } label: {
                HStack {
                    Label("Load preset", systemImage: "square.stack.3d.up")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundColor(.secondary)
                }
            }
            Picker("Engine flavor", selection: $draft.kind) {
                ForEach(BrowserKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
        } header: {
            Text("Identity")
        } footer: {
            Text("Engine flavor controls engine-specific leaks: window.chrome and navigator.userAgentData for Chrome, oscpu/buildID for Firefox, and the plugin list.")
        }
    }

    private var togglesSection: some View {
        Section("Spoofing") {
            Toggle("Navigator (UA, platform, cores…)", isOn: $draft.spoofNavigator)
            Toggle("Screen & pixel ratio", isOn: $draft.spoofScreen)
            Toggle("Time zone & locale", isOn: $draft.spoofTimezone)
            Toggle("WebGL vendor/renderer", isOn: $draft.spoofWebGL)
            Toggle("Canvas noise", isOn: $draft.spoofCanvas)
            Toggle("AudioContext noise", isOn: $draft.spoofAudio)
        }
    }

    private var navigatorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("User agent").font(.caption).foregroundColor(.secondary)
                TextField("User agent", text: $draft.userAgent)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            LabeledField("Platform", text: $draft.platform)
            LabeledField("Vendor", text: $draft.vendor)
            LabeledField("Language", text: $draft.language)
            LabeledField("Languages (comma-separated)", text: Binding(
                get: { draft.languages.joined(separator: ", ") },
                set: { draft.languages = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            ))
            Stepper("CPU cores: \(draft.hardwareConcurrency)", value: $draft.hardwareConcurrency, in: 1...64)
            Picker("Device memory", selection: Binding(
                get: { draft.deviceMemory ?? 0 },
                set: { draft.deviceMemory = $0 == 0 ? nil : $0 }
            )) {
                Text("Hidden (Safari/Firefox)").tag(0)
                ForEach([2, 4, 8, 16, 32], id: \.self) { gb in
                    Text("\(gb) GB").tag(gb)
                }
            }
            Stepper("Touch points: \(draft.maxTouchPoints)", value: $draft.maxTouchPoints, in: 0...10)
            Toggle("Send Do Not Track", isOn: $draft.doNotTrack)
        } header: {
            Text("Navigator")
        } footer: {
            Text("Touch points = 0 also hides TouchEvent and ontouch* handlers like a desktop browser.")
        }
        .disabled(!draft.spoofNavigator)
    }

    private var screenSection: some View {
        Section {
            NumberField("Width", value: $draft.screenWidth)
            NumberField("Height", value: $draft.screenHeight)
            NumberField("Available width", value: $draft.availWidth)
            NumberField("Available height", value: $draft.availHeight)
            HStack {
                Text("Pixel ratio")
                Spacer()
                TextField("1", value: $draft.devicePixelRatio, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            Picker("Color depth", selection: $draft.colorDepth) {
                Text("24-bit").tag(24)
                Text("30-bit").tag(30)
                Text("32-bit").tag(32)
            }
        } header: {
            Text("Screen")
        } footer: {
            Text("The layout viewport (innerWidth/innerHeight) is left untouched so pages keep rendering correctly.")
        }
        .disabled(!draft.spoofScreen)
    }

    private var localeSection: some View {
        Section {
            Picker("Time zone", selection: $draft.timeZone) {
                ForEach(timeZoneOptions, id: \.self) { tz in
                    Text(tz).tag(tz)
                }
            }
            LabeledField("Custom IANA zone", text: $draft.timeZone)
        } header: {
            Text("Time zone")
        } footer: {
            Text("Date, Date.prototype.getTimezoneOffset and Intl.DateTimeFormat are rewritten to this zone. Intl defaults use the navigator language above.")
        }
        .disabled(!draft.spoofTimezone)
    }

    private var graphicsSection: some View {
        Section {
            Group {
                LabeledField("WebGL vendor", text: $draft.webglVendor)
                LabeledField("WebGL renderer", text: $draft.webglRenderer)
            }
            .disabled(!draft.spoofWebGL)
            HStack {
                Text("Noise seed")
                Spacer()
                Text(String(draft.seed)).foregroundColor(.secondary).font(.system(.body, design: .monospaced))
                Button("Re-roll") { draft.rerollSeed() }
                    .buttonStyle(.bordered)
            }
        } header: {
            Text("Graphics & audio")
        } footer: {
            Text("Canvas and AudioContext output gets deterministic noise derived from the seed: stable within a profile, unique across profiles.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Private mode", isOn: $store.privateMode)
            LabeledField("Home page", text: $store.homeURL)
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear cookies, cache & storage", systemImage: "trash")
            }
            .confirmationDialog("Clear all website data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    onClearData()
                    dismiss()
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Private mode uses a non-persistent data store: cookies and storage vanish when the profile changes or the app quits.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Session")
                Spacer()
                Text(store.active.name).foregroundColor(.secondary)
            }
            HStack {
                Text("Identity")
                Spacer()
                Text(store.profile.deviceLabel).foregroundColor(.secondary)
            }
            HStack {
                Text("Saved cookies")
                Spacer()
                Text("\(store.active.cookies.count)").foregroundColor(.secondary)
            }
            Text(store.profile.summary).font(.footnote).foregroundColor(.secondary)
        } header: {
            Text("Status")
        } footer: {
            Text("Spoofing runs as a document-start script in every frame. Changes apply to the next page load. Without a proxy your real IP address is visible.")
        }
    }
}

// MARK: - Small field helpers

private struct LabeledField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Int

    init(_ title: String, value: Binding<Int>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}
