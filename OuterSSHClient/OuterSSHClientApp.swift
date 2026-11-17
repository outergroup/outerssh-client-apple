import SwiftUI
import WebKit

@main
struct OuterSSHClientApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("OuterSSH Client", id: "browser") {
            ContentView(browser: appDelegate.browser)
        }
    }
    #else
    @State private var browser = SSHBrowser()

    var body: some Scene {
        WindowGroup {
            ContentView(browser: browser)
        }
    }
    #endif
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    let browser = SSHBrowser()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        browser.shutDown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
#endif

struct ContentView: View {
    let browser: SSHBrowser
    @State private var port = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Home", systemImage: "house") { browser.goHome() }
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onSubmit { browser.openPort(port) }
                Spacer()
            }
            .padding(8)
            if let status = browser.status {
                Text(status)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.yellow.opacity(0.3))
            }
            if let webView = browser.webView {
                WebView(webView: webView)
            } else {
                Spacer()
            }
        }
    }
}

#if os(macOS)
struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#else
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif
