import AppKit
import Foundation

struct AppConfig: Codable {
  let webhookUrl: String
}

enum ScreenNotesError: LocalizedError {
  case missingWebhook
  case invalidWebhook
  case emptySelection
  case saveFailed(status: Int)
  case transportFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingWebhook:
      return "Flomo webhook URL is not configured yet."
    case .invalidWebhook:
      return "Webhook URL must start with https://flomoapp.com/iwh/."
    case .emptySelection:
      return "No selected text was provided."
    case .saveFailed(let status):
      return "Flomo API returned HTTP \(status)."
    case .transportFailed(let message):
      return message
    }
  }
}

final class ConfigStore {
  private let fileURL: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    self.fileURL = base
      .appendingPathComponent("ScreenNotesMac", isDirectory: true)
      .appendingPathComponent("config.json", isDirectory: false)
  }

  func load() throws -> AppConfig {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw ScreenNotesError.missingWebhook
    }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode(AppConfig.self, from: data)
  }

  func save(webhookUrl: String) throws {
    guard webhookUrl.hasPrefix("https://flomoapp.com/iwh/") else {
      throw ScreenNotesError.invalidWebhook
    }

    let dir = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let normalized = AppConfig(webhookUrl: webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines))
    let data = try encoder.encode(normalized)
    try data.write(to: fileURL, options: [.atomic])
  }
}

struct CLIArgs {
  var selectedText: String?
  var sourceLabel: String = "Preview"
  var setupWebhook: String?
}

final class NetworkResultBox: @unchecked Sendable {
  var error: Error?
  var statusCode: Int?
}

func parseArguments() -> CLIArgs {
  var args = CLIArgs()
  let values = Array(CommandLine.arguments.dropFirst())
  var index = 0

  while index < values.count {
    let item = values[index]
    switch item {
    case "--selected-text":
      if index + 1 < values.count {
        args.selectedText = values[index + 1]
        index += 1
      }
    case "--source":
      if index + 1 < values.count {
        args.sourceLabel = values[index + 1]
        index += 1
      }
    case "--set-webhook":
      if index + 1 < values.count {
        args.setupWebhook = values[index + 1]
        index += 1
      }
    default:
      break
    }
    index += 1
  }

  return args
}

func readSelectedTextFromStdIn() -> String? {
  if isatty(fileno(stdin)) != 0 {
    return nil
  }

  let data = FileHandle.standardInput.readDataToEndOfFile()
  guard let text = String(data: data, encoding: .utf8) else {
    return nil
  }

  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : text
}

@MainActor
func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
  NSApp.activate(ignoringOtherApps: true)
  _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
  let alert = NSAlert()
  alert.alertStyle = style
  alert.messageText = title
  alert.informativeText = message
  alert.addButton(withTitle: "OK")
  alert.window.level = .floating
  alert.window.makeKeyAndOrderFront(nil)
  alert.runModal()
}

@MainActor
final class ModalButtonHelper: NSObject {
  @objc func confirmAction(_ sender: Any?) {
    NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 1000))
  }
  @objc func cancelAction(_ sender: Any?) {
    NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 1001))
  }
}

