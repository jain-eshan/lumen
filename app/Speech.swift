import AVFoundation

// MARK: - Kokoro speech service

enum SpeechError: Error { case failed(String) }

@MainActor
final class Speech {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<URL, Error>] = [:]
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReady = false

    func start() throws {
        // The voice engine, its Python and the Kokoro model all ship inside the app.
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        process.executableURL = resources.appendingPathComponent("python/bin/python3")
        process.arguments = ["-I", "-B", resources.appendingPathComponent("kokoro_server.py").path]
        process.environment = ["NARRATOR_MODEL": resources.appendingPathComponent("kokoro").path, "HF_HUB_OFFLINE": "1", "HOME": NSHomeDirectory()]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
        try process.run()
    }

    func stop() { if process.isRunning { process.terminate() } }

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    func synthesize(_ text: String, voice: String, speed: Double) async throws -> URL {
        await waitUntilReady()
        nextID += 1
        let id = nextID
        let request = try JSONSerialization.data(withJSONObject: ["id": id, "text": text, "voice": voice, "speed": speed])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            input.fileHandleForWriting.write(request + Data("\n".utf8))
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[buffer.startIndex..<end]
            buffer.removeSubrange(buffer.startIndex...end)
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if reply["ready"] != nil {
                isReady = true
                readyWaiters.forEach { $0.resume() }
                readyWaiters.removeAll()
            } else if let id = reply["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if let path = reply["path"] as? String {
                    continuation.resume(returning: URL(fileURLWithPath: path))
                } else {
                    continuation.resume(throwing: SpeechError.failed(reply["error"] as? String ?? "Speech failed"))
                }
            }
        }
    }
}

/// Deletes voice clips made ahead of time once they are no longer needed.
func discardClips(_ clips: some Collection<Task<URL, Error>>) {
    let clips = Array(clips)
    Task { for clip in clips { if let url = try? await clip.value { try? FileManager.default.removeItem(at: url) } } }
}

final class PlaybackFinished: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
}

// MARK: - Diagnostic log

let logFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Narrator")
let logClock: ISO8601DateFormatter = {
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return clock
}()

/// Where events go. Evals set their own, so a run never lands in the log of the app in use.
nonisolated(unsafe) var logFile = logFolder.appendingPathComponent("narrator.log")

/// Records app events only, never the text on screen.
func note(_ message: String) {
    let url = logFile
    let line = Data("\(logClock.string(from: Date())) \(message)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? line.write(to: url)
    }
}
