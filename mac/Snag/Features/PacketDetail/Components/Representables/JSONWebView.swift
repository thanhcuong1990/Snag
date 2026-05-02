import SwiftUI
import WebKit

struct JSONWebView: NSViewRepresentable {
    let jsonString: String
    @Environment(\.colorScheme) var colorScheme

    private struct TemplateBundle {
        let template: String
        let baseURL: URL
    }

    private static let templateBundle: TemplateBundle? = {
        let htmlPath = Bundle.main.path(forResource: "jsonviewer", ofType: "html", inDirectory: "jsonViewer") ??
                       Bundle.main.path(forResource: "jsonviewer", ofType: "html")
        guard let path = htmlPath, let template = try? String(contentsOfFile: path) else { return nil }
        return TemplateBundle(template: template, baseURL: URL(fileURLWithPath: path).deletingLastPathComponent())
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = SearchableWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor().cgColor
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // Update layer background color for theme changes
        nsView.layer?.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor().cgColor

        if context.coordinator.isLoaded {
            // Page is already loaded; re-render via JS instead of reloading HTML.
            context.coordinator.renderJSON(nsView)
        } else {
            loadContent(nsView)
        }
    }

    private func loadContent(_ webView: WKWebView) {
        guard let bundle = Self.templateBundle else { return }

        let base64 = jsonString.data(using: .utf8)?.base64EncodedString() ?? ""
        let themeScript = colorScheme == .dark ? "changeThemeToDark()" : "changeThemeToLight()"

        let finalHtml = bundle.template.replacingOccurrences(of: "/* INJECTED_SCRIPT */", with: """
            \(themeScript);
            renderJSONBase64('\(base64)');
        """)

        webView.loadHTMLString(finalHtml, baseURL: bundle.baseURL)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: JSONWebView
        var isLoaded = false
        
        init(_ parent: JSONWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderJSON(webView)
        }
        
        func renderJSON(_ webView: WKWebView) {
            guard isLoaded else { return }
            
            let base64 = parent.jsonString.data(using: .utf8)?.base64EncodedString() ?? ""
            
            let themeScript = parent.colorScheme == .dark ? "changeThemeToDark()" : "changeThemeToLight()"
            
            let jsCode = """
                \(themeScript);
                renderJSONBase64('\(base64)');
                document.body.style.backgroundColor = 'transparent';
            """
            
            webView.evaluateJavaScript(jsCode)
        }
    }
}

class SearchableWebView: WKWebView {
    @objc func performFindPanelAction(_ sender: Any?) {
        // Trigger the custom JS search UI
        self.evaluateJavaScript("searchManager.show()")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}
