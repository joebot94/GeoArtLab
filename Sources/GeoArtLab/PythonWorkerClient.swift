import Foundation

enum WorkerClientError: LocalizedError {
    case workerScriptMissing(String)
    case processNotRunning
    case invalidResponse
    case workerError(String)

    var errorDescription: String? {
        switch self {
        case .workerScriptMissing(let path):
            return "Python worker script not found at \(path)"
        case .processNotRunning:
            return "Python worker process is not running"
        case .invalidResponse:
            return "Received invalid worker response"
        case .workerError(let message):
            return message
        }
    }
}

final class PythonWorkerClient: @unchecked Sendable {
    typealias JSONDict = [String: Any]
    typealias ResponseHandler = @Sendable (Result<JSONDict, Error>) -> Void

    var onEvent: ((JSONDict) -> Void)?

    private let queue = DispatchQueue(label: "GeoArtLab.PythonWorkerClient")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [String: ResponseHandler] = [:]
    private var shouldKeepAlive = true
    private var isRunning = false

    func startIfNeeded() {
        queue.async {
            guard !self.isRunning else { return }
            self.launchLocked()
        }
    }

    func stop() {
        queue.async {
            self.shouldKeepAlive = false
            self.stdoutHandle?.readabilityHandler = nil
            self.stderrHandle?.readabilityHandler = nil
            self.process?.terminate()
            self.process = nil
            self.stdinHandle = nil
            self.stdoutHandle = nil
            self.stderrHandle = nil
            self.isRunning = false
        }
    }

    func sendRequest(type: String, payload: JSONDict, completion: @escaping ResponseHandler) {
        let requestID = UUID().uuidString
        let envelope: JSONDict = [
            "request_id": requestID,
            "type": type,
            "payload": payload
        ]

        let encodedLine: Data
        do {
            var data = try JSONSerialization.data(withJSONObject: envelope, options: [])
            data.append(0x0A)
            encodedLine = data
        } catch {
            completion(.failure(error))
            return
        }

        queue.async {
            if !self.isRunning {
                self.launchLocked()
            }

            guard self.isRunning, let stdinHandle = self.stdinHandle else {
                self.dispatchCompletion(completion, result: .failure(WorkerClientError.processNotRunning))
                return
            }

            self.pending[requestID] = completion

            do {
                try stdinHandle.write(contentsOf: encodedLine)
            } catch {
                let handler = self.pending.removeValue(forKey: requestID)
                if let handler {
                    self.dispatchCompletion(handler, result: .failure(error))
                } else {
                    self.dispatchCompletion(completion, result: .failure(error))
                }
            }
        }
    }

    private func launchLocked() {
        let scriptURL = Self.defaultWorkerScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            dispatchEvent([
                "type": "worker_error",
                "ok": false,
                "error": ["message": WorkerClientError.workerScriptMissing(scriptURL.path).localizedDescription]
            ])
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path]
        process.currentDirectoryURL = Self.projectRootURL()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { [weak self] task in
            guard let self else { return }
            self.queue.async {
                self.handleTermination(status: task.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdinHandle = stdin.fileHandleForWriting
            self.stdoutHandle = stdout.fileHandleForReading
            self.stderrHandle = stderr.fileHandleForReading
            self.isRunning = true

            self.stdoutHandle?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let strongSelf = self else { return }
                strongSelf.queue.async {
                    strongSelf.consumeStdout(data)
                }
            }

            self.stderrHandle?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let strongSelf = self else { return }
                strongSelf.queue.async {
                    strongSelf.consumeStderr(data)
                }
            }

            dispatchEvent(["type": "worker_started", "ok": true])
        } catch {
            dispatchEvent([
                "type": "worker_error",
                "ok": false,
                "error": ["message": error.localizedDescription]
            ])
        }
    }

    private func handleTermination(status: Int32) {
        isRunning = false
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        let pendingHandlers = pending
        pending.removeAll()
        for handler in pendingHandlers.values {
            dispatchCompletion(handler, result: .failure(WorkerClientError.processNotRunning))
        }

        dispatchEvent([
            "type": "worker_stopped",
            "ok": false,
            "payload": ["status": status]
        ])

        guard shouldKeepAlive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.startIfNeeded()
        }
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineRange = stdoutBuffer.range(of: Data([0x0A])) {
            let lineData = stdoutBuffer.subdata(in: 0..<newlineRange.lowerBound)
            stdoutBuffer.removeSubrange(0..<newlineRange.upperBound)
            guard !lineData.isEmpty else { continue }
            handleStdoutLine(lineData)
        }
    }

    private func handleStdoutLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let message = object as? JSONDict,
            let type = message["type"] as? String
        else {
            dispatchEvent([
                "type": "worker_error",
                "ok": false,
                "error": ["message": WorkerClientError.invalidResponse.localizedDescription]
            ])
            return
        }

        if let requestID = message["request_id"] as? String,
           let completion = pending[requestID] {
            if type == "export_progress" {
                dispatchEvent(message)
                return
            }

            pending.removeValue(forKey: requestID)
            if let ok = message["ok"] as? Bool, ok == false {
                let errorPayload = message["error"] as? JSONDict
                let messageText = errorPayload?["message"] as? String ?? "Unknown worker error"
                dispatchCompletion(completion, result: .failure(WorkerClientError.workerError(messageText)))
            } else if type == "error" {
                let errorPayload = message["error"] as? JSONDict
                let messageText = errorPayload?["message"] as? String ?? "Unknown worker error"
                dispatchCompletion(completion, result: .failure(WorkerClientError.workerError(messageText)))
            } else {
                dispatchCompletion(completion, result: .success(message))
            }
            return
        }

        dispatchEvent(message)
    }

    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        while let newlineRange = stderrBuffer.range(of: Data([0x0A])) {
            let lineData = stderrBuffer.subdata(in: 0..<newlineRange.lowerBound)
            stderrBuffer.removeSubrange(0..<newlineRange.upperBound)
            guard
                !lineData.isEmpty,
                let text = String(data: lineData, encoding: .utf8)
            else { continue }
            dispatchEvent([
                "type": "worker_stderr",
                "ok": false,
                "payload": ["line": text]
            ])
        }
    }

    private func dispatchCompletion(_ completion: @escaping ResponseHandler, result: Result<JSONDict, Error>) {
        completion(result)
    }

    private func dispatchEvent(_ event: JSONDict) {
        onEvent?(event)
    }

    static func projectRootURL() -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent() // GeoArtLab
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // project root
    }

    static func defaultWorkerScriptURL() -> URL {
        projectRootURL()
            .appendingPathComponent("python")
            .appendingPathComponent("worker")
            .appendingPathComponent("main.py")
    }
}
