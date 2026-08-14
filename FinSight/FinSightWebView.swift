import SwiftUI
import WebKit

#if os(macOS)
import AppKit
typealias PlatformViewController = NSViewController
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformColor = UIColor
#endif

// MARK: - SwiftUI wrapper

/// Hosts the FinSight dashboard (a single self-contained `index.html` shipped in the
/// app bundle) in a WKWebView. Nothing is fetched from the network — the page carries
/// React, Babel and pdf.js inline — so the app works fully offline.
struct FinSightWebView {
    typealias Controller = FinSightWebController
}

#if os(macOS)
extension FinSightWebView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> Controller { Controller() }
    func updateNSViewController(_ controller: Controller, context: Context) {}
}
#else
extension FinSightWebView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
}
#endif

// MARK: - Web controller

final class FinSightWebController: PlatformViewController {

    private(set) var webView: WKWebView!

    override func loadView() {
        let content = WKUserContentController()
        content.add(self, name: Self.saveMessageName)
        content.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.websiteDataStore = .default()          // localStorage persists in the app container
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = PlatformColor(red: 10 / 255, green: 11 / 255, blue: 14 / 255, alpha: 1)

        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = webView.underPageBackgroundColor
        webView.scrollView.backgroundColor = webView.underPageBackgroundColor
        webView.scrollView.bounces = false            // the dashboard manages its own scrolling
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #endif

        self.webView = webView
        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else {
            assertionFailure("index.html is missing from the app bundle — check the Copy Bundle Resources phase.")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    deinit {
        // The content controller retains its message handlers — break the cycle.
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.saveMessageName)
    }
}

// MARK: - Navigation

extension FinSightWebController: WKNavigationDelegate {

    /// The dashboard is entirely local, so the only navigation this web view should ever perform
    /// is to the bundled file. A tapped link to the web opens in the user's real browser; a
    /// remote address the page tried to navigate to *itself* is refused outright, because the
    /// only way that happens is something going wrong — and a remote page loaded into the app's
    /// own chrome, with no address bar to contradict it, is a convincing place to ask for a PIN.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if scheme == "http" || scheme == "https" {
            if navigationAction.navigationType == .linkActivated { openExternally(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(scheme == "file" || scheme == "about" ? .allow : .cancel)
    }

    private func openExternally(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Exports (Backup / CSV / Markdown)

extension FinSightWebController: WKScriptMessageHandler {

    fileprivate static let saveMessageName = "finsightSave"

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.saveMessageName,
              let body = message.body as? [String: Any],
              let name = body["name"] as? String,
              let base64 = body["data"] as? String,
              let data = Data(base64Encoded: base64) else { return }
        save(data: data, suggestedName: name)
    }

    #if os(macOS)
    private func save(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }
    #else
    private func save(data: Data, suggestedName: String) {
        // The name comes from a `download` attribute in the web layer, so it is not ours to
        // trust: "../../Library/Preferences/x.plist" would append cleanly and write outside the
        // temporary directory. Take the last path component only, and fall back if that is empty.
        let leaf = (suggestedName as NSString).lastPathComponent
        let safeName = leaf.isEmpty || leaf == "." || leaf == ".." ? "finsight-export" : leaf
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            present(message: "Couldn't prepare \(safeName) for export.")
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX,
                                                                 y: view.bounds.midY,
                                                                 width: 1, height: 1)
        present(share, animated: true)
    }
    #endif

    /// Intercepts the dashboard's `<a download>` exports and hands the bytes to the host
    /// app, which then shows a real save panel / share sheet. Without this, blob downloads
    /// inside a WKWebView go nowhere.
    fileprivate static let bridgeScript = """
    (function () {
      if (window.__finsightNativeBridge) return;
      window.__finsightNativeBridge = true;

      var blobs = Object.create(null);
      var makeURL = URL.createObjectURL.bind(URL);
      var dropURL = URL.revokeObjectURL.bind(URL);
      URL.createObjectURL = function (obj) {
        var url = makeURL(obj);
        if (obj instanceof Blob) blobs[url] = obj;
        return url;
      };
      URL.revokeObjectURL = function (url) { delete blobs[url]; return dropURL(url); };

      document.addEventListener('click', function (e) {
        var anchor = e.target && e.target.closest ? e.target.closest('a[download]') : null;
        if (!anchor) return;
        var blob = blobs[anchor.href || ''];
        if (!blob) return;
        e.preventDefault();
        e.stopPropagation();
        var name = anchor.getAttribute('download') || 'finsight-export';
        var reader = new FileReader();
        reader.onload = function () {
          var result = String(reader.result);
          var comma = result.indexOf(',');
          window.webkit.messageHandlers.finsightSave.postMessage({
            name: name,
            data: comma >= 0 ? result.slice(comma + 1) : ''
          });
        };
        reader.readAsDataURL(blob);
      }, true);
    })();
    """
}

// MARK: - alert / confirm / prompt
//
// WKWebView does nothing with these unless the host implements them, and FinSight uses
// all three (setting an account value, wiping data, import warnings).

extension FinSightWebController: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, navigationAction.targetFrame == nil {
            openExternally(url)
        }
        return nil
    }

    #if os(macOS)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        runModal(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        runModal(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = makeAlert(prompt)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        runModal(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    private func makeAlert(_ text: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "FinSight"
        alert.informativeText = text
        return alert
    }

    private func runModal(_ alert: NSAlert, then handle: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    #else

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "FinSight", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "FinSight", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "FinSight", message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func present(message: String) {
        let alert = UIAlertController(title: "FinSight", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    #endif
}
