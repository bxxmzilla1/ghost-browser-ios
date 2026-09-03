import SwiftUI
import UIKit

/// Sheet that ties the current instagram.com web session to the sideloaded native Instagram
/// (Blaze) app: open-in-app deep links, export the login as native tokens, and import a pasted
/// cookie/token block back into the session.
struct InstagramBridgeView: View {
    @Environment(\.dismiss) private var dismiss

    let currentURL: URL?
    /// Snapshot the live web cookies (main-thread callback).
    let exportCookies: (@escaping ([CookieRecord]) -> Void) -> Void
    /// Inject cookies into the session, then reload instagram.com.
    let importCookies: ([CookieRecord]) -> Void

    @State private var session = InstagramBridge.Session()
    @State private var loaded = false
    @State private var pasteText = ""
    @State private var toast: String?

    private var deepLinks: [InstagramBridge.DeepLink] { InstagramBridge.deepLinks(for: currentURL) }

    var body: some View {
        NavigationView {
            Form {
                openSection
                exportSection
                importSection
            }
            .navigationTitle("Instagram bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: refresh)
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

    // MARK: Open in app

    private var openSection: some View {
        Section {
            ForEach(deepLinks) { link in
                Button {
                    open(link.url)
                } label: {
                    Label(link.title, systemImage: link.systemImage)
                }
            }
        } header: {
            Text("Open in Instagram app")
        } footer: {
            Text("Launches the sideloaded Instagram (with its Blaze spoofing). If nothing happens, the app isn't installed — sideload IG IPA/Instagram.ipa first.")
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            if session.hasLogin {
                row("Logged-in user id", session.dsUserID)
                if !session.mid.isEmpty { row("X-MID", session.mid) }
                if !session.igDid.isEmpty { row("Device ID (ig_did)", session.igDid) }

                Button {
                    if let auth = session.authorizationHeader { copy(auth, "Authorization copied") }
                } label: { Label("Copy Authorization (Bearer IGT:2:…)", systemImage: "key.horizontal") }
                .disabled(session.authorizationHeader == nil)

                Button {
                    copy(session.tokenBlock, "Token block copied")
                } label: { Label("Copy token block", systemImage: "doc.on.clipboard") }

                Button {
                    copy(session.cookieHeader, "Cookie string copied")
                } label: { Label("Copy cookie string", systemImage: "number") }
            } else {
                Label("No Instagram login found in this session.", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundColor(.secondary)
                Text("Log in at instagram.com in this session, then reopen this bridge.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Button {
                refresh()
                showToast("Refreshed")
            } label: { Label("Refresh from web session", systemImage: "arrow.clockwise") }
        } header: {
            Text("Export web login → native tokens")
        } footer: {
            Text("Authorization is rebuilt from the web sessionid + ds_user_id in the mobile \"Bearer IGT:2:…\" form the native app uses. IDFA/IDFV/Android ID are native-only and show \"No data available\".")
        }
    }

    // MARK: Import

    private var importSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste cookies (name=value; …), a JSON cookie array, or a Key: value token block")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.placeholderText))
                        .padding(.top, 8).padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $pasteText)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .frame(minHeight: 110)
            }
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { pasteText = s }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Spacer()
                Button {
                    let cookies = InstagramBridge.parseCookies(pasteText)
                    guard !cookies.isEmpty else { showToast("No Instagram cookies found"); return }
                    importCookies(cookies)
                    pasteText = ""
                    showToast("\(cookies.count) cookies imported")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
                } label: { Label("Import into session", systemImage: "square.and.arrow.down") }
                .font(.body.weight(.semibold))
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Import login → this session")
        } footer: {
            Text("Sets the cookies on instagram.com in this session and reloads. Use it to continue a login captured elsewhere in the web view.")
        }
    }

    // MARK: Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                .font(.system(size: 13, design: .monospaced))
        }
        .font(.footnote)
    }

    private func refresh() {
        exportCookies { cookies in
            session = InstagramBridge.session(from: cookies)
            loaded = true
        }
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { showToast("Instagram app not installed") }
        }
    }

    private func copy(_ text: String, _ message: String) {
        UIPasteboard.general.string = text
        showToast(message)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
