import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    @EnvironmentObject private var store: ProfileStore
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var urlText = ""
    @State private var showSettings = false
    @State private var showSessions = false
    @State private var showIGBridge = false
    @State private var toast: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack(alignment: .top) {
                WebViewContainer(webView: model.webView)
                    .id(model.generation)
                if model.isLoading {
                    ProgressView(value: min(max(model.progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(height: 2)
                }
                if let toast = toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            bottomBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            if !model.isConfigured {
                previousActiveID = store.activeID
                model.onNavigationFinished = { [weak store, weak model] url in
                    guard let store = store, let model = model, !store.privateMode else { return }
                    let id = store.activeID
                    model.exportCookies { cookies in store.snapshot(cookies: cookies, url: url, for: id) }
                }
                let s = store.active
                model.apply(profile: s.profile, proxy: s.proxy, privateMode: store.privateMode, keepURL: false)
                model.restoreCookies(s.cookies) { _ in
                    model.load(s.lastURL.isEmpty ? store.homeURL : s.lastURL)
                }
            }
        }
        .onChange(of: store.revision) { _ in
            model.apply(profile: store.profile, proxy: store.proxy, privateMode: store.privateMode)
        }
        .onChange(of: store.activeID) { newID in
            switchSession(to: newID)
        }
        .onChange(of: model.currentURL) { url in
            if !urlFocused { urlText = displayString(for: url) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .inactive { snapshotNow() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClearData: clearData)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSessions) {
            SessionsView(onSelect: { id in
                showSessions = false
                if id != store.activeID { store.setActive(id) }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showIGBridge) {
            InstagramBridgeView(
                currentURL: model.currentURL,
                exportCookies: { done in model.exportCookies(completion: done) },
                importCookies: { cookies in
                    model.restoreCookies(cookies) { count in
                        if !store.privateMode { snapshotNow() }
                        model.load("https://www.instagram.com/")
                        showToast(count > 0 ? "\(count) Instagram cookies set" : "No cookies set")
                    }
                }
            )
        }
    }

    // MARK: Address bar

    private var addressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(model.proxyActive ? .orange : (model.isSecure ? .green : .secondary))
                .frame(width: 18)

            TextField("Search or enter address", text: $urlText)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .focused($urlFocused)
                .onSubmit {
                    urlFocused = false
                    model.load(urlText)
                }
                .onChange(of: urlFocused) { focused in
                    if focused {
                        urlText = model.currentURL?.absoluteString ?? urlText
                    } else {
                        urlText = displayString(for: model.currentURL)
                    }
                }
                .font(.system(size: 15))

            if urlFocused {
                Button {
                    urlText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if model.isLoading { model.stop() } else { model.reload() }
                } label: {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var statusIcon: String {
        if store.privateMode { return "eyeglasses" }
        if model.proxyActive { return "shield.lefthalf.filled" }
        return model.isSecure ? "lock.fill" : "globe"
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", enabled: model.canGoBack) { model.goBack() }
            barButton("chevron.right", enabled: model.canGoForward) { model.goForward() }

            Spacer()

            Menu {
                Section("New identity for this session") {
                    Button {
                        store.profile = FingerprintProfile.random(family: .ios)
                    } label: { Label("Random iPhone", systemImage: "iphone") }
                    Button {
                        store.profile = FingerprintProfile.random(family: .android)
                    } label: { Label("Random Android", systemImage: "candybarphone") }
                    Button {
                        store.profile = FingerprintProfile.random(family: .desktop)
                    } label: { Label("Random Windows PC", systemImage: "desktopcomputer") }
                }
                Button {
                    var p = store.profile
                    p.rerollSeed()
                    store.profile = p
                } label: {
                    Label("Re-roll canvas/audio noise", systemImage: "waveform.path")
                }
                Divider()
                Button {
                    showIGBridge = true
                } label: {
                    Label("Instagram bridge…", systemImage: "arrow.left.arrow.right.circle")
                }
                Toggle(isOn: desktopSiteBinding) {
                    Label("Desktop site", systemImage: "desktopcomputer.and.arrow.down")
                }
                .disabled(store.profile.isDesktopLike && !store.desktopSite)
                Toggle(isOn: $store.privateMode) {
                    Label("Private mode (no persistent data)", systemImage: "eyeglasses")
                }
                Button(role: .destructive) {
                    clearData()
                } label: {
                    Label("Clear website data", systemImage: "trash")
                }
            } label: {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
            }

            Button {
                snapshotNow()
                showSessions = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 17))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.active.name)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(store.active.proxy == nil ? store.active.deviceLabel : store.active.proxyLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 130, alignment: .leading)
                }
                .frame(height: 44)
                .padding(.horizontal, 6)
            }

            barButton("gearshape", enabled: true) { showSettings = true }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }

    /// On when the session is temporarily desktop, or when its own identity is already desktop-class.
    private var desktopSiteBinding: Binding<Bool> {
        Binding(
            get: { store.desktopSite || store.profile.isDesktopLike },
            set: { on in
                store.desktopSite = on
                showToast(on ? "Desktop site · \(store.profile.deviceLabel)" : "Mobile site · \(store.profile.deviceLabel)")
            }
        )
    }

    private func barButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
    }

    // MARK: Session handling

    /// Save the outgoing session's cookies, wipe the shared store, restore the incoming
    /// session's cookies, then rebuild with its fingerprint + proxy and open its last URL.
    private func switchSession(to id: UUID) {
        let outgoingURL = model.currentURL
        let outgoingID = previousActiveID ?? id
        previousActiveID = id
        guard let target = store.sessions.first(where: { $0.id == id }) else { return }

        let finish = {
            model.clearWebsiteData {
                model.apply(profile: target.profile, proxy: target.proxy, privateMode: store.privateMode, keepURL: false)
                model.restoreCookies(target.cookies) { count in
                    model.load(target.lastURL.isEmpty ? store.homeURL : target.lastURL)
                    showToast(count > 0 ? "Switched to \(target.name) • \(count) cookies restored" : "Switched to \(target.name)")
                }
            }
        }
        if store.privateMode || outgoingID == id {
            finish()
        } else {
            model.exportCookies { cookies in
                store.snapshot(cookies: cookies, url: outgoingURL, for: outgoingID)
                finish()
            }
        }
    }

    @State private var previousActiveID: UUID?

    private func snapshotNow() {
        guard !store.privateMode, model.isConfigured else { return }
        let id = store.activeID
        let url = model.currentURL
        model.exportCookies { cookies in
            store.snapshot(cookies: cookies, url: url, for: id)
            store.saveNow()
        }
    }

    // MARK: Helpers

    private func displayString(for url: URL?) -> String {
        guard let url = url else { return "" }
        if url.scheme == "about" { return "" }
        return url.absoluteString
    }

    private func clearData() {
        model.clearWebsiteData {
            store.snapshot(cookies: [], url: nil, for: store.activeID)
            model.apply(profile: store.profile, proxy: store.proxy, privateMode: store.privateMode)
            showToast("Website data cleared")
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
