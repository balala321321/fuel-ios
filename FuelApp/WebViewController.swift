import UIKit
import WebKit

final class WebViewController: UIViewController, WKScriptMessageHandler {
    private var web: WKWebView!
    private var server: LocalServer?

    private static let bridgeScript = """
    window.AndroidBridge = {
      saveText: function (name, content) {
        try { window.webkit.messageHandlers.fuelSave.postMessage({ name: name, content: content }); } catch (e) {}
      }
    };
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.userContentController.addUserScript(
            WKUserScript(source: WebViewController.bridgeScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "fuelSave")

        let webFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        web = WKWebView(frame: webFrame, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.allowsBackForwardNavigationGestures = true
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