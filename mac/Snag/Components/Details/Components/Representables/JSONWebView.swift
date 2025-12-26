import SwiftUI
import WebKit

struct JSONWebView: NSViewRepresentable {
    let jsonString: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor().cgColor
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        
        // Update layer background color for theme changes
        nsView.effectiveAppearance.performAsCurrentDrawingAppearance {
            nsView.layer?.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor().cgColor
        }
        
        if nsView.url == nil {
            let htmlPath = Bundle.main.path(forResource: "jsonviewer", ofType: "html", inDirectory: "jsonViewer") ??
                           Bundle.main.path(forResource: "jsonviewer", ofType: "html")
            
            guard let path = htmlPath else {
                return
            }
            
            let fileURL = URL(fileURLWithPath: path)
            nsView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            context.coordinator.renderJSON(nsView)
        }
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
