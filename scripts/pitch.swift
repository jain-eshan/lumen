import AVFoundation

// Usage: pitch input.wav cents output.wav
// Shifts pitch without changing speed, using the same audio unit the app can use live.
func shiftPitch(input: String, cents: Float, outputPath: String) throws {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: input))
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let shift = AVAudioUnitTimePitch()
    shift.pitch = cents
    engine.attach(player)
    engine.attach(shift)
    engine.connect(player, to: shift, format: file.processingFormat)
    engine.connect(shift, to: engine.mainMixerNode, format: file.processingFormat)
    try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: 4096)
    try engine.start()
    player.scheduleFile(file, at: nil)
    player.play()
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    let output = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath), settings: file.processingFormat.settings)
    while engine.manualRenderingSampleTime < file.length + 8192 {
        let frames = min(AVAudioFrameCount(file.length + 8192 - engine.manualRenderingSampleTime), buffer.frameCapacity)
        guard try engine.renderOffline(frames, to: buffer) == .success else { break }
        try output.write(from: buffer)
    }
    engine.stop()
}

let arguments = CommandLine.arguments
try shiftPitch(input: arguments[1], cents: Float(arguments[2]) ?? 0, outputPath: arguments[3])
