import CryptoKit
import Foundation

/// Which hook a request is from.
enum HookPath: Equatable {
    case permissionRequest
    case stopWait
}

/// What the bytes received from the hook script amount to so far.
enum HTTPRequest: Equatable {
    case needMore
    case invalid
    case complete(path: HookPath, body: Data)
}

/// The wire format between the plugin's hook script and the app. Never touches the disk or a socket.
enum AnswerProtocol {
    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 1024 * 1024

    /// Reads the request a hook script sends: `POST /permission-request` or `POST /stop-wait` with a JSON body.
    /// Anything else is invalid; nothing here is guessed at or repaired.
    static func parse(_ data: Data) -> HTTPRequest {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .needMore
        }
        guard end.lowerBound - data.startIndex <= maxHeaderBytes else { return .invalid }
        let lines = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let path: HookPath
        if lines[0].hasPrefix("POST /permission-request HTTP/1.") {
            path = .permissionRequest
        } else if lines[0].hasPrefix("POST /stop-wait HTTP/1.") {
            path = .stopWait
        } else {
            return .invalid
        }
        var length: Int?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            length = Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        guard let length, (0...maxBodyBytes).contains(length) else { return .invalid }
        let body = data[end.upperBound...]
        return body.count < length ? .needMore : .complete(path: path, body: Data(body.prefix(length)))
    }

    /// What a Stop hook answers to make Claude carry on with `reason` as its next instruction.
    static func block(reason: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": reason], options: [.sortedKeys])) ?? Data()
    }

    /// The session's id: the name of its transcript file, taken from the text of the hook's path.
    static func session(transcriptPath: String) -> String? {
        let session = ((transcriptPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return session.isEmpty || session.hasPrefix(".") ? nil : session
    }

    /// A decision as a JSON body, or no decision at all: with an empty answer the hook script
    /// prints nothing and Claude Code carries on asking in the terminal.
    static func response(body: Data?) -> Data {
        guard let body else { return Data("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".utf8) }
        return Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
    }

    /// Identifies one tool call by its name and input, whatever order the keys were written in.
    /// The hook and the transcript both carry the input, and this is how the two are matched.
    static func digest(tool: String, input: Any) -> String {
        let value: [Any] = [tool, input]
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the person chose in the panel.
enum Answer: Equatable {
    case allow
    case deny
    case option(String)
    /// A question left unanswered: Claude Code is told so, and carries on without one.
    case skip
}

/// A Stop hook: Claude finished its turn and is waiting to hear whether to carry on.
/// Everything in it is untrusted text.
struct StopWait: Equatable {
    let session: String
    let lastMessage: String

    init(session: String, lastMessage: String) {
        self.session = session
        self.lastMessage = lastMessage
    }

    init?(hookInput: Data) {
        guard let object = SafeJSON.object(hookInput),
              let transcript = object["transcript_path"] as? String,
              let session = AnswerProtocol.session(transcriptPath: transcript) else { return nil }
        // Not every Claude Code sends the last message; the turn ended all the same.
        self.init(session: session, lastMessage: object["last_assistant_message"] as? String ?? "")
    }
}

/// One request from Claude Code, as received from the hook. Everything in it is untrusted text.
struct Ask: Equatable {
    /// What a permission request puts on screen: all of it, or the request cannot be allowed.
    struct Shown: Equatable {
        struct Field: Equatable {
            let name: String
            let value: String
        }

        /// What a Bash call runs. It alone may span lines.
        let command: String?
        /// Every other field of the input, one line each, by name.
        let fields: [Field]
    }

    /// What of a request that cannot be allowed from here can still be drawn as written: the
    /// fields that each fit on one line. It says which file or which bucket the request is about.
    /// It is never enough to allow the request, and nothing in it is shortened.
    struct Partial: Equatable {
        let fields: [Shown.Field]
        /// The names of the fields left out, in order.
        let missing: [String]

        /// The left-out names that are listed: those that can be nothing but a name. With a space
        /// or a colon in it, a name could pass for the app's own words, or for a field with a value.
        var named: [String] {
            let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.".unicodeScalars)
            return Array(missing.filter { !$0.isEmpty && $0.unicodeScalars.count <= 32 && $0.unicodeScalars.allSatisfy(plain.contains) }.prefix(Ask.maxPartialFields))
        }
    }

    /// A request that is not shown in full lists at most this many of its fields.
    static let maxPartialFields = 4

    static func partial(input: [String: Any]) -> Partial {
        var fields: [Shown.Field] = []
        var missing: [String] = []
        for key in input.keys.sorted() {
            if fields.count < maxPartialFields, !key.isEmpty, isShowable(key, multiline: false),
               let value = text(input[key]), isShowable(value, multiline: false), columns("\(key): \(value)") <= wrapAt {
                fields.append(Shown.Field(name: key, value: value))
            } else {
                missing.append(key)
            }
        }
        return Partial(fields: fields, missing: missing)
    }

    struct Option: Equatable {
        let label: String
        /// The option's own description, shown beside it. May be empty.
        let detail: String
    }

    enum Kind: Equatable {
        /// A permission request whose whole content is on screen: it can be allowed or denied.
        case permission(Shown)
        /// One that cannot be shown in full and faithfully, so it cannot be allowed from here.
        /// It carries what of it can be drawn, for the person to tell which request it is.
        case permissionHidden(Partial)
        /// One single-choice question, all of it on screen. `header` is its own short label,
        /// empty when it has none that can be drawn.
        case question(text: String, header: String, options: [Option])
        /// Shown, but only answerable in the terminal: other questions, a plan.
        case terminalOnly(text: String)

        /// Whether the panel shows Allow and Deny, or option rows, for it.
        var isAnswerable: Bool {
            switch self {
            case .permission, .question: return true
            case .permissionHidden, .terminalOnly: return false
            }
        }

        /// The answer a key stands for on a request of this kind, or nil when it offers none
        /// such. What `reply` would refuse is not offered here either: a request that cannot be
        /// shown in full cannot be allowed by a key any more than by a click.
        func answer(for key: KeyCommand) -> Answer? {
            switch (self, key) {
            case (.permission, .allow): return .allow
            case (.permission, .deny), (.permissionHidden, .deny): return .deny
            case (.question(_, _, let options), .option(let number)) where options.indices.contains(number - 1): return .option(options[number - 1].label)
            // The key that denies a tool call leaves a question unanswered.
            case (.question, .deny): return .skip
            default: return nil
            }
        }
    }

    static let maxCharacters = 600

    static let maxLines = 8
    /// The columns that fit on one line under a row in the panel.
    static let wrapAt = 60
    static let maxQuestionLines = 3
    /// The columns that fit on one line of an option's row, beside its number.
    static let optionWrapAt = 52
    /// The lines a question's options may take together, labels and descriptions. At twelve,
    /// under a question of three lines, a request stands some 350 points tall: what the list
    /// shows whole on the smallest MacBook screen. A request not all in view takes no answer.
    static let maxOptionLines = 12
    /// The columns a question's header may take. Claude Code asks for twelve characters at most.
    static let maxHeaderColumns = 12

    /// The session's id: the name of its transcript file. Taken from the text of the hook's path,
    /// which is never opened, resolved or otherwise used as a path.
    let session: String
    let tool: String
    let kind: Kind
    let digest: String
    /// `tool_input` as received, needed again to answer a question.
    let input: Data
    /// The sub-agent asking, or nil for the session itself. Claude Code (2.1.310) shows a
    /// sub-agent's prompt in the terminal only once every hook is done with it.
    let agent: String?

    /// The tool's name when it can be drawn as written, otherwise a plain word in its place.
    var toolTitle: String { Self.isShowable(tool, multiline: false) ? tool : "Tool" }

    /// What a request that has been put away still says of itself: the question, or the tool.
    var summary: String {
        switch kind {
        case .question(let text, _, _), .terminalOnly(let text): return text
        case .permission, .permissionHidden: return toolTitle
        }
    }

    init?(hookInput: Data) {
        guard let object = SafeJSON.object(hookInput),
              let tool = object["tool_name"] as? String, !tool.isEmpty,
              let transcript = object["transcript_path"] as? String,
              let toolInput = object["tool_input"] as? [String: Any],
              let input = try? JSONSerialization.data(withJSONObject: toolInput) else { return nil }
        guard let session = AnswerProtocol.session(transcriptPath: transcript) else { return nil }
        self.session = session
        self.tool = tool
        self.input = input
        self.digest = AnswerProtocol.digest(tool: tool, input: toolInput)
        self.agent = (object["agent_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.kind = Self.kind(tool: tool, input: toolInput)
    }

    private static func kind(tool: String, input: [String: Any]) -> Kind {
        switch tool {
        case "AskUserQuestion":
            let questions = input["questions"] as? [[String: Any]] ?? []
            guard questions.count == 1 else { return .terminalOnly(text: "\(questions.count) questions") }
            let text = questions[0]["question"] as? String ?? ""
            // What cannot be drawn as written is not drawn at all.
            guard isShowable(text, multiline: true) else { return .terminalOnly(text: "Question") }
            // The question's short label, drawn before it. One that cannot be drawn as written is
            // left out: the question says everything without it.
            var header = (questions[0]["header"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !isShowable(header, multiline: false) || columns(header) > maxHeaderColumns { header = "" }
            // It stands beside the question, which wraps in the room that is left: its own
            // columns, and three for its padding and the gap after it.
            let questionWidth = wrapAt - (header.isEmpty ? 0 : columns(header) + 3)
            let listed = questions[0]["options"] as? [[String: Any]] ?? []
            let options = listed.map { Option(label: $0["label"] as? String ?? "", detail: $0["description"] as? String ?? "") }
            // A description wraps under its label, whole. All the rows together have to fit.
            let optionLines = options.reduce(0) { $0 + 1 + ($1.detail.isEmpty ? 0 : wordWrappedLines($1.detail, at: optionWrapAt)) }
            let visible = questions[0]["multiSelect"] as? Bool != true
                && (2...4).contains(options.count)
                && wrappedLines([text], at: questionWidth) <= maxQuestionLines
                && optionLines <= maxOptionLines
                && Set(options.map(\.label)).count == options.count
                && listed.allSatisfy { $0["preview"] == nil }
                && options.allSatisfy { option in
                    !option.label.isEmpty && isShowable(option.label, multiline: false) && isShowable(option.detail, multiline: false)
                        && columns(option.label) <= optionWrapAt
                }
            return visible ? .question(text: text, header: header, options: options) : .terminalOnly(text: text)
        case "ExitPlanMode":
            return .terminalOnly(text: TranscriptReader.planReady)
        default:
            return display(tool: tool, input: input).map { .permission($0) } ?? .permissionHidden(partial(input: input))
        }
    }

    /// Everything a permission request says, or nil when the panel cannot show all of it exactly
    /// as it is. You can only allow what you can read: nothing is shortened, left out or cleaned up.
    static func display(tool: String, input: [String: Any]) -> Shown? {
        guard isShowable(tool, multiline: false) else { return nil }
        var rest = input
        var command: String?
        // The command is what runs. The model's own description of it comes after, as a field.
        if tool == "Bash", let text = input["command"] as? String {
            guard isShowable(text, multiline: true) else { return nil }
            command = text
            rest["command"] = nil
        }
        var fields: [Shown.Field] = []
        for key in rest.keys.sorted() {
            // One line each: a second line in a value could pass itself off as another field.
            guard let value = text(rest[key]), isShowable(key, multiline: false), isShowable(value, multiline: false) else { return nil }
            fields.append(Shown.Field(name: key, value: value))
        }
        let lines = [tool] + (command?.components(separatedBy: "\n") ?? []) + fields.map { "\($0.name): \($0.value)" }
        let characters = lines.reduce(0) { $0 + $1.unicodeScalars.count }
        return characters <= maxCharacters && wrappedLines(lines) <= maxLines ? Shown(command: command, fields: fields) : nil
    }

    /// Whether `text` draws as written: every character visible, in order, on the line it is on.
    /// Controls and invisible characters draw as nothing or as a line break; right-to-left text
    /// and the marks that steer it reorder what stands next to them; a stack of combining marks
    /// paints over other lines. A request carrying any of those cannot be judged from the screen.
    static func isShowable(_ text: String, multiline: Bool) -> Bool {
        text.allSatisfy { character in
            if character == "\n" { return multiline }
            if character == " " { return true }
            guard character.unicodeScalars.count <= 4 else { return false }
            return character.unicodeScalars.allSatisfy { scalar in
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .privateUse, .surrogate, .unassigned:
                    return false
                default:
                    return !isRightToLeft(scalar)
                }
            }
        }
    }

    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: return true
        default: return false
        }
    }

    /// Columns in the panel's monospaced font: East Asian and emoji characters take two.
    static func columns(_ text: String) -> Int {
        text.reduce(0) { $0 + (($1.unicodeScalars.first?.value ?? 0) >= 0x2E80 ? 2 : 1) }
    }

    private static func wrappedLines(_ lines: [String], at width: Int = wrapAt) -> Int {
        lines.flatMap { $0.components(separatedBy: "\n") }.reduce(0) { $0 + max(1, (columns($1) + width - 1) / width) }
    }

    /// The lines one line of text takes at `width` columns when it breaks between words, as the
    /// panel draws it: a count by columns alone comes out short. A word wider than the line
    /// starts a line of its own and runs on over the next ones.
    static func wordWrappedLines(_ text: String, at width: Int) -> Int {
        var lines = 1
        var used = 0
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let size = columns(String(word))
            if used > 0, used + 1 + size > width {
                lines += 1
                used = 0
            }
            let over = max(0, size - 1) / width
            lines += over
            used = over > 0 ? size - over * width : used + (used > 0 ? 1 : 0) + size
        }
        return lines
    }

    /// A plain value as text; nil for anything nested, which cannot be shown faithfully on a line.
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        // Drawn from its value, not from the text it was written as. A whole number comes back as
        // written; one with a fraction, or too long to hold exactly, may not.
        return CFNumberIsFloatType(number) ? nil : number.stringValue
    }

    /// The JSON to hand back to Claude Code, or nil when this answer is not one the panel could
    /// have offered for this request. Allowing what was not shown in full is refused here too.
    func reply(_ answer: Answer) -> Data? {
        let decision: [String: Any]
        switch (kind, answer) {
        case (.permission, .allow):
            decision = ["behavior": "allow"]
        case (.permission, .deny), (.permissionHidden, .deny):
            decision = ["behavior": "deny", "message": "Denied from the notch."]
        case (.question, .skip):
            decision = ["behavior": "deny", "message": "Skipped from the notch. The user chose not to answer this question."]
        case (.question(let text, _, let options), .option(let label)) where options.contains(where: { $0.label == label }):
            // Claude Code takes the answer as the original input handed back with `answers` added.
            guard var updated = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return nil }
            updated["answers"] = [text: label]
            decision = ["behavior": "allow", "updatedInput": updated]
        default:
            return nil
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    }
}
