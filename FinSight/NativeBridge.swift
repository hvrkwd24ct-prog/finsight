import UIKit
import WebKit

/// The one channel between the dashboard and the phone.
///
/// Everything goes through a single message handler with an `action` field rather than a handler
/// per feature, so the surface the web layer can reach is one switch statement you can read in
/// full. The page is bundled with the app and is the only thing that can post here, but it is
/// still the layer that opens files somebody else made, so it is treated as an untrusted caller:
/// nothing here takes a path, a URL or anything else it would then act on blindly.
enum NativeBridge {

    static let name = "finsight"

    @MainActor
    static func handle(action: String, body: [String: Any], host: WebHostController) {
        switch action {

        case "ready":
            host.webAppBecameReady()

        // Downloads inside a WKWebView go nowhere, so the page's exports come here instead and
        // leave through the share sheet — into Files, iCloud, Mail, AirDrop, anywhere.
        case "save":
            guard let name = body["name"] as? String,
                  let base64 = body["data"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            host.export(data: data, suggestedName: name)

        case "import":
            host.importBackup()

        // A phone can tell you a thing landed without you having to look at it.
        case "haptic":
            haptic(body["kind"] as? String ?? "light")

        case "setLock":
            let on = body["on"] as? Bool ?? false
            host.lock?.setEnabled(on)

        default:
            break
        }
    }

    private static func haptic(_ kind: String) {
        switch kind {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error":   UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "select":  UISelectionFeedbackGenerator().selectionChanged()
        case "medium":  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default:        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Injected at document start, before the dashboard's own script runs.
    ///
    /// Two jobs. It publishes `window.__finsightNative` so the page can feature-detect the phone
    /// and ask it for things — and the page is written so that everything here is optional, which
    /// is what keeps the same `index.html` working when you open it in a browser on a laptop.
    ///
    /// And it catches the page's `<a download>` exports. Those are how the dashboard has always
    /// saved a backup, and inside a web view they silently do nothing, so the blob is intercepted
    /// on the way out and handed to the share sheet instead.
    static let script = """
    (function () {
      if (window.__finsightNative) return;

      var post = function (msg) {
        try { window.webkit.messageHandlers.finsight.postMessage(msg); } catch (e) {}
      };

      var api = {
        platform: 'ios',
        caps: {},
        ready: function () { post({action: 'ready'}); },
        haptic: function (kind) { post({action: 'haptic', kind: kind || 'light'}); },
        pickBackup: function () { post({action: 'import'}); },
        setLock: function (on) { post({action: 'setLock', on: !!on}); },
        // filled in by the host once the page says it is ready
        capabilities: function (c) {
          api.caps = c || {};
          window.dispatchEvent(new CustomEvent('finsight:capabilities', {detail: api.caps}));
        },
        // a Home Screen quick action, delivered once the page can act on it
        action: function (name) {
          window.dispatchEvent(new CustomEvent('finsight:action', {detail: name}));
        },
        // a backup chosen in Files, handed over as text
        restore: function (text) {
          window.dispatchEvent(new CustomEvent('finsight:restore', {detail: text}));
        }
      };
      window.__finsightNative = api;

      // <a download> exports -> share sheet
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
          post({action: 'save', name: name, data: comma >= 0 ? result.slice(comma + 1) : ''});
        };
        reader.readAsDataURL(blob);
      }, true);
    })();
    """
}
