import UIKit
import WebKit

final class WebViewController: UIViewController, WKScriptMessageHandler {
    private var web: WKWebView!
    private var server: LocalServer?

    /// 本地存储镜像文件（Documents 目录），保证数据不会因为 WebView 缓存被清而丢失
    private var store: [String: String] = [:]

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("fuel_store.json")
    }

    private func loadStore() {
        if let d = try? Data(contentsOf: storeURL),
           let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] {
            store = obj
        }
    }

    private func persistStore() {
        guard let d = try? JSONSerialization.data(withJSONObject: store, options: []) else { return }
        try? d.write(to: storeURL, options: [.atomic])
    }

    private func jsSeedObject() -> String {
        if let d = try? JSONSerialization.data(withJSONObject: store, options: []),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    private var injectedScript: String {
        let seed = jsSeedObject()
        return """
        window.AndroidBridge = {
          saveText: function (name, content) {
            try { window.webkit.messageHandlers.fuelSave.postMessage({ name: name, content: content }); } catch (e) {}
          }
        };
        (function () {
          var SEED = \(seed);
          try {
            for (var k in SEED) { if (Object.prototype.hasOwnProperty.call(SEED, k)) { try { localStorage.setItem(k, SEED[k]); } catch (e) {} } }
          } catch (e) {}
          try {
            var origSet = localStorage.setItem.bind(localStorage);
            localStorage.setItem = function (k, v) {
              try { origSet(k, v); } catch (e) {}
              try { window.webkit.messageHandlers.fuelPersist.postMessage({ k: String(k), v: String(v) }); } catch (e) {}
            };
            var origDel = localStorage.removeItem.bind(localStorage);
            localStorage.removeItem = function (k) {
              try { origDel(k); } catch (e) {}
              try { window.webkit.messageHandlers.fuelPersist.postMessage({ k: String(k), v: null }); } catch (e) {}
            };
            var origClear = localStorage.clear.bind(localStorage);
            localStorage.clear = function () {
              try { origClear(); } catch (e) {}
              try { window.webkit.messageHandlers.fuelPersist.postMessage({ clear: true }); } catch (e) {}
            };
          } catch (e) {}
        })();
        """
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        loadStore()

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.userContentController.addUserScript(
            WKUserScript(source: injectedScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "fuelSave")
        cfg.userContentController.add(self, name: "fuelPersist")

        let webFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        web = WKWebView(frame: webFrame, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.allowsBackForwardNavigationGestures = false
        view.addSubview(web)

        let root = Bundle.main.url(forResource: "www", withExtension: nil)
            ?? Bundle.main.bundleURL
        let s = LocalServer(root: root)
        server = s
        s.onReady = { [weak self] port in
            guard let self = self, port > 0 else { return }
            let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
            self.web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        s.start()
    }

    override var prefersStatusBarHidden: Bool { false }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "fuelPersist" {
            guard let body = message.body as? [String: Any] else { return }
            if let clear = body["clear"] as? Bool, clear {
                store.removeAll()
                persistStore()
                return
            }
            guard let k = body["k"] as? String else { return }
            if let v = body["v"] as? String {
                store[k] = v
            } else {
                store.removeValue(forKey: k)
            }
            persistStore()
            return
        }

        guard message.name == "fuelSave",
              let body = message.body as? [String: Any],
              let content = body["content"] as? String else { return }
        var name = (body["name"] as? String) ?? "export.txt"
        name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = dir.appendingPathComponent(name)
        do {
            try content.data(using: .utf8)?.write(to: fileURL)
        } catch {
            return
        }
        let ac = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(ac, animated: true, completion: nil)
    }
}
