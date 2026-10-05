import Foundation

/// Watches one path for writes with a vnode source (kqueue `EVFILT_VNODE`).
/// FSEvents reports a content change only when the writer closes the file,
/// so it stays silent while an agent appends to an open session log; a vnode
/// source fires on every write.
///
/// The source is bound to the open file, not to the path. After a delete or
/// a rename, as in an atomic replace, the path is opened again; while it is
/// missing it is tried again every `retryInterval` until `cancel()`.
final class FileWatch {
    enum Event: Equatable {
        /// The file was written or extended.
        case written
        /// A new file is at the path. Read it from the start.
        case replaced
        /// The file is gone from the path.
        case removed
    }

    let url: URL
    private let callbackQueue: DispatchQueue
    private let handler: (Event) -> Void
    private let retryInterval: TimeInterval
    private let state = DispatchQueue(label: "com.caffeinagent.app.filewatch")
    private var source: DispatchSourceFileSystemObject?
    private var retry: DispatchSourceTimer?
    private var cancelled = false

    /// `handler` runs on `queue`. A call that was already queued can still
    /// arrive after `cancel()`.
    init(url: URL, queue: DispatchQueue, retryInterval: TimeInterval = 0.5, handler: @escaping (Event) -> Void) {
        self.url = url
        self.callbackQueue = queue
        self.retryInterval = retryInterval
        self.handler = handler
    }

    deinit {
        source?.cancel()
        retry?.cancel()
    }

    /// Writes made after this returns are reported, if the file exists.
    func start() {
        state.sync {
            guard !cancelled, source == nil else { return }
            attach()
        }
    }

    func cancel() {
        state.sync {
            cancelled = true
            detach()
            retry?.cancel()
            retry = nil
        }
    }

    /// Runs on `state`.
    @discardableResult
    private func attach() -> Bool {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleRetry()
            return false
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: state
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, source === self.source else { return }
            if source.data.isDisjoint(with: [.delete, .rename]) {
                self.emit(.written)
            } else {
                self.detach()
                self.emit(self.attach() ? .replaced : .removed)
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        retry?.cancel()
        retry = nil
        source.resume()
        return true
    }

    private func detach() {
        source?.cancel()
        source = nil
    }

    private func scheduleRetry() {
        guard retry == nil, !cancelled else { return }
        let timer = DispatchSource.makeTimerSource(queue: state)
        timer.schedule(deadline: .now() + retryInterval, repeating: retryInterval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.cancelled, self.source == nil else { return }
            if self.attach() { self.emit(.replaced) }
        }
        retry = timer
        timer.resume()
    }

    private func emit(_ event: Event) {
        callbackQueue.async { [handler] in handler(event) }
    }
}

/// Reports that entries of one directory were added, removed or renamed, to
/// discover new session files. It says nothing about writes inside the files
/// and does not look into subdirectories: watch each level of a dated tree
/// such as `~/.codex/sessions/YYYY/MM/DD`, or list the tree on a slow timer.
final class DirectoryWatch {
    private let watch: FileWatch

    init(url: URL, queue: DispatchQueue, handler: @escaping () -> Void) {
        watch = FileWatch(url: url, queue: queue) { _ in handler() }
    }

    func start() { watch.start() }
    func cancel() { watch.cancel() }
}
