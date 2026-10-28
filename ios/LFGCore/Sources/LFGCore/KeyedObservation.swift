import Observation

/// Observation at the granularity of one key in a keyed collection.
///
/// `@Observable` tracks a stored property as a whole. A view that reads
/// `transcripts[sid]` therefore depends on the entire dictionary, and a message
/// for any other session re-runs that view's body. With many sessions running,
/// that is several re-renders of the open transcript per second for messages it
/// never shows, and it made scrolling stutter.
///
/// The owner keeps the collection itself out of observation
/// (`@ObservationIgnored`) and calls `access(key)` from every read that a view
/// can reach and `didChange(key)` after every write. An observer then depends on
/// the keys it read and nothing else.
///
/// A key gets its cell on first `access`. `didChange` for a key nobody has read
/// is a no-op: there is no observer to tell, and the first later read sees the
/// current value. Cells are never removed, so a view that is still observing a
/// key keeps receiving its changes; they cost one small object per key read.
@MainActor
public final class KeyedObservation<Key: Hashable> {
    private var cells: [Key: KeyedObservationCell] = [:]

    public init() {}

    /// Register a dependency on `key` in the current observation scope.
    public func access(_ key: Key) {
        if let cell = cells[key] {
            _ = cell.generation
        } else {
            let cell = KeyedObservationCell()
            cells[key] = cell
            _ = cell.generation
        }
    }

    /// Notify the observers of `key`, and only them.
    public func didChange(_ key: Key) {
        cells[key]?.generation &+= 1
    }
}

@MainActor @Observable
final class KeyedObservationCell {
    var generation = 0
}
