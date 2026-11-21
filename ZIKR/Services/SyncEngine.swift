import Foundation

typealias Mutation = (inout ZikrData) throws -> Void

/// Applies mutations to the file off the main thread.
///
/// The UI applies each mutation to its in-memory copy immediately; the same mutation is queued
/// here and replayed on top of the *current file* inside one coordinated read-modify-write.
/// That way changes made meanwhile by the widget or an App Intent are merged, not overwritten.
/// Mutations must be deterministic (capture `now` and new IDs before enqueueing).
final class SyncEngine: @unchecked Sendable {
    private let file: DataFile
    private let queue = DispatchQueue(label: "zikr.sync", qos: .userInitiated)
    private var pending: [Mutation] = []
    private var drainScheduled = false
    private var blocked = false

    /// Called on the main actor after a successful write with the file state and how many
    /// queued mutations it contains.
    var onCommitted: (@MainActor (ZikrData, Int) -> Void)?
    var onFailure: (@MainActor (Error) -> Void)?

    init(file: DataFile) {
        self.file = file
    }

    /// While blocked (unreadable or newer-version file) nothing is written.
    func setBlocked(_ value: Bool) {
        queue.async { self.blocked = value; if value { self.pending.removeAll() } }
    }

    func enqueue(_ mutation: @escaping Mutation, delay: TimeInterval = 0.25) {
        queue.async {
            self.pending.append(mutation)
            guard !self.drainScheduled else { return }
            self.drainScheduled = true
            self.queue.asyncAfter(deadline: .now() + delay) { self.drain() }
        }
    }

    /// Writes everything that is queued before returning. Call when the app leaves the foreground.
    func flush() {
        queue.sync { self.drain() }
    }

    /// Writes everything queued off the main thread, then calls `completion` on the main actor.
    func flushAsync(_ completion: @escaping @MainActor () -> Void) {
        queue.async {
            self.drain()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion() } }
        }
    }

    /// Re-reads the file (after another process changed it) without writing.
    func reload(_ completion: @escaping @MainActor (ZikrData?) -> Void) {
        queue.async {
            let data = self.file.peek()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(data) } }
        }
    }

    private func drain() {
        drainScheduled = false
        guard !pending.isEmpty, !blocked else { return }
        let batch = pending
        pending.removeAll()
        do {
            let result = try file.update { data in
                for mutation in batch {
                    // A mutation can become invalid because of an external change
                    // (e.g. the item was archived from another device state). Skip it.
                    try? mutation(&data)
                }
            }
            // No Darwin notification here: only the app listens for them, and this is the app.
            let callback = onCommitted
            DispatchQueue.main.async { MainActor.assumeIsolated { callback?(result, batch.count) } }
        } catch {
            // Keep the mutations and retry later instead of losing them.
            pending.insert(contentsOf: batch, at: 0)
            if !drainScheduled {
                drainScheduled = true
                queue.asyncAfter(deadline: .now() + 2) { self.drain() }
            }
            let callback = onFailure
            DispatchQueue.main.async { MainActor.assumeIsolated { callback?(error) } }
        }
    }
}