@MainActor
func showComposer(selectedText: String) -> String? {
  let W: CGFloat = 380
  let pad: CGFloat = 16
  let innerW = W - 2 * pad
  let labelH: CGFloat = 16
  let btnH: CGFloat = 28
  let editorH: CGFloat = 90
  let maxPrevH: CGFloat = 64

  // Measure preview height
  let ts = NSTextStorage(string: selectedText)
  ts.font = .systemFont(ofSize: 13)
  let tc = NSTextContainer(containerSize: NSSize(width: innerW - 12, height: .greatestFiniteMagnitude))
  tc.lineFragmentPadding = 0
  let lm = NSLayoutManager()
  lm.addTextContainer(tc)
  ts.addLayoutManager(lm)
  lm.glyphRange(for: tc)
  let prevH = max(CGFloat(24), min(ceil(lm.usedRect(for: tc).height) + 8, maxPrevH))

  let botPad: CGFloat = 10
  let cardH = labelH + prevH
  let totalH = botPad + btnH + 8 + editorH + 2 + labelH + 8 + cardH + 8

  let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: W, height: totalH),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  panel.title = "\u{270F}\u{FE0F} Take Notes"
  panel.level = .floating
  panel.isReleasedWhenClosed = false
  let cv = panel.contentView!

  let helper = ModalButtonHelper()
  var y = botPad

  // -- Buttons --
  let saveBtnW: CGFloat = 120
  let cancelBtnW: CGFloat = 80

  let saveBtn = NSButton(frame: NSRect(x: W - pad - saveBtnW, y: y, width: saveBtnW, height: btnH))
  saveBtn.title = "Save to Flomo"
  saveBtn.bezelStyle = .rounded
  saveBtn.keyEquivalent = "\r"
  saveBtn.target = helper
  saveBtn.action = #selector(ModalButtonHelper.confirmAction)
  cv.addSubview(saveBtn)

  let cancelBtn = NSButton(frame: NSRect(x: W - pad - saveBtnW - 8 - cancelBtnW, y: y, width: cancelBtnW, height: btnH))
  cancelBtn.title = "Cancel"
  cancelBtn.bezelStyle = .rounded
  cancelBtn.keyEquivalent = "\u{1b}"
  cancelBtn.target = helper
  cancelBtn.action = #selector(ModalButtonHelper.cancelAction)
  cv.addSubview(cancelBtn)
  y += btnH + 8

  // -- Editor --
  let noteView = NSTextView(frame: NSRect(x: 0, y: 0, width: innerW, height: editorH))
  noteView.font = .systemFont(ofSize: 13)
  noteView.isEditable = true
  noteView.isRichText = false
  noteView.textContainerInset = NSSize(width: 6, height: 4)
  noteView.textContainer?.widthTracksTextView = true

  let noteScroll = NSScrollView(frame: NSRect(x: pad, y: y, width: innerW, height: editorH))
  noteScroll.documentView = noteView
  noteScroll.hasVerticalScroller = true
  noteScroll.borderType = .bezelBorder
  noteScroll.wantsLayer = true
  noteScroll.layer?.cornerRadius = 6
  noteScroll.layer?.masksToBounds = true
  cv.addSubview(noteScroll)
  y += editorH + 2

  // -- YOUR NOTE label --
  let noteLabel = NSTextField(labelWithString: "YOUR NOTE")
  noteLabel.font = .boldSystemFont(ofSize: 10)
  noteLabel.textColor = .secondaryLabelColor
  noteLabel.frame = NSRect(x: pad, y: y, width: innerW, height: labelH)
  cv.addSubview(noteLabel)
  y += labelH + 8

  // -- Selected text card --
  let card = NSView(frame: NSRect(x: pad, y: y, width: innerW, height: cardH))
  card.wantsLayer = true
  card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
  card.layer?.cornerRadius = 6
  card.layer?.masksToBounds = true

  let selLabel = NSTextField(labelWithString: "SELECTED TEXT")
  selLabel.font = .boldSystemFont(ofSize: 10)
  selLabel.textColor = .tertiaryLabelColor
  selLabel.frame = NSRect(x: 8, y: cardH - labelH - 2, width: innerW - 16, height: labelH)
  card.addSubview(selLabel)

  let prevView = NSTextView(frame: NSRect(x: 0, y: 0, width: innerW, height: prevH))
  prevView.font = .systemFont(ofSize: 13)
  prevView.isEditable = false
  prevView.isSelectable = true
  prevView.isRichText = false
  prevView.string = selectedText
  prevView.textColor = .secondaryLabelColor
  prevView.drawsBackground = false
  prevView.textContainerInset = NSSize(width: 6, height: 2)
  prevView.textContainer?.widthTracksTextView = true

  let prevScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: innerW, height: prevH))
  prevScroll.documentView = prevView
  prevScroll.hasVerticalScroller = true
  prevScroll.borderType = .noBorder
  prevScroll.drawsBackground = false
  card.addSubview(prevScroll)
  cv.addSubview(card)

  NSApp.activate(ignoringOtherApps: true)
  _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
  panel.center()
  panel.makeKeyAndOrderFront(nil)
  panel.makeFirstResponder(noteView)

  let result = NSApp.runModal(for: panel)
  panel.orderOut(nil)

  guard result.rawValue == 1000 else { return nil }
  return noteView.string.trimmingCharacters(in: .whitespacesAndNewlines)
}

