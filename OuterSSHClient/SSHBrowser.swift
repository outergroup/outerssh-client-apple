import Foundation
import Network
import Observation
import OuterSSH
import WebKit

/// Connects to the configured server through OuterSSH and shows its pages in a web view.
@Observable
final class SSHBrowser {
    private(set) var webView: WKWebView?
    private(set) var status: String?

    private enum Tag: UInt64 {
        case proxyStarted = 1, homepage, destroyed
    }

    @ObservationIgnored private let events = DispatchSource.makeUserDataOrSource(queue: .main)
    @ObservationIgnored private var eventQueue: OpaquePointer?
    @ObservationIgnored private var pool: OpaquePointer?
    @ObservationIgnored private var proxy: OpaquePointer?
    @ObservationIgnored private var pendingDestroys = 0
    @ObservationIgnored private var shutdownCompletion: (() -> Void)?

    init() {
        events.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drainEvents() }
        }
        events.activate()
        guard let source = events as? DispatchSource,
              let eventQueue = outerssh_event_queue_create(source) else {
            status = "Couldn't create the OuterSSH event queue."
            return
        }
        self.eventQueue = eventQueue
        guard let privateKey = Self.privateKey() else {
            status = "Couldn't read the private key. Check Configuration.swift."
            return
        }
        var error = OuterSSHError()
        pool = Self.createPool(eventQueue: eventQueue, privateKey: privateKey, error: &error)
        guard let pool else {
            status = Self.describe(error)
            return
        }
        var proxyConfiguration = OuterSSHHTTPProxyServerConfiguration()
        proxyConfiguration.authentication = OUTERSSH_PROXY_AUTHENTICATION_PASSWORD
        proxyConfiguration.rewrite_loopback_addresses = true
        proxy = outerssh_http_proxy_server_create(pool, &proxyConfiguration, &error)
        guard let proxy else {
            status = Self.describe(error)
            return
        }
        if !outerssh_http_proxy_server_start(proxy, 0, Tag.proxyStarted.rawValue) {
            status = "Couldn't start the HTTP proxy."
        }
    }

    func goHome() {
        guard let pool, webView != nil else { return }
        status = nil
        if !outerssh_session_pool_get_homepage(pool, Tag.homepage.rawValue) {
            status = "Couldn't ask the server for its homepage."
        }
    }

    func openPort(_ text: String) {
        guard let port = UInt16(text), port > 0, let url = ProxyAddress.url(forPort: port) else {
            status = "Enter a port from 1 to 65535."
            return
        }
        status = nil
        webView?.load(URLRequest(url: url))
    }

    /// Destroys the proxy and the pool, then the event queue once both report OUTERSSH_EVENT_DESTROYED.
    func shutDown(completion: @escaping () -> Void) {
        guard shutdownCompletion == nil else { return }
        shutdownCompletion = completion
        if let proxy, outerssh_http_proxy_server_destroy(proxy, Tag.destroyed.rawValue) {
            pendingDestroys += 1
        }
        if let pool, outerssh_session_pool_destroy(pool, Tag.destroyed.rawValue) {
            pendingDestroys += 1
        }
        proxy = nil
        pool = nil
        if pendingDestroys == 0 {
            finishShutdown()
        }
    }

    private func finishShutdown() {
        events.cancel()
        let eventQueue = eventQueue
        self.eventQueue = nil
        DispatchQueue.main.async { [shutdownCompletion] in
            outerssh_event_queue_destroy(eventQueue)
            shutdownCompletion?()
        }
    }

    private func drainEvents() {
        let capacity = 8
        let batch = UnsafeMutablePointer<OuterSSHEvent>.allocate(capacity: capacity)
        defer { batch.deallocate() }
        while let eventQueue, case let count = outerssh_event_queue_poll(eventQueue, batch, capacity), count > 0 {
            for index in 0..<count {
                handle(batch[index])
            }
        }
    }

    private func handle(_ event: OuterSSHEvent) {
        switch event.type {
        case OUTERSSH_EVENT_PROXY_STARTED:
            proxyStarted(event)
        case OUTERSSH_EVENT_HOMEPAGE_RECEIVED:
            homepageReceived(event)
        case OUTERSSH_EVENT_HOST_KEY_VALIDATION:
            guard let pool = event.pool else { return }
            let question = event.host_key_validation
            let fingerprint = Self.string(question.fingerprint, question.fingerprint_length)
            if Configuration.trustedHostKeyFingerprint.isEmpty {
                print("Trusting host key \(fingerprint). Paste it into Configuration.trustedHostKeyFingerprint to pin it.")
                outerssh_session_pool_answer_host_key(pool, question.question, true)
            } else {
                status = "The server's host key \(fingerprint) doesn't match Configuration.trustedHostKeyFingerprint."
                outerssh_session_pool_answer_host_key(pool, question.question, false)
            }
        case OUTERSSH_EVENT_SUDO_PASSWORD_NEEDED:
            guard let pool = event.pool else { return }
            outerssh_session_pool_decline_sudo_password(pool, event.sudo_password_needed.question)
        case OUTERSSH_EVENT_HELPER_BINARY_NEEDED:
            provideHelper(event)
        case OUTERSSH_EVENT_CONNECTION_FAILED:
            let failure = event.connection_failed
            let destination = failure.socket_path_length > 0
                ? Self.string(failure.socket_path, failure.socket_path_length)
                : "\(Self.string(failure.host, failure.host_length)):\(failure.port)"
            status = "Couldn't connect to \(destination): \(Self.describe(failure.error))"
        case OUTERSSH_EVENT_DESTROYED:
            pendingDestroys -= 1
            if pendingDestroys == 0, shutdownCompletion != nil {
                finishShutdown()
            }
        default:
            break
        }
    }

    /// Uploads the bundled helper that OuterSSH runs on the server to reach its Unix sockets.
    private func provideHelper(_ event: OuterSSHEvent) {
        guard let pool = event.pool else { return }
        let request = event.helper_binary_needed
        let platform = Self.string(request.platform, request.platform_length)
        let name = "outerssh-helper-\(platform).\(platform.hasPrefix("windows-") ? "tar.gz" : "gz")"
        let file = Bundle.main.resourceURL.map { open($0.appendingPathComponent(name).path, O_RDONLY | O_CLOEXEC) } ?? -1
        var info = stat()
        if file >= 0, fstat(file, &info) == 0 {
            outerssh_session_pool_provide_helper_binary(pool, request.question, file, 0, UInt64(info.st_size))
        } else {
            if file >= 0 {
                close(file)
            }
            print("Missing \(name) in the app's resources; this server's sockets need it.")
            outerssh_session_pool_decline_helper_binary(pool, request.question, OuterSSHError())
        }
    }

    private func proxyStarted(_ event: OuterSSHEvent) {
        let started = event.proxy_started
        guard started.error.domain == OUTERSSH_ERROR_NONE else {
            status = Self.describe(started.error)
            return
        }
        guard let port = NWEndpoint.Port(rawValue: started.listen_port) else { return }
        var proxyConfiguration = ProxyConfiguration(
            httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: port), tlsOptions: nil)
        proxyConfiguration.applyCredential(
            username: Self.string(started.username, started.username_length),
            password: Self.string(started.password, started.password_length))
        proxyConfiguration.allowFailover = false
        let dataStore = WKWebsiteDataStore.nonPersistent()
        dataStore.proxyConfigurations = [proxyConfiguration]
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Apple's WebKit sends localhost requests directly, bypassing the proxy. OuterSSH's
        // script rewrites localhost URLs that pages build in JavaScript to proxy aliases.
        if let url = Bundle.main.url(forResource: "LoopbackCompatibility", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        goHome()
    }

    private func homepageReceived(_ event: OuterSSHEvent) {
        let homepage = event.homepage_received
        guard homepage.error.domain == OUTERSSH_ERROR_NONE else {
            status = Self.describe(homepage.error)
            return
        }
        guard homepage.found else {
            status = "This server has no homepage. Type a port to open one of its web servers."
            return
        }
        let homepageURL = Self.string(homepage.url, homepage.url_length)
        guard let url = ProxyAddress.url(forHomepage: homepageURL) else {
            status = "This starter doesn't support the homepage \(homepageURL)."
            return
        }
        webView?.load(URLRequest(url: url))
    }

    private static func privateKey() -> [UInt8]? {
        if !Configuration.password.isEmpty {
            return []
        }
        if !Configuration.privateKeyText.isEmpty {
            return Array(Configuration.privateKeyText.utf8)
        }
        #if os(macOS)
        let path = NSString(string: Configuration.privateKeyPath).expandingTildeInPath
        return (try? Data(contentsOf: URL(fileURLWithPath: path))).map(Array.init)
        #else
        return nil
        #endif
    }

    private static func createPool(
        eventQueue: OpaquePointer, privateKey: [UInt8], error: inout OuterSSHError
    ) -> OpaquePointer? {
        Configuration.host.withCString { host in
        Configuration.username.withCString { username in
        Configuration.trustedHostKeyFingerprint.withCString { fingerprint in
        Configuration.privateKeyPassphrase.withCString { passphrase in
        Configuration.password.withCString { password in
        privateKey.withUnsafeBytes { key in
            var authentication = OuterSSHSessionAuthentication()
            if Configuration.password.isEmpty {
                authentication.kind = OUTERSSH_SESSION_AUTHENTICATION_PRIVATE_KEY
                authentication.private_key = key.baseAddress
                authentication.private_key_length = key.count
                if !Configuration.privateKeyPassphrase.isEmpty {
                    authentication.passphrase = passphrase
                    authentication.passphrase_length = strlen(passphrase)
                }
            } else {
                authentication.kind = OUTERSSH_SESSION_AUTHENTICATION_PASSWORD
                authentication.password = password
                authentication.password_length = strlen(password)
            }
            let fingerprintLength = strlen(fingerprint)
            var configuration = OuterSSHSessionPoolConfiguration(
                jump_host: nil,
                hostname: host, hostname_length: strlen(host),
                username: username, username_length: strlen(username),
                port: Configuration.port,
                authentication: authentication,
                ssh_agent_socket_path: nil, ssh_agent_socket_path_length: 0,
                trusted_host_key_fingerprint: fingerprintLength > 0 ? fingerprint : nil,
                trusted_host_key_fingerprint_length: fingerprintLength,
                additional_socket_allowlists: nil, additional_socket_allowlist_count: 0)
            return outerssh_session_pool_create(eventQueue, &configuration, &error)
        }}}}}}
    }

    private static func string(_ bytes: UnsafePointer<CChar>?, _ length: Int) -> String {
        String(decoding: UnsafeRawBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    private static func describe(_ error: OuterSSHError) -> String {
        var text = string(error.message, error.message_length)
        if error.ssh_error_message_length > 0 {
            text += ": " + string(error.ssh_error_message, error.ssh_error_message_length)
        }
        let systemError = String(cString: strerror(error.system_error_code))
        if error.system_error_code != 0, !text.contains(systemError) {
            text += ": " + systemError
        }
        return text
    }
}
