import XCTest
@testable import Snag

final class CaptureCommandTests: XCTestCase {

    private func parse(_ string: String) -> Result<CaptureCommand.Envelope, CaptureCommand.ParseError> {
        CaptureCommand.parse(URL(string: string)!)
    }

    func testStartCarriesEveryOption() throws {
        let envelope = try parse(
            "snag://capture/start?folder=%2Ftmp%2Fcaps&host=api-staging.communa.sg"
                + "&device=iPhone%2018%20Pro&bundle=sg.communa.staging&append=1&req=abc-123"
        ).get()

        XCTAssertEqual(envelope.requestId, "abc-123")
        XCTAssertEqual(envelope.command, .start(CaptureStartOptions(
            folder: "/tmp/caps",
            hostFilter: "api-staging.communa.sg",
            scope: CaptureScope(device: "iPhone 18 Pro", bundleId: "sg.communa.staging"),
            append: true
        )))
    }

    func testStartDefaultsToEverythingWithoutAppend() throws {
        let envelope = try parse("snag://capture/start?folder=%2Ftmp%2Fcaps").get()

        XCTAssertNil(envelope.requestId)
        XCTAssertEqual(envelope.command, .start(CaptureStartOptions(
            folder: "/tmp/caps", hostFilter: "", scope: .everything, append: false
        )))
    }

    func testStartExpandsTilde() throws {
        let envelope = try parse("snag://capture/start?folder=~%2Fcaps").get()

        guard case .start(let options) = envelope.command else { return XCTFail("expected start") }
        XCTAssertEqual(options.folder, (NSHomeDirectory() as NSString).appendingPathComponent("caps"))
    }

    func testStartWithoutFolderIsRejected() {
        XCTAssertEqual(parse("snag://capture/start?host=communa.sg"), .failure(.missingFolder))
    }

    func testStopAndStatus() throws {
        XCTAssertEqual(try parse("snag://capture/stop?req=1").get(), .init(command: .stop, requestId: "1"))
        XCTAssertEqual(try parse("snag://capture/status").get(), .init(command: .status, requestId: nil))
    }

    func testUnknownActionAndForeignURLsAreRejected() {
        XCTAssertEqual(parse("snag://capture/pause"), .failure(.unknownAction("pause")))
        XCTAssertEqual(parse("snag://export/start?folder=x"), .failure(.notACaptureURL))
        XCTAssertEqual(parse("https://capture/start?folder=x"), .failure(.notACaptureURL))
    }
}

final class CaptureScopeTests: XCTestCase {

    func testEmptyScopeMatchesEverything() {
        XCTAssertTrue(CaptureScope.everything.matches(deviceId: nil, deviceName: nil, bundleId: nil))
    }

    func testDeviceNameMatchesExactlyNotByPrefix() {
        let scope = CaptureScope(device: "iPhone 18 Pro")

        XCTAssertTrue(scope.matches(deviceId: "A1", deviceName: "iPhone 18 Pro", bundleId: nil))
        XCTAssertTrue(scope.matches(deviceId: "A1", deviceName: "iphone 18 pro", bundleId: nil))
        XCTAssertFalse(scope.matches(deviceId: "B2", deviceName: "iPhone 18 Pro - RN", bundleId: nil))
        XCTAssertFalse(scope.matches(deviceId: "C3", deviceName: nil, bundleId: nil))
    }

    func testDeviceIdMatches() {
        let scope = CaptureScope(device: "ABCD-1234")

        XCTAssertTrue(scope.matches(deviceId: "abcd-1234", deviceName: "iPhone 18 Pro", bundleId: nil))
        XCTAssertFalse(scope.matches(deviceId: "abcd-12345", deviceName: "iPhone 18 Pro", bundleId: nil))
    }

    func testBundleIdMustMatchWhenSet() {
        let scope = CaptureScope(device: "iPhone 18 Pro", bundleId: "sg.communa.staging")

        XCTAssertTrue(scope.matches(deviceId: nil, deviceName: "iPhone 18 Pro", bundleId: "sg.communa.staging"))
        XCTAssertFalse(scope.matches(deviceId: nil, deviceName: "iPhone 18 Pro", bundleId: "sg.communa"))
        XCTAssertFalse(scope.matches(deviceId: nil, deviceName: "iPhone 18 Pro", bundleId: nil))
    }
}

final class CaptureFolderTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    func testEmptyFolderStartsAtZero() {
        XCTAssertEqual(CaptureFolder.highestSequence(in: folder), 0)
        XCTAssertFalse(CaptureFolder.hasVisibleContents(folder))
    }

    func testHighestSequenceReadsCapturePrefixesOnly() throws {
        try touch("0001-v4-posts.json")
        try touch("0001-v4-posts.meta.json")
        try touch("0012-detail.json")
        try touch("notes.txt")
        try touch("12-short.json")

        XCTAssertEqual(CaptureFolder.highestSequence(in: folder), 12)
    }

    func testHiddenFilesDoNotCountAsContents() throws {
        try touch(".DS_Store")
        XCTAssertFalse(CaptureFolder.hasVisibleContents(folder))

        try touch("0001-a.json")
        XCTAssertTrue(CaptureFolder.hasVisibleContents(folder))
    }
}
