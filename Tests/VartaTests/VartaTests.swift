import Testing
import Foundation
@testable import Varta

@Suite("Address value type")
struct AddressSuite {

    @Test("Address.local builds a host=local address")
    func localFactory() {
        let address = Address.local("/tmp/x")
        #expect(address.host == Address.localHost)
        #expect(address.path == "/tmp/x")
        #expect(address.isLocal)
    }

    @Test("Address.peer builds a remote peer address")
    func peerFactory() {
        let address = Address.peer("peer-1", path: "/mailboxes/a")
        #expect(address.host == "peer:peer-1")
        #expect(address.path == "/mailboxes/a")
        #expect(!address.isLocal)
        #expect(address.hostKind == .peer("peer-1"))
    }

    @Test("Address round-trips through JSON")
    func roundTrip() throws {
        let address = Address(host: "peer-42", path: "/var/mailbox")
        let data = try JSONEncoder().encode(address)
        let decoded = try JSONDecoder().decode(Address.self, from: data)
        #expect(decoded == address)
    }
}

@Suite("Envelope value type")
struct EnvelopeSuite {

    @Test("Envelope round-trips through JSON")
    func roundTrip() throws {
        let env = Envelope(
            from: .local("/tmp/a"),
            to: .local("/tmp/b"),
            issuedAt: Date(timeIntervalSince1970: 1_900_000_000),
            causality: [UUID()],
            mediaType: "text/plain",
            data: Data("hi".utf8),
            metadata: ["k": "v"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(env)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Envelope.self, from: data)
        #expect(decoded == env)
    }
}

@Suite("Varta send and receive")
struct VartaSuite {

    @Test("submit writes an envelope into the managed outbox without delivering it")
    func submitOnlyWritesPendingOutbox() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(
            address: .local(dirs[0].path),
            serviceRoot: serviceRoot
        )
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("queued".utf8)
        )

        try await daemon.submit(envelope)

        let pendingEnvelope = serviceRoot
            .appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent(envelope.id.uuidString, isDirectory: true)
            .appendingPathComponent(FilesystemSubmissionQueue.envelopeFileName)
        #expect(FileManager.default.fileExists(atPath: pendingEnvelope.path))

