import SwiftUI
import UniformTypeIdentifiers

/// Sessions X style profile list: every row is an isolated identity (fingerprint + cookies +
/// proxy + last URL). Tap to switch, swipe for rename / export / delete, import JSON files.
struct SessionsView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    let onSelect: (UUID) -> Void

    @State private var renaming: BrowserSession?
    @State private var renameText = ""
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var pendingDelete: BrowserSession?
    @State private var showNewSession = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(store.sessions) { session in
                        row(for: session)
                    }
                } header: {
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                } footer: {
                    Text("Each session keeps its own fingerprint, cookies, proxy and last page. Switching saves the current session's cookies, wipes the shared store and restores the target's.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Menu {
                            Button { showNewSession = true } label: { Label("New session (device + proxy)…", systemImage: "plus.circle") }
                            Button {
                                let copy = store.add(store.duplicateActive())
                                onSelect(copy.id)
                            } label: {
                                Label("Duplicate current (same identity + cookies)", systemImage: "plus.square.on.square")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data], allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionSheet { family, proxy, matchGeo in
                    create(family, proxy: proxy, matchGeo: matchGeo)
                }
                .environmentObject(store)
            }
            .sheet(item: $renaming) { session in
                RenameSheet(title: "Rename session", text: session.name) { newName in
                    store.rename(id: session.id, to: newName)
                }
            }
            .alert(item: $pendingDelete) { session in
                Alert(
                    title: Text("Delete \"\(session.name)\"?"),
                    message: Text("Its fingerprint and \(session.cookies.count) saved cookies are removed permanently."),
                    primaryButton: .destructive(Text("Delete")) { store.remove(id: session.id) },
                    secondaryButton: .cancel()
                )
            }
            .overlay(alignment: .bottom) {
                if let msg = importMessage {
                    Text(msg)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Row

    private func row(for session: BrowserSession) -> some View {
        let isActive = session.id == store.activeID
        return Button {
            onSelect(session.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: session))
                    .font(.system(size: 22))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.name).font(.body.weight(isActive ? .semibold : .regular))
                        if isActive {
                            Text("ACTIVE").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundColor(.accentColor)
                        }
                    }
                    Text(session.deviceLabel).font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Label(session.proxy == nil ? "direct" : session.proxyLabel, systemImage: "network")
                        Label("\(session.cookies.count)", systemImage: "circle.grid.2x2")
                        if !session.lastURL.isEmpty, let host = URL(string: session.lastURL)?.host {
                            Label(host, systemImage: "globe")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
        }
        .foregroundColor(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = session
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                renameText = session.name
                renaming = session
            } label: { Label("Rename", systemImage: "pencil") }
            .tint(.blue)
            Button {
                export(session)
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .tint(.green)
        }
        .contextMenu {
            Button { renaming = session } label: { Label("Rename", systemImage: "pencil") }
            Button { export(session) } label: { Label("Export JSON (Sessions X format)", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { pendingDelete = session } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func icon(for s: BrowserSession) -> String {
        switch s.profile.family {
        case .ios: return "iphone"
        case .android: return "candybarphone"
        case .desktop: return s.profile.kind == .safari ? "laptopcomputer" : "desktopcomputer"
        }
    }

    // MARK: Actions

    private func create(_ family: DeviceFamily?, proxy: ProxyConfig?, matchGeo: Bool) {
        let s = store.add(store.newSession(family: family, proxy: proxy))
        onSelect(s.id)
        // Camoufox geoip: pin time zone / language / coordinates to the proxy's exit IP so the
        // identity never contradicts the address the site sees.
        guard matchGeo, let proxy = proxy else { return }
        GeoIP.resolve(through: proxy) { result in
            switch result {
            case .success(let geo):
                store.pin(geo: geo, to: s.id)
            case .failure(let error):
                let alert = UIAlertController(title: "Location not matched",
                                              message: "The proxy connected but the geo lookup failed (\(error.localizedDescription)). The session keeps its random time zone; set it in Fingerprint → Location.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                TopViewController.present(alert)
            }
        }
    }

    private func export(_ session: BrowserSession) {
        guard let data = store.exportData(for: session.id) else { return }
        let safe = session.name.replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "_", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "session" : safe).json")
        do {
            try data.write(to: url, options: .atomic)
            TopViewController.share(fileURL: url)
        } catch {
            flash("Export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            flash("Import failed: \(error.localizedDescription)")
        case .success(let urls):
            var ok = 0, failed = 0
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    _ = try store.importSession(from: data)
                    ok += 1
                } catch {
                    failed += 1
                }
            }
            flash(failed == 0 ? "Imported \(ok) session\(ok == 1 ? "" : "s")" : "Imported \(ok), failed \(failed)")
        }
    }

    private func flash(_ text: String) {
        withAnimation { importMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if importMessage == text { importMessage = nil } }
        }
    }
}

// MARK: - New session sheet (device + proxy, so the real IP is never used by mistake)

struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// (device family or nil for random, proxy, match location to proxy IP)
    let onCreate: (DeviceFamily?, ProxyConfig?, Bool) -> Void

    @State private var familyChoice: Int = 0       // 0 iPhone, 1 Android, 2 Desktop, 3 Random
    @State private var proxyText: String = ""
    @State private var matchGeo = true
    @State private var confirmNoProxy = false
    @FocusState private var proxyFocused: Bool

    private var family: DeviceFamily? {
        switch familyChoice {
        case 0: return .ios
        case 1: return .android
        case 2: return .desktop
        default: return nil
        }
    }
    private var parsedProxy: ProxyConfig? { ProxyConfig.parse(proxyText) }
    private var proxyEmpty: Bool { proxyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var proxyInvalid: Bool { !proxyEmpty && parsedProxy == nil }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Device", selection: $familyChoice) {
                        Label("iPhone · Safari", systemImage: "iphone").tag(0)
                        Label("Android · Chrome", systemImage: "candybarphone").tag(1)
                        Label("Desktop · Chrome", systemImage: "desktopcomputer").tag(2)
                        Label("Random device", systemImage: "dice").tag(3)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Device")
                } footer: {
                    Text("A fresh, internally consistent identity is generated and pinned to this session for life.")
                }

                Section {
                    HStack {
                        TextField("socks5://host:port:user:pass  ·  host:port", text: $proxyText)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .focused($proxyFocused)
                        Button {
                            if let clip = UIPasteboard.general.string { proxyText = clip.trimmingCharacters(in: .whitespacesAndNewlines) }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        if proxyInvalid {
                            Label("Unrecognised format", systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                        } else if let p = parsedProxy {
                            Label(p.label + (p.user.isEmpty ? "" : " (auth)"), systemImage: "checkmark.shield").foregroundColor(.green)
                        } else {
                            Label("No proxy — your real IP would be visible", systemImage: "exclamationmark.shield").foregroundColor(.red)
                        }
                    }
                    .font(.footnote)
                    Toggle("Match location to proxy IP", isOn: $matchGeo)
                        .disabled(parsedProxy == nil)
                } header: {
                    Text("Proxy (required)")
                } footer: {
                    if ProxyConfig.isSupported {
                        Text("Every request of this session goes through the proxy. \"Match location\" looks up the proxy's exit IP right after creation and pins the time zone, language and GPS position to it (Camoufox geoip), so nothing about the identity contradicts the IP.")
                    } else {
                        Text("Per-session proxies need iOS 17 or later. The proxy is saved with the session but this device cannot apply it — browsing would use your real IP.")
                    }
                }

                Section {
                    Button {
                        onCreate(family, parsedProxy, matchGeo)
                        dismiss()
                    } label: {
                        Label("Create session", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .font(.body.weight(.semibold))
                    .disabled(parsedProxy == nil)

                    if proxyEmpty {
                        Button(role: .destructive) {
                            confirmNoProxy = true
                        } label: {
                            Label("Create without proxy (uses real IP)", systemImage: "exclamationmark.triangle").frame(maxWidth: .infinity)
                        }
                        .font(.footnote)
                    }
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Browse with your real IP address?", isPresented: $confirmNoProxy, titleVisibility: .visible) {
                Button("Create without proxy", role: .destructive) {
                    onCreate(family, nil, false)
                    dismiss()
                }
            } message: {
                Text("The spoofed fingerprint will be paired with your real IP, which sites can log. You can add a proxy later in Fingerprint → Proxy.")
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxyFocused = true }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Rename sheet (iOS 15 has no TextField-in-alert)

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        onSave(text)
        dismiss()
    }
}
