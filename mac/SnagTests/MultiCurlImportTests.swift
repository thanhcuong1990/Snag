import XCTest
@testable import Snag

@MainActor
final class MultiCurlImportTests: XCTestCase {

    // MARK: - Detection

    func testDetectsTwoCurlCommandsSeparatedByBlankLine() {
        let input = """
        curl https://x.test/a

        curl https://x.test/b
        """
        XCTAssertEqual(MultiCurlImporter.curlCommandCount(input), 2)
    }

    func testDetectsThreeCurlCommands() {
        let input = """
        curl https://x.test/1

        curl -X POST https://x.test/2

        curl -H 'X-A: 1' https://x.test/3
        """
        XCTAssertEqual(MultiCurlImporter.curlCommandCount(input), 3)
    }

    func testSingleCurlCountsAsOne() {
        let input = "curl https://x.test/"
        XCTAssertEqual(MultiCurlImporter.curlCommandCount(input), 1)
    }

    func testNonCurlContentCountsAsZero() {
        let input = "{ \"info\": {}, \"item\": [] }"
        XCTAssertEqual(MultiCurlImporter.curlCommandCount(input), 0)
    }

    // MARK: - Parse: Plan §7 — "3 commands separated by blank lines → 3 drafts"

    func testThreeBlankSeparatedCommandsProduceThreeRequests() throws {
        let input = """
        curl https://x.test/a

        curl -X POST https://x.test/b -d 'q=1'

        curl -H 'X-Hdr: v' https://x.test/c
        """
        let batch = try MultiCurlImporter.parse(.text(input), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 3)
        XCTAssertEqual(batch.requests[0].draftData.method, "GET")
        XCTAssertEqual(batch.requests[1].draftData.method, "POST")
        XCTAssertTrue(batch.requests[2].draftData.headers.contains { $0.key == "X-Hdr" && $0.value == "v" })
        XCTAssertNil(batch.folders, "multi-curl batches are flat")
    }

    // MARK: - Parse: Plan §7 — "1 bad chunk among 3 → 2 success rows + 1 warning row"

    func testOneBadChunkAmongThreeProducesWarningRowButBatchSurvives() throws {
        let input = """
        curl https://x.test/ok-1

        curl 'unterminated

        curl https://x.test/ok-2
        """
        let batch = try MultiCurlImporter.parse(.text(input), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 3)

        // Two good rows have valid URLs and no warnings.
        XCTAssertEqual(batch.requests[0].draftData.url, "https://x.test/ok-1")
        XCTAssertTrue(batch.requests[0].warnings.isEmpty)

        // Middle row is the placeholder with a parse-error warning.
        XCTAssertEqual(batch.requests[1].draftData.url, "")
        XCTAssertFalse(batch.requests[1].warnings.isEmpty)
        XCTAssertTrue(batch.requests[1].warnings.first?.contains("Parse error") == true)

        XCTAssertEqual(batch.requests[2].draftData.url, "https://x.test/ok-2")
        XCTAssertTrue(batch.requests[2].warnings.isEmpty)
    }

    // MARK: - Continuation lines stay inside one chunk

    func testLineContinuationStaysInsideOneChunk() throws {
        let input = """
        curl -X POST \\
          -H 'X-One: 1' \\
          https://x.test/a

        curl https://x.test/b
        """
        let batch = try MultiCurlImporter.parse(.text(input), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 2)
        XCTAssertEqual(batch.requests[0].draftData.method, "POST")
        XCTAssertTrue(batch.requests[0].draftData.headers.contains { $0.key == "X-One" })
    }

    // MARK: - canHandle

    func testCanHandleRequiresAtLeastTwoCurls() {
        XCTAssertFalse(MultiCurlImporter.canHandle(.text("curl https://x.test/")))
        XCTAssertTrue(MultiCurlImporter.canHandle(.text("curl https://x.test/a\n\ncurl https://x.test/b")))
    }
}
