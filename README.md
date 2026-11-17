# outerssh-client-apple

A small starter that shows how to build an SSH client for macOS and iOS/iPadOS on
[OuterSSH](https://github.com/outergroup/OuterSSH). It connects to one SSH server and shows
the server's [homepage](https://github.com/outergroup/OuterSSH/blob/main/OuterSSH/README.md#server-defined-homepage)
in a WKWebView. Installing [Outer Shell](https://outershell.org) on a server makes it that
server's homepage, on Linux, macOS, and Windows. A port box opens `localhost:<port>` on the
server, and a Home button goes back to the homepage.

Every web request goes through OuterSSH's HTTP proxy, which runs inside the app and forwards
over SSH. WKWebView won't send `localhost` URLs to a proxy, so the app uses OuterSSH's special
hosts instead, for example `localhost.tcp.outerssh.localhost:8080` for the server's port 8080.

## Configuration

Edit `OuterSSHClient/Configuration.swift`: host, port, username, then a private key
(a file path on macOS, or the key text, which works on both platforms), with an optional
passphrase, or a password. Leave `trustedHostKeyFingerprint` empty for the first run. The
app then trusts the server's key and prints its fingerprint to the Xcode console, so you can
paste it in to pin it.

## Server helpers

OuterSSH uploads a small helper to the server when it first needs one, such as to open a Unix
socket like Outer Shell's. A build phase runs `fetch_helpers.sh`, which downloads signed helpers
for Linux, macOS, and Windows servers from outerssh.org into `helpers/` (git-ignored), checks
each against `helpers.sha256`, and copies them into the app. The phase runs with script
sandboxing off, since it downloads files and caches them in the source folder.

To use helpers you build yourself (see `OuterSSH/Release/README.md`), put them in `helpers/` and
their hashes in `helpers.sha256`; the script only downloads files whose hash doesn't match.

## Building and running

Open `OuterSSHClient.xcodeproj` in Xcode and run the `OuterSSHClient` scheme with a My Mac
or iPad/iPhone destination. The project needs no development team for macOS or the Simulator.
For a physical device, choose your team under Signing & Capabilities. From the command line:

```bash
git submodule update --init
xcodebuild -project OuterSSHClient.xcodeproj -scheme OuterSSHClient -destination 'platform=macOS' build
xcodebuild -project OuterSSHClient.xcodeproj -scheme OuterSSHClient -destination 'generic/platform=iOS Simulator' build
```

The `OuterSSH` target builds the submodule's `OuterSSH/OuterSSH` sources into a static
library with Apple cryptography, for macOS and iOS. Swift imports the library's C API with
`import OuterSSH`, through the module map in `OuterSSH/OuterSSH/include/OuterSSH`.

On macOS 15 and later, the system asks for Local Network access the first time the app connects
to a server on your local network.

## Limitations

- Root-owned sockets need `sudo`, which the starter declines.
- Supports `http+unix`, `http+pipe` and `http://localhost` homepages only.
- No saved settings, tabs or bookmarks: edit the code.
- No address bar, back or forward buttons.
- WebKit sends `localhost` requests directly instead of through a proxy, so the app injects
  OuterSSH's loopback compatibility script, `OuterSSH/OuterSSH/web/LoopbackCompatibility.js`,
  alongside the proxy's HTML rewriting. A few cases remain unhandled, such as `location.href`
  assignments; see [Compatibility hacks](https://outerssh.org/compatibility-hacks/).
