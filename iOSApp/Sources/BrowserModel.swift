import Foundation
import Combine
import UIKit
import WebKit

/// Owns the WKWebView. Changing the profile / proxy / data store rebuilds the web view
/// so the new user script, user agent, proxy and cookies take effect from the next load.
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var webView: WKWebView
    /// Bumped every time the web view is rebuilt so SwiftUI swaps the UIView.
    @Published private(set) var generation: Int = 0

    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var isSecure = false
    @Published private(set) var proxyActive = false
    /// Set when a page tries to open an `sms:` link (Google's send-to-verify). The UI explains the
    /// dead end instead of silently bouncing to Messages.
    @Published var smsIntent: SMSIntent?

    /// Fired after each committed top-level navigation finishes (used to snapshot cookies).
    var onNavigationFinished: ((URL?) -> Void)?

    private(set) var isConfigured = false
    private(set) var currentProfile: FingerprintProfile?
    private var observers: [NSKeyValueObservation] = []

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
    }

    // MARK: Configuration

    func apply(profile: FingerprintProfile, proxy: ProxyConfig?, privateMode: Bool, keepURL: Bool = true) {
        let previousURL = (isConfigured && keepURL) ? webView.url : nil

        let config = WKWebViewConfiguration()
        let store: WKWebsiteDataStore = privateMode ? .nonPersistent() : .default()
        ProxyConfig.apply(proxy, to: store)
        proxyActive = proxy != nil && ProxyConfig.isSupported
        config.websiteDataStore = store
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = profile.isDesktopLike ? .desktop : .mobile

        let controller = WKUserContentController()
        let script = WKUserScript(
            source: SpoofScript.source(for: profile),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(script)
        config.userContentController = controller

        let newView = WKWebView(frame: .zero, configuration: config)
        newView.customUserAgent = profile.spoofNavigator ? profile.userAgent : nil
        newView.allowsBackForwardNavigationGestures = true
        newView.allowsLinkPreview = false
        newView.navigationDelegate = self
        newView.uiDelegate = self
        newView.scrollView.contentInsetAdjustmentBehavior = .always

        observers.removeAll()
        webView = newView
        currentProfile = profile
        observe(newView)
        isConfigured = true
        generation += 1

        canGoBack = false
        canGoForward = false
        progress = 0
        isLoading = false

        if let url = previousURL {
            newView.load(spoofedRequest(for: url))
        }
    }

    private func observe(_ view: WKWebView) {
        observers = [
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in
                self?.progress = v.estimatedProgress
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] v, _ in
                self?.isLoading = v.isLoading
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] v, _ in
                self?.canGoBack = v.canGoBack
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] v, _ in
                self?.canGoForward = v.canGoForward
            },
            view.observe(\.url, options: [.new]) { [weak self] v, _ in
                self?.currentURL = v.url
                self?.isSecure = v.hasOnlySecureContent
            },
            view.observe(\.title, options: [.new]) { [weak self] v, _ in
                self?.pageTitle = v.title ?? ""
            }
        ]
    }

    // MARK: Navigation

    /// Builds a request carrying the identity's Accept-Language / Sec-CH-UA headers.
    private func spoofedRequest(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if let p = currentProfile, p.spoofNavigator, p.spoofHeaders {
            for (k, v) in p.spoofedRequestHeaders { req.setValue(v, forHTTPHeaderField: k) }
        }
        return req
    }

    private func needsHeaderRewrite(_ request: URLRequest) -> Bool {
        guard let p = currentProfile, p.spoofNavigator, p.spoofHeaders,
              (request.httpMethod ?? "GET").uppercased() == "GET",
              let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let want = p.spoofedRequestHeaders
        for (k, v) in want where request.value(forHTTPHeaderField: k) != v { return true }
        return false
    }

    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var target: URL?
        if let u = URL(string: text), let scheme = u.scheme?.lowercased(),
           ["http", "https"].contains(scheme), u.host != nil {
            target = u
        } else if !text.contains(" "), text.contains("."),
                  let u = URL(string: "https://" + text), u.host != nil {
            target = u
        } else {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let q = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            target = URL(string: "https://www.google.com/search?q=" + q)
        }
        if let url = target {
            webView.load(spoofedRequest(for: url))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    /// Hand a non-web URL (sms:, mailto:, app links) to the system after all.
    func openExternally(_ url: URL?) {
        guard let url = url else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Website data / cookies

    /// Wipes cookies, cache and storage for the web view's current data store.
    func clearWebsiteData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async(execute: completion)
        }
    }

    func exportCookies(completion: @escaping ([CookieRecord]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let records = cookies.map(CookieRecord.init(cookie:))
            DispatchQueue.main.async { completion(records) }
        }
    }

    /// Writes cookie records into the current data store, then calls back on main.
    func restoreCookies(_ records: [CookieRecord], completion: @escaping (Int) -> Void) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = records.compactMap { $0.makeHTTPCookie() }
        guard !cookies.isEmpty else { completion(0); return }
        let group = DispatchGroup()
        for c in cookies {
            group.enter()
            cookieStore.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main) { completion(cookies.count) }
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let request = navigationAction.request
        if let url = request.url,
           let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
            // `sms:` is Google's "send an SMS from this phone to verify" step. A rented number can't
            // send, so surface it in-app (with a way out) rather than opening Messages.
            if scheme == "sms", let intent = SMSIntent.parse(url) {
                smsIntent = intent
            } else {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        // Re-issue top-level GET navigations with the identity's headers (Sessions X does this
        // with onBeforeSendHeaders; WKWebView only lets us set headers on the request we start).
        let isTopLevel = navigationAction.targetFrame?.isMainFrame ?? true
        let type = navigationAction.navigationType
        if isTopLevel, type != .backForward, type != .reload, needsHeaderRewrite(request), let url = request.url {
            decisionHandler(.cancel)
            webView.load(spoofedRequest(for: url))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentURL = webView.url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url
        pageTitle = webView.title ?? ""
        HeavenzyBridge.syncSMSBrand(for: webView.url)   // SMS panel rents a number for *this* site
        onNavigationFinished?(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    private func handle(error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // frame load interrupted
        let escaped = nsError.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let proxyHint = proxyActive ? "<p style=\"color:#999;font-size:13px\">A proxy is active for this session — check its host, port and credentials.</p>" : ""
        let html = """
        <!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
        <body style="font-family:-apple-system,sans-serif;padding:40px 24px;color:#333;background:#fafafa">
        <h2 style="margin:0 0 8px">Page failed to load</h2>
        <p style="color:#666">\(escaped)</p>\(proxyHint)</body>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - WKUIDelegate

extension BrowserModel: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(spoofedRequest(for: url))
        }
        return nil
    }

    // Sessions X answers every permission prompt with "allow" (setPermissionRequestHandler).
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView,
                 requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        if !TopViewController.present(alert) { completionHandler() }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        if !TopViewController.present(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text ?? "")
        })
        if !TopViewController.present(alert) { completionHandler(nil) }
    }
}

// MARK: - Presenting UIKit controllers from SwiftUI land

enum TopViewController {
    static func current() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    @discardableResult
    static func present(_ controller: UIViewController) -> Bool {
        guard let top = current() else { return false }
        if let pop = controller.popoverPresentationController, pop.sourceView == nil {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
        return true
    }

    /// Shares a file via the system share sheet.
    static func share(fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        present(activity)
    }
}
