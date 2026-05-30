
import SwiftUI
import WebKit

struct WebScreenView: UIViewRepresentable {
    let htmlFile: String
    let onNavigate: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // permite cargar archivos locales con acceso al bundle
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false                    // evita que el bounce arrastre los elementos fixed
        webView.scrollView.alwaysBounceVertical = false        // refuerza: sin bounce vertical
        webView.scrollView.alwaysBounceHorizontal = false      //sin bounce horizontal
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        
        // permite ("pinch-zoom") nativo en el mapa
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.isOpaque = true

        loadHTML(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // solo recarga si cambio el archivo
        if context.coordinator.currentFile != htmlFile {
            context.coordinator.currentFile = htmlFile
            loadHTML(in: webView)
        }
    }

    private func loadHTML(in webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: htmlFile, withExtension: "html") else {
            print("❌ No se encontró: \(htmlFile).html en el Bundle")
            return
        }
        // allowingReadAccessTo: permite que el webview lea recursos del mismo directorio
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: Coordinator (intercepta URLs de navegacion)
    class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigate: (String) -> Void
        var currentFile: String = ""

        init(onNavigate: @escaping (String) -> Void) {
            self.onNavigate = onNavigate
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Interceptamos el esquema app://navigate/<pantalla>
            if url.scheme == "app" && url.host == "navigate" {
                let destination = url.pathComponents.dropFirst().joined(separator: "/")
                print("➡️ Navegando a: \(destination)")
                DispatchQueue.main.async {
                    self.onNavigate(destination)
                }
                decisionHandler(.cancel)
                return
            }

            // MARK: Bloquear links externos (como terminos de servicio href="#")
            if url.scheme == "http" || url.scheme == "https" {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Cargó: \(webView.url?.lastPathComponent ?? "?")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print(" Error cargando página: \(error.localizedDescription)")
        }
    }
}
