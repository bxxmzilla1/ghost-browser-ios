import SwiftUI

/// Editor for the session's device / account tokens. Accepts the whole "Key: value" block via
/// paste, plus per-field editing, generation and the host scope for header injection.
struct DeviceTokensView: View {
    @Binding var tokens: DeviceTokens

    @State private var pasteText: String = ""
    @State private var hostsText: String = ""
    @State private var hostsLoaded = false
    @State private var showClearConfirm = false
    @State private var toast: String?

    private var sample: String {
        """
        Username: No data available
        Android ID: android-278da90d972ed9a6
        Device ID: No data available
        IDFV: DC06AFFC-246B-4B22-B1B4-E168C5989F45
        IDFA: 877CD6FE-3E67-4C40-AFC5-9872A791A4FE
        Authorization: No data available
        IG-U-DS-USER-ID: No data available
        IG-INTENDED-USER-ID: No data available
        X-MID: No data available
        X-IG-WWW-Claim: No data available
        """
    }

    var body: some View {
        Form {
            pasteSection
            fieldsSection(title: "Device identifiers", fields: DeviceTokens.Field.allCases.filter { !$0.isHeader })
            fieldsSection(title: "Request headers", fields: DeviceTokens.Field.allCases.filter { $0.isHeader })
            injectionSection
            actionsSection
        }
        .navigationTitle("Device tokens")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hostsLoaded {
                hostsText = tokens.headerHosts.joined(separator: ", ")
                hostsLoaded = true
            }
        }
        .onChange(of: hostsText) { newValue in
            tokens.headerHosts = newValue
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                .map { String($0) }
                .filter { !$0.isEmpty }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Sections

    private var pasteSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text(sample)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(.placeholderText))
                        .padding(.top, 8).padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $pasteText)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .frame(minHeight: 150)
            }
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { pasteText = s }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Spacer()
                Button {
                    let parsed = DeviceTokens.parse(pasteText, into: tokens)
                    let changed = parsed != tokens
                    tokens = parsed
                    pasteText = ""
                    showToast(changed ? "Tokens imported" : "No recognised lines")
                } label: { Label("Import block", systemImage: "square.and.arrow.down") }
                .font(.body.weight(.semibold))
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Paste token block")
        } footer: {
            Text("Paste the whole \"Key: value\" block from your account tool. Lines with \"No data available\" clear that field; unknown lines are ignored. Keys are matched loosely (x_mid, X-MID, X Mid all work).")
        }
    }

    private func fieldsSection(title: String, fields: [DeviceTokens.Field]) -> some View {
        Section(title) {
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(field.rawValue).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        if field.canGenerate {
                            Button {
                                tokens[field] = DeviceTokens.generate(field)
                            } label: {
                                Image(systemName: "dice").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        if !tokens[field].isEmpty {
                            Button {
                                UIPasteboard.general.string = tokens[field]
                                showToast("\(field.rawValue) copied")
                            } label: {
                                Image(systemName: "doc.on.doc").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    TextField(field.hint, text: binding(for: field))
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
        }
    }

    private var injectionSection: some View {
        Section {
            Toggle("Send header tokens", isOn: $tokens.injectHeaders)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hosts (comma separated)").font(.caption).foregroundColor(.secondary)
                TextField("instagram.com, i.instagram.com", text: $hostsText)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            HStack {
                Text("Active headers")
                Spacer()
                Text("\(tokens.headers.count)").foregroundColor(.secondary)
            }
            .font(.footnote)
        } header: {
            Text("Header injection")
        } footer: {
            Text("Authorization, IG-U-DS-USER-ID, IG-INTENDED-USER-ID, X-MID and X-IG-WWW-Claim are added to requests sent to these hosts and their subdomains — page navigations natively, fetch/XHR API calls through the injected script. Device identifiers (Android ID, IDFV, IDFA, …) are stored with the session and travel with its export.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                tokens.fillMissingGenerated()
                showToast("Missing IDs generated")
            } label: { Label("Generate missing identifiers", systemImage: "wand.and.stars") }
            Button {
                UIPasteboard.general.string = tokens.textBlock
                showToast("Token block copied")
            } label: { Label("Copy as block", systemImage: "doc.on.doc") }
            Button(role: .destructive) { showClearConfirm = true } label: {
                Label("Clear all tokens", systemImage: "trash")
            }
            .disabled(tokens.isEmpty)
        }
        .confirmationDialog("Clear all device tokens for this session?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear tokens", role: .destructive) {
                let hosts = tokens.headerHosts
                let inject = tokens.injectHeaders
                tokens = DeviceTokens()
                tokens.headerHosts = hosts
                tokens.injectHeaders = inject
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Helpers

    private func binding(for field: DeviceTokens.Field) -> Binding<String> {
        Binding(get: { tokens[field] }, set: { tokens[field] = $0 })
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
