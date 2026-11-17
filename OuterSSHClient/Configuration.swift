import Foundation

/// Edit these values to point the app at your SSH server.
enum Configuration {
    static let host = "example.com"
    static let port: UInt16 = 22
    static let username = "you"

    /// The private key file. Only the macOS app reads it; iOS apps can't read ~/.ssh.
    static let privateKeyPath = "~/.ssh/id_ed25519"
    /// The private key text, used instead of `privateKeyPath` when set. For example:
    /// """
    /// -----BEGIN OPENSSH PRIVATE KEY-----
    /// ...
    /// -----END OPENSSH PRIVATE KEY-----
    /// """
    static let privateKeyText = ""
    static let privateKeyPassphrase = ""

    /// Set a password to use password authentication instead of a private key.
    static let password = ""

    /// The server's host key fingerprint, as OpenSSH prints it ("SHA256:...").
    /// When empty, the app trusts any host key and logs its fingerprint for you to paste here.
    static let trustedHostKeyFingerprint = ""
}
