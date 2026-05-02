import Foundation
import Combine

/// Sends draft requests using a dedicated `URLSession` per call.
/// Uses an ephemeral configuration with no cache; metrics give wall-clock timing.
@MainActor
final class RequestSender: NSObject, ObservableObject {
    static let shared = RequestSender()

    @Published private(set) var inFlight: Set<String> = []
    private var tasks: [String: URLSessionTask] = [:]
    private var sessions: [String: URLSession] = [:]
    private var startTimes: [String: Date] = [:]
    private var metricsByTask: [ObjectIdentifier: URLSessionTaskMetrics] = [:]

    /// 5 MB cap on response body kept in memory.
    private let responseBodyCap = 5 * 1024 * 1024

    private override init() {
        super.init()
    }

    func isSending(draftId: String) -> Bool {
        inFlight.contains(draftId)
    }

    /// Build, validate, and dispatch the draft. Updates `draft.lastRun` on completion.
    func send(_ draft: RequestDraft) {
        let id = draft.id
        if inFlight.contains(id) { return }

        let request: URLRequest
        do {
            request = try draft.data.toURLRequest()
        } catch {
            draft.lastRun = DraftRun(
                startedAt: Date(),
                finishedAt: Date(),
                error: error.localizedDescription
            )
            return
        }

        // Persist on send so the file mirrors what was actually executed.
        RequestDraftStore.shared.upsert(draft)

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = max(1, draft.data.timeoutSeconds)

        let delegate = SenderDelegate(
            allowInvalidCertificates: draft.data.allowInvalidCertificates,
            followRedirects: draft.data.followRedirects,
            onMetrics: { [weak self] task, metrics in
                Task { @MainActor in
                    self?.metricsByTask[ObjectIdentifier(task)] = metrics
                }
            }
        )
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions[id] = session

        let started = Date()
        startTimes[id] = started
        draft.lastRun = DraftRun(startedAt: started)
        inFlight.insert(id)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                self?.finish(draftId: id, data: data, response: response, error: error)
            }
        }
        tasks[id] = task
        task.resume()
    }

    func cancel(_ draftId: String) {
        tasks[draftId]?.cancel()
    }

    // MARK: - Private

    private func finish(draftId: String, data: Data?, response: URLResponse?, error: Error?) {
        guard let task = tasks[draftId] else { return }
        let started = startTimes[draftId] ?? Date()
        let metrics = metricsByTask[ObjectIdentifier(task)]
        let duration = (metrics?.taskInterval.duration ?? Date().timeIntervalSince(started)) * 1000.0

        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode

        var headers: [String: String] = [:]
        if let raw = http?.allHeaderFields {
            for (k, v) in raw {
                headers[String(describing: k)] = String(describing: v)
            }
        }

        var bodyB64: String?
        var truncated = false
        if let data = data, !data.isEmpty {
            if data.count > responseBodyCap {
                bodyB64 = data.prefix(responseBodyCap).base64EncodedString()
                truncated = true
            } else {
                bodyB64 = data.base64EncodedString()
            }
        }

        let errorString: String? = {
            guard let error = error as? NSError else { return nil }
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                return "Cancelled.".localized
            }
            return error.localizedDescription
        }()

        let draft = RequestDraftStore.shared.draft(withId: draftId)
        draft?.lastRun = DraftRun(
            startedAt: started,
            finishedAt: Date(),
            statusCode: statusCode,
            responseHeaders: headers,
            responseBodyBase64: bodyB64,
            responseBodyTruncated: truncated,
            durationMS: duration,
            error: errorString
        )

        sessions[draftId]?.invalidateAndCancel()
        sessions[draftId] = nil
        tasks[draftId] = nil
        startTimes[draftId] = nil
        metricsByTask[ObjectIdentifier(task)] = nil
        inFlight.remove(draftId)

        NotificationCenter.default.post(name: SnagNotifications.didFinishDraftRun, object: draftId)
    }
}

private final class SenderDelegate: NSObject, URLSessionDataDelegate {
    let allowInvalidCertificates: Bool
    let followRedirects: Bool
    let onMetrics: (URLSessionTask, URLSessionTaskMetrics) -> Void

    init(allowInvalidCertificates: Bool,
         followRedirects: Bool,
         onMetrics: @escaping (URLSessionTask, URLSessionTaskMetrics) -> Void) {
        self.allowInvalidCertificates = allowInvalidCertificates
        self.followRedirects = followRedirects
        self.onMetrics = onMetrics
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInvalidCertificates,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(followRedirects ? request : nil)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        onMetrics(task, metrics)
    }
}