func buildFlomoContent(selectedText: String, userNote: String, sourceLabel: String) -> String {
  var parts: [String] = [selectedText, "——————————"]
  if !userNote.isEmpty {
    parts.append(userNote)
  }
  parts.append(sourceLabel)
  parts.append("#Mac-Reading")
  return parts.joined(separator: "\n\n")
}

func sendToFlomo(webhookUrl: String, content: String) throws {
  guard let url = URL(string: webhookUrl) else {
    throw ScreenNotesError.invalidWebhook
  }

  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])

  let semaphore = DispatchSemaphore(value: 0)
  let box = NetworkResultBox()
  URLSession.shared.dataTask(with: request) { _, response, error in
    defer { semaphore.signal() }
    box.error = error
    box.statusCode = (response as? HTTPURLResponse)?.statusCode
  }.resume()

  semaphore.wait()

  if let error = box.error {
    throw ScreenNotesError.transportFailed(error.localizedDescription)
  }

  guard let statusCode = box.statusCode else {
    throw ScreenNotesError.transportFailed("No HTTP response from Flomo API.")
  }

  guard (200...299).contains(statusCode) else {
    throw ScreenNotesError.saveFailed(status: statusCode)
  }
}

func configureWebhook(_ webhook: String, store: ConfigStore) -> Int32 {
  do {
    try store.save(webhookUrl: webhook)
    print("Webhook configured.")
    return EXIT_SUCCESS
  } catch {
    fputs("Failed to save webhook: \(error.localizedDescription)\n", stderr)
    return EXIT_FAILURE
  }
}

@MainActor
func runComposeFlow(args: CLIArgs, store: ConfigStore) -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)

  let selectedText = args.selectedText ?? readSelectedTextFromStdIn()
  guard let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    fputs("No selected text found.\n", stderr)
    return EXIT_FAILURE
  }

  let webhookUrl: String
  do {
    let config = try store.load()
    webhookUrl = config.webhookUrl
  } catch {
    showAlert(
      title: "Screen Notes Setup Required",
      message: "Run:\n\nswift run --package-path mac/ScreenNotesMac ScreenNotesMac --set-webhook https://flomoapp.com/iwh/xxxxx/yyyyy/"
    )
    return EXIT_FAILURE
  }

  guard let userNote = showComposer(selectedText: selectedText) else {
    return EXIT_SUCCESS
  }

  let content = buildFlomoContent(
    selectedText: selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
    userNote: userNote,
    sourceLabel: args.sourceLabel
  )

  do {
    try sendToFlomo(webhookUrl: webhookUrl, content: content)
    showAlert(title: "Saved", message: "Your note was sent to Flomo.", style: .informational)
    return EXIT_SUCCESS
  } catch {
    showAlert(title: "Save Failed", message: error.localizedDescription)
    return EXIT_FAILURE
  }
}

let cli = parseArguments()
let store = ConfigStore()

if let webhook = cli.setupWebhook {
  exit(configureWebhook(webhook, store: store))
} else {
  Task { @MainActor in
    exit(runComposeFlow(args: cli, store: store))
  }
  dispatchMain()
}
