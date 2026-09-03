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
                            Section("New session") {
                                Button { create(.ios) } label: { Label("iPhone · Safari", systemImage: "iphone") }
                                Button { create(.android) } label: { Label("Android · Chrome", systemImage: "candybarphone") }
                                Button { create(.desktop) } label: { Label("Desktop · Chrome", systemImage: "desktopcomputer") }
                                Button { create(nil) } label: { Label("Random device", systemImage: "dice") }
                            }
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
                        if let t = session.tokens, !t.isEmpty {
                            Label("tokens", systemImage: "key.horizontal")
                        }
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

    private func create(_ family: DeviceFamily?) {
        let s = store.add(store.newSession(family: family))
        onSelect(s.id)
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
