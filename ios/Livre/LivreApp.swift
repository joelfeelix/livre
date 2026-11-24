import SwiftUI
import WebKit
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

/// Grupo compartilhado entre o app e o widget.
let appGroup = "group.com.livreapp.livre"

@main
struct LivreApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea()
                .background(Color(red: 15/255, green: 20/255, blue: 25/255))
                .preferredColorScheme(.dark)
        }
    }
}

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ vc: WebViewController, context: Context) {}
}

/// Serve os arquivos do app web (pasta "web" do bundle) em livre://app/...
/// Uma origem fixa garante que o localStorage seja mantido entre aberturas.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "livre"
    private let root = Bundle.main.resourceURL!.appendingPathComponent("web")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst()))
        guard file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!

    /// Cópia de segurança dos dados em Documentos/livre.json (além do localStorage).
    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("livre.json")
    }

    /// Cópia das fotos do Mapa dos Sonhos em Documentos/photos.
    private var photosDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
    }

    private func savedPhotosJSON() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)) ?? []
        var dict: [String: String] = [:]
        for f in files where f.pathExtension == "jpg" {
            if let d = try? Data(contentsOf: f) {
                dict[f.deletingPathExtension().lastPathComponent] = "data:image/jpeg;base64," + d.base64EncodedString()
            }
        }
        guard let json = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
        return String(data: json, encoding: .utf8) ?? "{}"
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = UIColor(red: 15/255, green: 20/255, blue: 25/255, alpha: 1)
        view.backgroundColor = bg

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.websiteDataStore = .default()

        let ucc = WKUserContentController()
        ucc.add(LeakAvoider(self), name: "store")
        ucc.add(LeakAvoider(self), name: "share")
        ucc.add(LeakAvoider(self), name: "reminders")
        ucc.add(LeakAvoider(self), name: "widget")
        ucc.add(LeakAvoider(self), name: "photo")
        ucc.add(LeakAvoider(self), name: "ai")
        let saved = (try? String(contentsOf: storeURL, encoding: .utf8)) ?? "null"
        let js = "window.__LIVRE_NATIVE = \(saved.isEmpty ? "null" : saved); window.__LIVRE_PHOTOS = \(savedPhotosJSON());"
        ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: URL(string: "\(BundleSchemeHandler.scheme)://app/index.html")!))
    }

    // MARK: Mensagens do JavaScript
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "store":
            if let json = message.body as? String { try? json.write(to: storeURL, atomically: true, encoding: .utf8) }
        case "share":
            guard let body = message.body as? [String: Any],
                  let name = body["name"] as? String, let content = body["content"] as? String else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? content.write(to: tmp, atomically: true, encoding: .utf8)
            let ac = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
            ac.popoverPresentationController?.sourceView = view
            present(ac, animated: true)
        case "reminders":
            guard let body = message.body as? [String: Any] else { return }
            scheduleReminders(body)
        case "ai":
            guard let body = message.body as? [String: Any] else { return }
            handleAI(body)
        case "photo":
            guard let body = message.body as? [String: Any], let id = body["id"] as? String,
                  id.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return }
            let file = photosDir.appendingPathComponent(id + ".jpg")
            if let dataURL = body["data"] as? String, let comma = dataURL.firstIndex(of: ","),
               let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) {
                try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        case "widget":
            guard let body = message.body as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: body) else { return }
            let defaults = UserDefaults(suiteName: appGroup)
            if defaults?.data(forKey: "widget") != data {
                defaults?.set(data, forKey: "widget")
                WidgetCenter.shared.reloadAllTimelines()
            }
        default: break
        }
    }

    // MARK: IA da Apple (Coach)
    private var aiCoach: AnyObject?

    private func js(_ code: String) { webView.evaluateJavaScript(code) }
    private func jsonString(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
    }

    private func handleAI(_ body: [String: Any]) {
        let type = body["type"] as? String ?? ""
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let coach: AICoach
            if let c = aiCoach as? AICoach { coach = c } else { coach = AICoach(); aiCoach = coach }
            switch type {
            case "status":
                js("window.aiStatus && aiStatus(\(jsonString(coach.status())))")
            case "start":
                coach.start(context: body["context"] as? String ?? "")
            case "reset":
                coach.reset()
            case "send":
                guard let id = body["id"] as? String, let prompt = body["prompt"] as? String else { return }
                let idJS = jsonString(id)
                coach.send(prompt: prompt, onText: { [weak self] text in
                    guard let self else { return }
                    self.js("window.aiChunk && aiChunk(\(idJS), \(self.jsonString(text)))")
                }, done: { [weak self] err in
                    guard let self else { return }
                    self.js("window.aiDone && aiDone(\(idJS), \(err.map { self.jsonString($0) } ?? "null"))")
                })
            default: break
            }
            return
        }
        #endif
        if type == "status" { js("window.aiStatus && aiStatus(\"unsupportedOS\")") }
    }

    // MARK: Lembretes de afirmações
    private func scheduleReminders(_ body: [String: Any]) {
        let count = (body["count"] as? Int) ?? 0
        let start = (body["start"] as? Int) ?? 8
        let end = max((body["end"] as? Int) ?? 21, start)
        let texts = (body["texts"] as? [String]) ?? []
        let ask = (body["ask"] as? Bool) ?? false
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<24).map { "aff-\($0)" })
        guard count > 0, !texts.isEmpty else { return }

        let schedule = { [weak self] in
            let span = (end - start) * 60
            for i in 0..<min(count, 24) {
                let minute = start * 60 + (count == 1 ? span / 2 : span * i / (count - 1))
                let content = UNMutableNotificationContent()
                content.title = "✨ Lembre-se"
                content.body = texts[i % texts.count]
                content.sound = .default
                var dc = DateComponents()
                dc.hour = minute / 60
                dc.minute = minute % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                center.add(UNNotificationRequest(identifier: "aff-\(i)", content: content, trigger: trigger))
            }
            if ask { DispatchQueue.main.async { self?.webView.evaluateJavaScript("window.remindersStatus && remindersStatus(true)") } }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { schedule() }
                    else { DispatchQueue.main.async { self.webView.evaluateJavaScript("window.remindersStatus && remindersStatus(false)") } }
                }
            default:
                DispatchQueue.main.async { self.webView.evaluateJavaScript("window.remindersStatus && remindersStatus(false)") }
            }
        }
    }

    // MARK: Links externos (telefone, sites) abrem fora do app
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == BundleSchemeHandler.scheme || url.scheme == "about" || url.scheme == "blob" {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // MARK: alert() e confirm()
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "Confirmar", style: .destructive) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

/// Evita ciclo de referência entre WKUserContentController e o controller.
final class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
