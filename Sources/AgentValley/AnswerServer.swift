import Foundation

enum AnswerServerError: Error, Equatable {
    case pathTooLong
    case directoryNotPrivate
    case inUse
    case system(Int32)

    var message: String {
        switch self {
        case .pathTooLong: return "the home folder path is too long for a socket"
        case .directoryNotPrivate: return "its folder is open to other accounts"
        case .inUse: return "another copy of the app is already listening"
        case .system(let code): return String(cString: strerror(code))
        }
    }
}

/// One hook waiting for its answer. Lives on the server's queue.
final class AnswerConnection {
    /// Called once if the other side goes away before a reply: the person answered "No" in the
    /// terminal, the hook timed out, or Claude Code quit.
    var onClose: (() -> Void)?

    private let descriptor: Int32
    private let source: DispatchSourceRead
    private var buffer = Data()
    private var announced = false
    private var finished = false
    private var timeout: DispatchWorkItem?
    private let onAsk: (Ask, AnswerConnection) -> Void
    private let onStop: (StopWait, AnswerConnection) -> Void
    private let onIntro: (CrewIntroRequest, AnswerConnection) -> Void
    private let onFinish: (AnswerConnection) -> Void

    fileprivate init(descriptor: Int32, queue: DispatchQueue, requestTimeout: TimeInterval,
                     onAsk: @escaping (Ask, AnswerConnection) -> Void, onStop: @escaping (StopWait, AnswerConnection) -> Void,
                     onIntro: @escaping (CrewIntroRequest, AnswerConnection) -> Void,
                     onFinish: @escaping (AnswerConnection) -> Void) {
        self.descriptor = descriptor
        self.onAsk = onAsk
        self.onStop = onStop
        self.onIntro = onIntro
        self.onFinish = onFinish
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readable() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        // A client that connects and never sends its request is not kept.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.announced else { return }
            self.finish()
        }
        timeout = work
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: work)
    }

    /// How long a reply may take to hand over. A hook that has stopped reading is given up on:
    /// this runs on the main thread, and the terminal is still there to answer.
    static let replyTimeout: TimeInterval = 1

    /// Sends the decision, or no decision when `body` is nil, and closes. Whether all of it was
    /// handed over: nothing is, to a hook that has gone.
    @discardableResult
    func reply(_ body: Data?) -> Bool {
        guard !finished else { return false }
        // Local and usually small: written in blocking calls so nothing is left half sent, with
        // a limit on each call and on the whole.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
        var limit = timeval(tv_sec: Int(Self.replyTimeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let deadline = Date().addingTimeInterval(Self.replyTimeout)
        let response = AnswerProtocol.response(body: body)
        let delivered = response.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count, Date() < deadline {
                let count = write(descriptor, bytes.baseAddress! + sent, bytes.count - sent)
                if count <= 0 { break }
                sent += count
            }
            return sent == bytes.count
        }
        finish()
        return delivered
    }

    fileprivate func finish() {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        source.cancel()
        onFinish(self)
    }

    private func readable() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while !finished {
            let count = read(descriptor, &chunk, chunk.count)
            if count > 0 {
                // Once the request is in, anything more is ignored: only the closing matters.
                if !announced { buffer.append(contentsOf: chunk[0..<count]) }
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                let wasAnnounced = announced
                finish()
                if wasAnnounced { onClose?() }
                return
            } else {
                break
            }
        }
        guard !announced, !finished else { return }
        switch AnswerProtocol.parse(buffer) {
        case .needMore:
            return
        case .invalid:
            finish()
        case .complete(.permissionRequest, let body):
            buffer = Data()
            guard let ask = Ask(hookInput: body) else { return finish() }
            announced = true
            onAsk(ask, self)
        case .complete(.stopWait, let body):
            buffer = Data()
            guard let stop = StopWait(hookInput: body) else { return finish() }
            announced = true
            onStop(stop, self)
        case .complete(.crewIntro(let pid, let terminal), let body):
            buffer = Data()
            guard let request = CrewIntroRequest(hookInput: body, pid: pid, terminal: terminal) else { return finish() }
            announced = true
            onIntro(request, self)
        }
    }
}

