import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?
  private var pendingFile: [String: String]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let ch = FlutterMethodChannel(name: "superapp/open_with",
                                    binaryMessenger: controller.binaryMessenger)
      ch.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialFile" {
          result(self?.pendingFile)
          self?.pendingFile = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      channel = ch
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // "Open in SuperAppHD" dari Files, Mail, WhatsApp, dll.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL, let file = copyToDocuments(url) else {
      return super.application(app, open: url, options: options)
    }
    let args = ["path": file.path, "name": file.lastPathComponent]
    if UIApplication.shared.applicationState == .active {
      channel?.invokeMethod("onFile", arguments: args)
    } else {
      // Cold start / dari background: Flutter mengambilnya lewat getInitialFile
      pendingFile = args
    }
    return true
  }

  private func copyToDocuments(_ url: URL) -> URL? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let dir = docs.appendingPathComponent("opened", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    if url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { return url }
    // Nama sama + isi berbeda → "laporan (2).docx"; isi identik → pakai ulang
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var n = 1
    while true {
      let name = n == 1 ? url.lastPathComponent : "\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)")
      let dest = dir.appendingPathComponent(name)
      if !fm.fileExists(atPath: dest.path) {
        do {
          try fm.copyItem(at: url, to: dest)
          return dest
        } catch {
          return url
        }
      }
      if fm.contentsEqual(atPath: dest.path, andPath: url.path) { return dest }
      n += 1
    }
  }
}
