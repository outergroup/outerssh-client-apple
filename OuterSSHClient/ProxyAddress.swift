import Foundation
import OuterSSH

/// Converts server-side addresses into the special hosts OuterSSH's proxy understands.
enum ProxyAddress {
    static func unixSocketHost(_ path: String) -> String? {
        encode(path, capacity: Int(OUTERSSH_PROXY_SOCKET_HOST_CAPACITY), outerssh_proxy_encode_unix_socket_host)
    }

    static func tcpHost(_ host: String) -> String? {
        encode(host, capacity: Int(OUTERSSH_PROXY_TCP_HOST_CAPACITY), outerssh_proxy_encode_tcp_host)
    }

    static func url(forPort port: UInt16) -> URL? {
        tcpHost("localhost").flatMap { URL(string: "http://\($0):\(port)/") }
    }

    /// Supports http+unix://<percent-encoded socket path>/... and http://localhost[:port]/... homepages.
    static func url(forHomepage homepage: String) -> URL? {
        if let (authority, rest) = split(homepage, scheme: "http+unix") {
            guard let path = authority.removingPercentEncoding, let host = unixSocketHost(path) else { return nil }
            return URL(string: "http://\(host)\(rest)")
        }
        if let (authority, rest) = split(homepage, scheme: "http") {
            guard !authority.contains("@") else { return nil }
            let hostEnd = authority.hasPrefix("[")
                ? authority.firstIndex(of: "]").map(authority.index(after:)) ?? authority.endIndex
                : authority.firstIndex(of: ":") ?? authority.endIndex
            let port = authority[hostEnd...]
            guard port.isEmpty || (port.hasPrefix(":") && port.dropFirst().allSatisfy(\.isASCII) && UInt16(port.dropFirst()) != nil),
                  let host = tcpHost(String(authority[..<hostEnd])) else { return nil }
            return URL(string: "http://\(host)\(port)\(rest)")
        }
        return nil
    }

    private static func split(_ url: String, scheme: String) -> (authority: String, rest: String)? {
        guard url.lowercased().hasPrefix(scheme + "://") else { return nil }
        let remainder = url.dropFirst(scheme.count + 3)
        let end = remainder.firstIndex { "/?#".contains($0) } ?? remainder.endIndex
        let rest = remainder[end...]
        return (String(remainder[..<end]), rest.hasPrefix("/") ? String(rest) : "/" + rest)
    }

    private static func encode(
        _ input: String, capacity: Int,
        _ encoder: (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, Int, UnsafeMutablePointer<Int>) -> Bool
    ) -> String? {
        var output = [CChar](repeating: 0, count: capacity)
        var length = 0
        let encoded = input.withCString { encoder($0, strlen($0), &output, capacity, &length) }
        return encoded ? String(decoding: output[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }
}