/// Listens for the plugin's hook script on a Unix socket in a folder only this account can enter.
/// The only code that opens a socket. It decides nothing: requests go to `onAsk`, `onStop` and `onIntro`, answers come back
/// through each connection.
final class AnswerServer {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentValley")
    }
    static let socketName = "answers.sock"
    /// Held for as long as a copy listens. Whoever holds it owns the socket file, whether or not
    /// it is quick to answer: a busy copy refuses a connection just as a dead one does.
    static let lockName = "answers.lock"

    private let directory: URL
    private let queue: DispatchQueue
    private let requestTimeout: TimeInterval
    private let onAsk: (Ask, AnswerConnection) -> Void
    private let onStop: (StopWait, AnswerConnection) -> Void
    private let onIntro: (CrewIntroRequest, AnswerConnection) -> Void
    private var accepting: DispatchSourceRead?
    private var lock: Int32 = -1
    private var connections: [ObjectIdentifier: AnswerConnection] = [:]

    var socketPath: String { directory.appendingPathComponent(Self.socketName).path }

    init(directory: URL = AnswerServer.defaultDirectory, queue: DispatchQueue = .main, requestTimeout: TimeInterval = 10,
         onAsk: @escaping (Ask, AnswerConnection) -> Void,
         onStop: @escaping (StopWait, AnswerConnection) -> Void = { _, connection in connection.reply(nil) },
         onIntro: @escaping (CrewIntroRequest, AnswerConnection) -> Void = { _, connection in connection.reply(nil) }) {
        self.directory = directory
        self.queue = queue
        self.requestTimeout = requestTimeout
        self.onAsk = onAsk
        self.onStop = onStop
        self.onIntro = onIntro
    }

    deinit {
        stop()
    }

    func start() throws {
        guard accepting == nil else { return }
        let path = socketPath
        // `sun_path` holds 104 bytes including the terminator.
        guard path.utf8.count < 104 else { throw AnswerServerError.pathTooLong }
        try preparePrivateFolder()
        guard let lock = Self.takeLock(in: directory) else { throw AnswerServerError.inUse }
        // From here the socket's place is this copy's: anything on it was left by one that is gone.
        var failure: AnswerServerError?
        defer { if failure != nil { Self.release(lock) } }
        var info = stat()
        if lstat(path, &info) == 0 {
            // Only ever a socket: a file someone put there is not the app's to delete.
            guard info.st_mode & S_IFMT == S_IFSOCK, unlink(path) == 0 else {
                failure = .system(EEXIST)
                throw failure!
            }
        }
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            failure = .system(errno)
            throw failure!
        }
        var address = Self.address(path)
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, size) } }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 16) == 0 else {
            failure = .system(errno)
            close(listener)
            if bound == 0 { unlink(path) }
            throw failure!
        }
        self.lock = lock
        _ = fcntl(listener, F_SETFD, FD_CLOEXEC)
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptWaiting(on: listener) }
        source.setCancelHandler { close(listener) }
        source.resume()
        accepting = source
    }

    /// Stops listening, removes the socket file and drops every connection without a decision.
    func stop() {
        guard let source = accepting else { return }
        accepting = nil
        source.cancel()
        // Still under the lock, so the file is this copy's own.
        unlink(socketPath)
        Self.release(lock)
        lock = -1
        for connection in Array(connections.values) { connection.finish() }
    }

    private static func takeLock(in directory: URL) -> Int32? {
        let descriptor = open(directory.appendingPathComponent(lockName).path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func release(_ lock: Int32) {
        guard lock >= 0 else { return }
        flock(lock, LOCK_UN)
        close(lock)
    }

    /// The folder must exist as a real directory that belongs to this account and that nobody else
    /// can enter. Otherwise another account could put its own socket there and answer for the app.
    private func preparePrivateFolder() throws {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            try? FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(directory.path, 0o700) == 0, lstat(directory.path, &info) == 0 else { throw AnswerServerError.system(errno) }
        }
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        guard isDirectory, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw AnswerServerError.directoryNotPrivate }
    }

    /// Removes the socket file a killed run left in `directory`, so that "off" always means no
    /// socket file. While another copy holds the lock the file is that copy's, and anything that
    /// is not a socket is not the app's to delete. Creates nothing where the folder does not exist.
    static func removeStaleSocket(in directory: URL) {
        let path = directory.appendingPathComponent(socketName).path
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, let lock = takeLock(in: directory) else { return }
        unlink(path)
        release(lock)
    }

    private func acceptWaiting(on listener: Int32) {
        while true {
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { return }
            // Defence in depth behind the folder's permissions: the caller must be this account.
            var user: uid_t = 0
            var group: gid_t = 0
            guard getpeereid(descriptor, &user, &group) == 0, user == getuid() else {
                close(descriptor)
                continue
            }
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            let connection = AnswerConnection(descriptor: descriptor, queue: queue, requestTimeout: requestTimeout, onAsk: onAsk, onStop: onStop, onIntro: onIntro) { [weak self] finished in
                self?.connections[ObjectIdentifier(finished)] = nil
            }
            connections[ObjectIdentifier(connection)] = connection
        }
    }

    private static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
        }
        return address
    }
}
