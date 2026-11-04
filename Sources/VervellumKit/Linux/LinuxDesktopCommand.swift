#if os(Linux)
import Foundation
import Glibc

/// Bounded synchronous desktop tools. SecretStore remains synchronous, not nonblocking.
enum LinuxDesktopCommand {
    private static let defaultTimeout: TimeInterval = 2
    private static let maximumOutputBytes = 64 * 1024
    private static let maximumInputBytes = 64 * 1024
    private static let readChunkBytes = 16 * 1024
    private static let pollMilliseconds: Int32 = 20
    private static let millisecondsPerSecond: Double = 1_000

    static func run(_ path: String?, _ arguments: [String], input: String? = nil,
                    timeout: TimeInterval = defaultTimeout,
                    limit: Int = maximumOutputBytes) -> String? {
        guard let path, timeout.isFinite, timeout > 0, limit >= 0 else { return nil }
        let inputData = input.map { Data($0.utf8) }
        guard (inputData?.count ?? 0) <= maximumInputBytes else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var inputReader: FileHandle?
        var inputWriter: FileHandle?
        if inputData != nil {
            // A socket is still stdin, but MSG_NOSIGNAL prevents a closed reader
            // from killing Vervellum. Never change the process-wide SIGPIPE policy.
            var descriptors: [Int32] = [-1, -1]
            let flags = Int32(SOCK_STREAM.rawValue | SOCK_CLOEXEC.rawValue)
            guard socketpair(AF_UNIX, flags, 0, &descriptors) == 0 else { return nil }
            inputWriter = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
            inputReader = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
            process.standardInput = inputReader
        }
        defer {
            // There is no timer racing a completed/reaped Process or a reused PID.
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            try? inputReader?.close()
            try? inputWriter?.close()
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        guard nonblocking(output.fileHandleForReading.fileDescriptor),
              inputWriter.map({ nonblocking($0.fileDescriptor) }) ?? true else { return nil }
        do { try process.run() } catch { return nil }
        try? inputReader?.close()
        inputReader = nil
        try? output.fileHandleForWriting.close()

        let expires = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: readChunkBytes)
        var outputOpen = true
        var inputOffset = 0
        while true {
            let remaining = expires - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            if !outputOpen, !process.isRunning {
                guard inputOffset == (inputData?.count ?? 0), process.terminationStatus == 0 else { return nil }
                return String(decoding: data, as: UTF8.self)
            }
            if let writer = inputWriter, inputOffset == inputData?.count {
                _ = shutdown(writer.fileDescriptor, Int32(SHUT_WR))
                try? writer.close()
                inputWriter = nil
            }
            var descriptors = [pollfd(fd: outputOpen ? output.fileHandleForReading.fileDescriptor : -1,
                                      events: Int16(POLLIN), revents: 0)]
            if let writer = inputWriter {
                descriptors.append(pollfd(fd: writer.fileDescriptor, events: Int16(POLLOUT), revents: 0))
            }
            let wait = Int32(min(remaining * millisecondsPerSecond, Double(pollMilliseconds)).rounded(.up))
            let ready = poll(&descriptors, nfds_t(descriptors.count), wait)
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if descriptors[0].revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                while true {
                    let count = Glibc.read(output.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                    if count == 0 { outputOpen = false; break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        guard errno == EAGAIN else { return nil }
                        break
                    }
                    guard count <= limit - data.count else { return nil }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let writer = inputWriter, let inputData, descriptors.count > 1 else { continue }
            let events = descriptors[1].revents
            if events & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return nil }
            guard events & Int16(POLLOUT) != 0 else { continue }
            let count = inputData.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Glibc.send(writer.fileDescriptor, base.advanced(by: inputOffset),
                                  inputData.count - inputOffset, Int32(MSG_NOSIGNAL))
            }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return nil
            }
            inputOffset += count
        }
    }

    private static func nonblocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0
    }
}
#endif
