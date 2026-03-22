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
  alert.runModal()
}

@MainActor
func showComposer(selectedText: String) -> String? {
  let selectedView = NSTextView(frame: .zero)
  selectedView.isEditable = false
  selectedView.font = .systemFont(ofSize: 13)
  selectedView.string = selectedText
  selectedView.textContainerInset = NSSize(width: 8, height: 8)

  let selectedScroll = NSScrollView(frame: .zero)
  selectedScroll.documentView = selectedView
  selectedScroll.hasVerticalScroller = true
  selectedScroll.borderType = .bezelBorder
  selectedScroll.translatesAutoresizingMaskIntoConstraints = false
  selectedScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true

  let noteView = NSTextView(frame: .zero)
  noteView.isEditable = true
  noteView.font = .systemFont(ofSize: 13)
  noteView.textContainerInset = NSSize(width: 8, height: 8)

  let noteScroll = NSScrollView(frame: .zero)
  noteScroll.documentView = noteView
  noteScroll.hasVerticalScroller = true
  noteScroll.borderType = .bezelBorder
  noteScroll.translatesAutoresizingMaskIntoConstraints = false
  noteScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true

  let stack = NSStackView()
  stack.orientation = .vertical
  stack.spacing = 8
  stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
  stack.translatesAutoresizingMaskIntoConstraints = false

  let selectedLabel = NSTextField(labelWithString: "Selected Text")
  let noteLabel = NSTextField(labelWithString: "Your Note")

  stack.addArrangedSubview(selectedLabel)
  stack.addArrangedSubview(selectedScroll)
  stack.addArrangedSubview(noteLabel)
  stack.addArrangedSubview(noteScroll)

  let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 380))
  container.addSubview(stack)

  NSLayoutConstraint.activate([
    stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    stack.topAnchor.constraint(equalTo: container.topAnchor),
    stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
  ])

  let alert = NSAlert()
  alert.messageText = "Take Notes"
  alert.informativeText = "Add your note, then save to Flomo."
  alert.alertStyle = .informational
  alert.addButton(withTitle: "Save to Flomo")
  alert.addButton(withTitle: "Cancel")
  alert.accessoryView = container

  NSApp.activate(ignoringOtherApps: true)
  _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

  let response = alert.runModal()
  guard response == .alertFirstButtonReturn else {
    return nil
  }

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