        let recipient = try await Varta(address: .local(dirs[1].path), serviceRoot: serviceRoot)
        let received = try await recipient.receive()
        #expect(received.isEmpty)
    }

    @Test("processPending delivers a local submission through the common outbox")
    func processPendingDeliversLocalSubmission() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(
            address: .local(dirs[0].path),
            serviceRoot: serviceRoot
        )
        _ = try await daemon.registerMailbox(.local(dirs[1].path))
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("local".utf8)
        )
        try await daemon.submit(envelope)

        let receipts = try await daemon.processPending()

        #expect(receipts.map(\.envelopeID) == [envelope.id])
        #expect(receipts.first?.mode == .local)
        let sentEnvelope = serviceRoot
            .appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent("sent", isDirectory: true)
            .appendingPathComponent(envelope.id.uuidString, isDirectory: true)
            .appendingPathComponent(FilesystemSubmissionQueue.envelopeFileName)
        #expect(FileManager.default.fileExists(atPath: sentEnvelope.path))

        let recipient = try await Varta(address: .local(dirs[1].path), serviceRoot: serviceRoot)
        let received = try await recipient.receive()
        #expect(received.map(\.id) == [envelope.id])
    }

    @Test("filesystem client writes only control and outbox pending state")
    func filesystemClientWritesProducerOwnedState() async throws {
        let dirs = try makeTempMailboxes(count: 2, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let client = MessagingFilesystemClient(serviceRoot: serviceRoot)
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("queued".utf8)
        )

        _ = try client.registerMailbox(.local(dirs[1].path))
        _ = try client.submit(envelope)

        #expect(FileManager.default.fileExists(
            atPath: serviceRoot
                .appendingPathComponent("control/pending", isDirectory: true)
                .path(percentEncoded: false)
        ))
        #expect(FileManager.default.fileExists(
            atPath: serviceRoot
                .appendingPathComponent("outbox/pending", isDirectory: true)
                .path(percentEncoded: false)
        ))
        #expect(!FileManager.default.fileExists(
            atPath: serviceRoot
                .appendingPathComponent("registry", isDirectory: true)
                .path(percentEncoded: false)
        ))
        #expect(!FileManager.default.fileExists(
            atPath: serviceRoot
                .appendingPathComponent("mailboxes", isDirectory: true)
                .path(percentEncoded: false)
        ))
    }

    @Test("filesystem client can receive after daemon processes control and outbox")
    func filesystemClientReceivesAfterDaemonDelivery() async throws {
        let dirs = try makeTempMailboxes(count: 2, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let client = MessagingFilesystemClient(serviceRoot: serviceRoot)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("queued".utf8)
        )

        _ = try client.registerMailbox(.local(dirs[1].path))
        _ = try await daemon.processControlCommands()
        _ = try client.submit(envelope)
        _ = try await daemon.processPending()

        let received = try client.receive(at: .local(dirs[1].path))
        #expect(received.map(\.id) == [envelope.id])
        try client.ack(envelope.id, at: .local(dirs[1].path))
        #expect(try client.receive(at: .local(dirs[1].path)).isEmpty)
    }

    @Test("echo service replies without an agent runtime")
    func echoServiceRepliesWithoutAgentRuntime() async throws {
        let dirs = try makeTempMailboxes(count: 2, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let client = MessagingFilesystemClient(serviceRoot: serviceRoot)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        let sender = Address.local(dirs[0].path)
        let echo = Address.local(dirs[1].path)
        let echoService = VartaEchoService(address: echo, serviceRoot: serviceRoot)
        let request = Envelope(
            from: sender,
            to: echo,
            mediaType: "text/plain",
            data: Data("echo this".utf8),
            metadata: ["test.case": "varta.echo"]
        )

        _ = try await daemon.registerMailbox(sender)
        _ = try await daemon.registerMailbox(echo)
        try client.submit(request)
        _ = try await daemon.processPending()

        let replies = try echoService.process()
        _ = try await daemon.processPending()

        #expect(replies.count == 1)
        #expect(replies.first?.from == echo)
        #expect(replies.first?.to == sender)
        #expect(replies.first?.data == request.data)
        #expect(replies.first?.mediaType == request.mediaType)
        #expect(replies.first?.causality == [request.id])
        #expect(replies.first?.metadata["messaging.inReplyTo"] == request.id.uuidString)
        #expect(replies.first?.metadata["varta.e2eEcho.kind"] == "reply")

        let senderInbox = try client.receive(at: sender)
        #expect(senderInbox.map(\.id) == replies.map(\.id))
        #expect(try client.receive(at: echo).isEmpty)
    }

    @Test("vartad e2e echo replies through the filesystem contract")
    func daemonEchoModeRepliesThroughFilesystemContract() async throws {
        let dirs = try makeTempMailboxes(count: 2, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let sender = Address.local(dirs[0].path)
        let echo = Address.local(dirs[1].path)
        let pidFile = serviceRoot
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("vartad-e2e.pid")
        let client = MessagingFilesystemClient(serviceRoot: serviceRoot)
        let mapper = MailboxStorageMapper(serviceRoot: serviceRoot)
        let senderRegistration = try mapper.registrationURL(for: sender)
        let process = try startVartad(
            serviceRoot: serviceRoot,
            echoPath: echo.path,
            pidFile: pidFile
        )
        defer {
            stop(process)
        }

        try await waitUntilFileExists(pidFile)
        _ = try client.registerMailbox(sender)
        try await waitUntilFileExists(senderRegistration)

        let request = Envelope(
            from: sender,
            to: echo,
            mediaType: "text/plain",
            data: Data("daemon echo".utf8),
            metadata: ["test.case": "varta.daemon.echo"]
        )
        try client.submit(request)

        let reply = try await waitForEnvelope(at: sender, serviceRoot: serviceRoot) { envelope in
            envelope.metadata["messaging.inReplyTo"] == request.id.uuidString
        }

        #expect(reply.from == echo)
        #expect(reply.to == sender)
        #expect(reply.data == request.data)
        #expect(reply.mediaType == request.mediaType)
        #expect(reply.causality == [request.id])
        #expect(reply.metadata["varta.e2eEcho.kind"] == "reply")
    }

    @Test("malformed pending outbox is quarantined and later envelopes still deliver")
    func malformedPendingOutboxDoesNotBlockDelivery() async throws {
        let dirs = try makeTempMailboxes(count: 2, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        _ = try await daemon.registerMailbox(.local(dirs[1].path))
        let badID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let pending = serviceRoot
            .appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        let badDirectory = pending.appendingPathComponent(badID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: badDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(
            to: badDirectory.appendingPathComponent(FilesystemSubmissionQueue.envelopeFileName)
        )
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("valid".utf8)
        )
        try await daemon.submit(envelope)

        let receipts = try await daemon.processPending()

        #expect(receipts.map(\.envelopeID) == [envelope.id])
        let quarantineFailure = serviceRoot
            .appendingPathComponent("quarantine/malformed/outbox", isDirectory: true)
            .appendingPathComponent(badID.uuidString, isDirectory: true)
            .appendingPathComponent(FilesystemSubmissionQueue.failureFileName)
        #expect(FileManager.default.fileExists(atPath: quarantineFailure.path(percentEncoded: false)))
        let received = try MessagingFilesystemClient(serviceRoot: serviceRoot)
            .receive(at: .local(dirs[1].path))
        #expect(received.map(\.id) == [envelope.id])
    }

    @Test("malformed control command is quarantined and later commands still apply")
    func malformedControlCommandDoesNotBlockControlProcessing() async throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        let badID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let pending = serviceRoot
            .appendingPathComponent("control", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        let badDirectory = pending.appendingPathComponent(badID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: badDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(
            to: badDirectory.appendingPathComponent(MessagingControlQueue.commandFileName)
        )
        let command = MessagingControlCommand(kind: .registerMailbox(address: .local(dirs[0].path)))
        _ = try MessagingControlQueue(root: serviceRoot).submit(command)

        let results = try await daemon.processControlCommands()

        #expect(results.map(\.commandID) == [command.id])
        let quarantineFailure = serviceRoot
            .appendingPathComponent("quarantine/malformed/control", isDirectory: true)
            .appendingPathComponent(badID.uuidString, isDirectory: true)
            .appendingPathComponent(MessagingControlQueue.failureFileName)
        #expect(FileManager.default.fileExists(atPath: quarantineFailure.path(percentEncoded: false)))
        _ = try await daemon.mailboxURLs(for: .local(dirs[0].path))
    }

    @Test("rejected control command is recorded and later commands still apply")
    func rejectedControlCommandDoesNotBlockControlProcessing() async throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        let rejected = MessagingControlCommand(
            kind: .registerMailbox(address: Address(host: "unsupported", path: "/mailbox"))
        )
        let applied = MessagingControlCommand(
            kind: .registerMailbox(address: .local(dirs[0].path))
        )
        let queue = MessagingControlQueue(root: serviceRoot)
        _ = try queue.submit(rejected)
        _ = try queue.submit(applied)

        let results = try await daemon.processControlCommands()

        #expect(results.map(\.commandID) == [applied.id])
        let rejectedFailure = serviceRoot
            .appendingPathComponent("control/rejected", isDirectory: true)
            .appendingPathComponent(rejected.id.uuidString, isDirectory: true)
            .appendingPathComponent(MessagingControlQueue.failureFileName)
        #expect(FileManager.default.fileExists(atPath: rejectedFailure.path(percentEncoded: false)))
        _ = try await daemon.mailboxURLs(for: .local(dirs[0].path))
    }

    @Test("garbage collection includes hidden mailbox paths")
    func garbageCollectionIncludesHiddenMailboxPaths() throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let processed = serviceRoot
            .appendingPathComponent("mailboxes/local/tmp/project/.agent/messaging/worker/processed", isDirectory: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let stale = processed.appendingPathComponent("stale.json")
        try Data("{}".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: stale.path(percentEncoded: false)
        )
        let collector = MessagingGarbageCollector(serviceRoot: serviceRoot)

        let report = try collector.run(
            policy: MessagingRetentionPolicy(
                dryRun: false,
                processedMaxAgeSeconds: 1
            ),
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(report.removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
    }

    @Test("garbage collection applies failed policy to mailbox failed state")
    func garbageCollectionSeparatesProcessedAndFailedPolicies() throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let root = serviceRoot
            .appendingPathComponent("mailboxes/local/tmp/project/.board/messaging/agent", isDirectory: true)
        let processed = root.appendingPathComponent("processed", isDirectory: true)
        let failed = root.appendingPathComponent("failed", isDirectory: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        let processedStale = processed.appendingPathComponent("processed.json")
        let failedStale = failed.appendingPathComponent("failed.json")
        try Data("{}".utf8).write(to: processedStale)
        try Data("{}".utf8).write(to: failedStale)
        for url in [processedStale, failedStale] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1)],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        let collector = MessagingGarbageCollector(serviceRoot: serviceRoot)

        let report = try collector.run(
            policy: MessagingRetentionPolicy(
                dryRun: false,
                failedMaxAgeSeconds: 1
            ),
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(report.removedCount == 1)
        #expect(FileManager.default.fileExists(atPath: processedStale.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: failedStale.path(percentEncoded: false)))
    }

    @Test("garbage collection applies quarantine retention")
    func garbageCollectionAppliesQuarantineRetention() throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let quarantine = serviceRoot
            .appendingPathComponent("quarantine/malformed/outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let stale = quarantine.appendingPathComponent("bad-envelope", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: stale.path(percentEncoded: false)
        )
        let collector = MessagingGarbageCollector(serviceRoot: serviceRoot)

        let report = try collector.run(
            policy: MessagingRetentionPolicy(
                dryRun: false,
                quarantineMaxAgeSeconds: 1
            ),
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(report.removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
    }

    @Test("processPending routes a remote submission through remote transport")
    func processPendingDeliversRemoteSubmission() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let envelopeID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let transport = RecordingRemoteTransport(
            response: RemoteEnvelopeDeliveryResponse(
                envelopeID: envelopeID,
                accepted: true,
                storedAt: Date(timeIntervalSince1970: 3_000)
            )
        )
        let daemon = try await Varta(
            address: .local(dirs[0].path),
            serviceRoot: serviceRoot,
            remoteTransport: transport
        )
        let envelope = Envelope(
            id: envelopeID,
            from: .local(dirs[0].path),
            to: .peer("peer-2", path: "/remote/mailbox"),
            mediaType: "text/plain",
            data: Data("remote".utf8)
        )
        try await daemon.submit(envelope)

        let receipts = try await daemon.processPending()

        #expect(receipts.first?.mode == .remote)
        let requests = await transport.requests
        #expect(requests.map(\.envelope.id) == [envelope.id])
    }

    @Test("failed remote submission is moved to failed outbox")
    func failedRemoteSubmissionMovesToFailed() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(
            address: .local(dirs[0].path),
            serviceRoot: serviceRoot
        )
        let envelope = Envelope(
            from: .local(dirs[0].path),
            to: .peer("peer-2", path: "/remote/mailbox"),
            mediaType: "text/plain",
            data: Data("remote".utf8)
        )
        try await daemon.submit(envelope)

        let receipts = try await daemon.processPending()

        #expect(receipts.isEmpty)
        let failedEnvelope = serviceRoot
            .appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent("failed", isDirectory: true)
            .appendingPathComponent(envelope.id.uuidString, isDirectory: true)
            .appendingPathComponent(FilesystemSubmissionQueue.failureFileName)
        #expect(FileManager.default.fileExists(atPath: failedEnvelope.path))
    }

    @Test("failed delivery is recorded and later envelopes still deliver")
    func failedDeliveryDoesNotBlockLaterEnvelopes() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let daemon = try await Varta(serviceRoot: serviceRoot)
        _ = try await daemon.registerMailbox(.local(dirs[1].path))
        let failed = Envelope(
            from: .local(dirs[0].path),
            to: .peer("peer-2", path: "/remote/mailbox"),
            mediaType: "text/plain",
            data: Data("remote".utf8)
        )
        let delivered = Envelope(
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            issuedAt: failed.issuedAt.addingTimeInterval(1),
            mediaType: "text/plain",
            data: Data("local".utf8)
        )
        try await daemon.submit(failed)
        try await daemon.submit(delivered)

        let receipts = try await daemon.processPending()

        #expect(receipts.map(\.envelopeID) == [delivered.id])
        let failedEnvelope = serviceRoot
            .appendingPathComponent("outbox/failed", isDirectory: true)
            .appendingPathComponent(failed.id.uuidString, isDirectory: true)
            .appendingPathComponent(FilesystemSubmissionQueue.failureFileName)
        #expect(FileManager.default.fileExists(atPath: failedEnvelope.path(percentEncoded: false)))
    }

    @Test("send writes the envelope into the recipient's inbox")
    func sendCreatesFile() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let aAddr = Address.local(dirs[0].path)
        let bAddr = Address.local(dirs[1].path)
        let serviceRoot = makeServiceRoot(for: dirs)
        let a = try await Varta(address: aAddr, serviceRoot: serviceRoot)
        _ = try await a.registerMailbox(bAddr)

        let envelope = Envelope(
            from: aAddr,
            to: bAddr,
            mediaType: "text/plain",
            data: Data("hello".utf8)
        )
        try await a.send(envelope)

        let bInbox = try await a.mailboxURLs(for: bAddr).inbox
        let entries = try FileManager.default.contentsOfDirectory(
            at: bInbox,
            includingPropertiesForKeys: nil
        )
        let jsonFiles = entries.filter { $0.pathExtension == "json" }
        #expect(jsonFiles.count == 1)
    }

    @Test("receive returns envelopes sorted by issuedAt")
    func receiveOrdered() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let aAddr = Address.local(dirs[0].path)
        let bAddr = Address.local(dirs[1].path)
        let serviceRoot = makeServiceRoot(for: dirs)
        let a = try await Varta(address: aAddr, serviceRoot: serviceRoot)
        let b = try await Varta(address: bAddr, serviceRoot: serviceRoot)

        let older = Envelope(
            from: aAddr,
            to: bAddr,
            issuedAt: Date(timeIntervalSince1970: 1_000),
            mediaType: "text/plain",
            data: Data("1".utf8)
        )
        let newer = Envelope(
            from: aAddr,
            to: bAddr,
            issuedAt: Date(timeIntervalSince1970: 2_000),
            mediaType: "text/plain",
            data: Data("2".utf8)
        )
        try await a.send(newer)
        try await a.send(older)

        let received = try await b.receive()
        #expect(received.count == 2)
        #expect(received[0].issuedAt < received[1].issuedAt)
        #expect(received[0].data == Data("1".utf8))
    }

    @Test("ack moves the envelope from inbox to processed")
    func ackMovesFile() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let aAddr = Address.local(dirs[0].path)
        let bAddr = Address.local(dirs[1].path)
        let serviceRoot = makeServiceRoot(for: dirs)
        let a = try await Varta(address: aAddr, serviceRoot: serviceRoot)
        let b = try await Varta(address: bAddr, serviceRoot: serviceRoot)

        let envelope = Envelope(
            from: aAddr,
            to: bAddr,
            mediaType: "text/plain",
            data: Data("hi".utf8)
        )
        try await a.send(envelope)

        let received = try await b.receive()
        #expect(received.count == 1)
        try await b.ack(envelope.id)

        let after = try await b.receive()
        #expect(after.isEmpty)

        let processed = try await b.mailboxURLs(for: bAddr)
            .processed
            .appendingPathComponent("\(envelope.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: processed.path))
    }

    @Test("ack of an unknown id throws envelopeNotFound")
    func ackNotFound() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let actor = try await Varta(
            address: .local(dirs[0].path),
            serviceRoot: makeServiceRoot(for: dirs)
        )

        do {
            try await actor.ack(UUID())
            Issue.record("ack must throw for unknown id")
        } catch let error as MessagingError {
            if case .envelopeNotFound = error {
                // expected
            } else {
                Issue.record("unexpected MessagingError: \(error)")
            }
        }
    }

    @Test("non-local host is rejected")
    func unsupportedHost() async {
        do {
            _ = try await Varta(address: Address(host: "remote", path: "/x"))
            Issue.record("non-local host must be rejected")
        } catch let error as MessagingError {
            if case .unsupportedHost(let h) = error {
                #expect(h == "remote")
            } else {
                Issue.record("unexpected MessagingError: \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("mailbox state is stored under the service root")
    func mailboxStateIsStoredUnderServiceRoot() async throws {
        let dirs = try makeTempMailboxes(count: 1, instantiate: false)
        defer { cleanup(dirs) }
        let senderDir = try makeTempMailboxes(count: 1)
        defer { cleanup(senderDir) }

        let serviceRoot = makeServiceRoot(for: senderDir + dirs)
        let sender = try await Varta(
            address: .local(senderDir[0].path),
            serviceRoot: serviceRoot
        )
        let urls = try await sender.mailboxURLs(for: .local(senderDir[0].path))
        #expect(urls.root.path.hasPrefix(serviceRoot.path))
        #expect(!FileManager.default.fileExists(
            atPath: senderDir[0]
                .appendingPathComponent(".messaging", isDirectory: true)
                .path
        ))
    }

    @Test("send to peer routes through remote transport and returns a remote receipt")
    func sendToPeerUsesRemoteTransport() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let senderAddress = Address.local(dirs[0].path)
        let envelopeID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let transport = RecordingRemoteTransport(
            response: RemoteEnvelopeDeliveryResponse(
                envelopeID: envelopeID,
                accepted: true,
                storedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let sender = try await Varta(
            address: senderAddress,
            serviceRoot: makeServiceRoot(for: dirs),
            remoteTransport: transport
        )
        let envelope = Envelope(
            id: envelopeID,
            from: senderAddress,
            to: .peer("peer-2", path: "/remote/mailbox"),
            mediaType: "text/plain",
            data: Data("remote".utf8)
        )

        let receipt = try await sender.send(envelope)

        #expect(receipt.mode == .remote)
        #expect(receipt.envelopeID == envelope.id)
        let requests = await transport.requests
        #expect(requests.map(\.envelope.id) == [envelope.id])
    }

    @Test("remote send without transport fails explicitly")
    func remoteSendWithoutTransportFails() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let senderAddress = Address.local(dirs[0].path)
        let sender = try await Varta(
            address: senderAddress,
            serviceRoot: makeServiceRoot(for: dirs)
        )
        let envelope = Envelope(
            from: senderAddress,
            to: .peer("peer-2", path: "/remote/mailbox"),
            mediaType: "text/plain",
            data: Data("remote".utf8)
        )

        do {
            _ = try await sender.send(envelope)
            Issue.record("remote delivery without transport must fail")
        } catch let error as MessagingError {
            if case .remoteTransportUnavailable(let host) = error {
                #expect(host == "peer:peer-2")
            } else {
                Issue.record("unexpected MessagingError: \(error)")
            }
        }
    }

    @Test("remote service stores allowed deliveries into local filesystem")
    func remoteServiceStoresAllowedDelivery() async throws {
        let dirs = try makeTempMailboxes(count: 1)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let registrar = try await Varta(serviceRoot: serviceRoot)
        _ = try await registrar.registerMailbox(.local(dirs[0].path))
        let service = VartaService(
            serviceRoot: serviceRoot,
            allowedMailboxRoots: [dirs[0]]
        )
        let envelope = Envelope(
            from: .peer("sender", path: "/reply"),
            to: .peer("receiver", path: dirs[0].path),
            mediaType: "text/plain",
            data: Data("hello".utf8)
        )

        let response = await service.acceptRemoteDelivery(
            RemoteEnvelopeDeliveryRequest(envelope: envelope)
        )

        #expect(response.accepted)
        let actor = try await Varta(address: .local(dirs[0].path), serviceRoot: serviceRoot)
        let received = try await actor.receive()
        #expect(received.map(\.id) == [envelope.id])
    }

    @Test("remote service rejects paths outside allowed roots")
    func remoteServiceRejectsUnauthorizedPath() async throws {
        let allowed = try makeTempMailboxes(count: 1)
        let denied = try makeTempMailboxes(count: 1)
        defer {
            cleanup(allowed)
            cleanup(denied)
        }
        let service = VartaService(
            serviceRoot: makeServiceRoot(for: allowed + denied),
            allowedMailboxRoots: [allowed[0]]
        )
        let envelope = Envelope(
            from: .peer("sender", path: "/reply"),
            to: .peer("receiver", path: denied[0].path),
            mediaType: "text/plain",
            data: Data("hello".utf8)
        )

        let response = await service.acceptRemoteDelivery(
            RemoteEnvelopeDeliveryRequest(envelope: envelope)
        )

        #expect(!response.accepted)
        #expect(response.error == .unauthorizedPath)
    }

    @Test("duplicate envelope ids are rejected instead of overwritten")
    func duplicateEnvelopeRejected() async throws {
        let dirs = try makeTempMailboxes(count: 2)
        defer { cleanup(dirs) }
        let serviceRoot = makeServiceRoot(for: dirs)
        let sender = try await Varta(address: .local(dirs[0].path), serviceRoot: serviceRoot)
        _ = try await sender.registerMailbox(.local(dirs[1].path))
        let id = UUID()
        let first = Envelope(
            id: id,
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("first".utf8)
        )
        let second = Envelope(
            id: id,
            from: .local(dirs[0].path),
            to: .local(dirs[1].path),
            mediaType: "text/plain",
            data: Data("second".utf8)
        )
        try await sender.send(first)

        do {
            _ = try await sender.send(second)
            Issue.record("duplicate delivery must fail")
        } catch let error as MessagingError {
            if case .duplicateEnvelope(let duplicateID) = error {
                #expect(duplicateID == id)
            } else {
                Issue.record("unexpected MessagingError: \(error)")
            }
        }

        let recipient = try await Varta(address: .local(dirs[1].path), serviceRoot: serviceRoot)
        let received = try await recipient.receive()
        #expect(received.count == 1)
        #expect(received.first?.data == Data("first".utf8))
    }
}

// MARK: - Helpers

private func makeTempMailboxes(
    count: Int,
    instantiate: Bool = true
) throws -> [URL] {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("VartaTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    var urls: [URL] = []
    for i in 0..<count {
        let url = base.appendingPathComponent("mailbox-\(i)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        urls.append(url)
    }
    _ = instantiate
    return urls
}

private func makeServiceRoot(for urls: [URL]) -> URL {
    let base = urls.first?.deletingLastPathComponent()
        ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Messaging", isDirectory: true)
}

private func startVartad(
    serviceRoot: URL,
    echoPath: String,
    pidFile: URL
) throws -> Process {
    let process = Process()
    process.executableURL = try vartadExecutableURL()
    process.arguments = [
        "--service-root", serviceRoot.path(percentEncoded: false),
        "--pid-file", pidFile.path(percentEncoded: false),
        "--poll-ms", "25",
        "--e2e-echo", echoPath
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    return process
}

private func vartadExecutableURL() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("debug", isDirectory: true)
        .appendingPathComponent("vartad", isDirectory: false)
    guard FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
        throw TestSupportError.missingExecutable(url)
    }
    return url
}

private func waitUntilFileExists(
    _ url: URL,
    timeoutSeconds: TimeInterval = 5
) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw TestSupportError.timeout("file did not appear: \(url.path(percentEncoded: false))")
}

private func waitForEnvelope(
    at address: Address,
    serviceRoot: URL,
    timeoutSeconds: TimeInterval = 5,
    matching predicate: (Envelope) -> Bool
) async throws -> Envelope {
    let client = MessagingFilesystemClient(serviceRoot: serviceRoot)
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        let envelopes = try client.receive(at: address)
        if let envelope = envelopes.first(where: predicate) {
            return envelope
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw TestSupportError.timeout("envelope did not arrive at \(address.path)")
}

private func stop(_ process: Process) {
    guard process.isRunning else {
        return
    }
    process.terminate()
}

private func cleanup(_ urls: [URL]) {
    for url in urls {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
        }
    }
    if let parent = urls.first?.deletingLastPathComponent() {
        do {
            try FileManager.default.removeItem(at: parent)
        } catch {
        }
    }
}

private enum TestSupportError: Error, CustomStringConvertible {
    case missingExecutable(URL)
    case timeout(String)

    var description: String {
        switch self {
        case .missingExecutable(let url):
            return "missing executable: \(url.path(percentEncoded: false))"
        case .timeout(let message):
            return message
        }
    }
}

private actor RecordingRemoteTransport: RemoteMailboxTransport {
    private(set) var requests: [RemoteEnvelopeDeliveryRequest] = []
    private let response: RemoteEnvelopeDeliveryResponse

    init(response: RemoteEnvelopeDeliveryResponse) {
        self.response = response
    }

    func deliver(
        _ request: RemoteEnvelopeDeliveryRequest
    ) async throws -> RemoteEnvelopeDeliveryResponse {
        requests.append(request)
        return response
    }
}
