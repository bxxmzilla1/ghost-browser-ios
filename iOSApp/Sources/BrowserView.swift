import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct TestSite: Identifiable {
    let name: String
    let url: String
    var id: String { url }

    static let all: [TestSite] = [
        TestSite(name: "BrowserLeaks • JavaScript", url: "https://browserleaks.com/javascript"),
        TestSite(name: "BrowserLeaks • Canvas", url: "https://browserleaks.com/canvas"),
        TestSite(name: "BrowserLeaks • WebGL", url: "https://browserleaks.com/webgl"),
        TestSite(name: "BrowserLeaks • Fonts", url: "https://browserleaks.com/fonts"),
        TestSite(name: "CreepJS", url: "https://abrahamjuliot.github.io/creepjs/"),
        TestSite(name: "AmIUnique", url: "https://amiunique.org/fingerprint"),
        TestSite(name: "EFF Cover Your Tracks", url: "https://coveryourtracks.eff.org/"),
        TestSite(name: "WhatIsMyBrowser", url: "https://www.whatismybrowser.com/"),
        TestSite(name: "IPLeak", url: "https://ipleak.net/"),
        TestSite(name: "Pixelscan", url: "https://pixelscan.net/")
    ]
}

struct BrowserView: View {
    @EnvironmentObject private var store: ProfileStore
    @StateObject private var model = BrowserModel()

    @State private var urlText = ""
    @State private var showSettings = false
    @State private var showClearedToast = false
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
                if showClearedToast {
                    Text("Website data cleared")
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
                model.apply(profile: store.profile, privateMode: store.privateMode)
                model.load(store.homeURL)
            }
        }
        .onChange(of: store.profile) { newProfile in
            model.apply(profile: newProfile, privateMode: store.privateMode)
        }
        .onChange(of: store.privateMode) { isPrivate in
            model.apply(profile: store.profile, privateMode: isPrivate)
        }
        .onChange(of: model.currentURL) { url in
            if !urlFocused { urlText = displayString(for: url) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClearData: clearData)
                .environmentObject(store)
        }
    }

    // MARK: Address bar

    private var addressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: store.privateMode ? "eyeglasses" : (model.isSecure ? "lock.fill" : "globe"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(model.isSecure ? .green : .secondary)
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

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", enabled: model.canGoBack) { model.goBack() }
            barButton("chevron.right", enabled: model.canGoForward) { model.goForward() }

            Spacer()

            Menu {
                Section("Fingerprint test sites") {
                    ForEach(TestSite.all) { site in
                        Button(site.name) { model.load(site.url) }
                    }
                }
            } label: {
                Image(systemName: "testtube.2")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
            }

            Menu {
                Section("Presets") {
                    ForEach(FingerprintProfile.presets) { preset in
                        Button {
                            store.profile = preset
                        } label: {
                            if preset.id == store.profile.id {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                }
                Button {
                    store.profile = FingerprintProfile.random()
                } label: {
                    Label("Randomize identity", systemImage: "dice")
                }
                Button {
                    var p = store.profile
                    p.rerollSeed()
                    store.profile = p
                } label: {
                    Label("Re-roll canvas/audio noise", systemImage: "waveform.path")
                }
                Divider()
                Toggle(isOn: $store.privateMode) {
                    Label("Private mode (no persistent data)", systemImage: "eyeglasses")
                }
                Button(role: .destructive) {
                    clearData()
                } label: {
                    Label("Clear website data", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 19))
                    Text(store.profile.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: 140)
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

    private func barButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
    }

    // MARK: Helpers

    private func displayString(for url: URL?) -> String {
        guard let url = url else { return "" }
        if url.scheme == "about" { return "" }
        return url.absoluteString
    }

    private func clearData() {
        model.clearWebsiteData {
            model.apply(profile: store.profile, privateMode: store.privateMode)
            withAnimation { showClearedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation { showClearedToast = false }
            }
        }
    }
}
