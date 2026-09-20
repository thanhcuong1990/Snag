import XCTest
@testable import Snag

final class LocalMachineTests: XCTestCase {

    func testPhysicalDeviceReportingNoHostMachineIsNeverRemote() {
        XCTAssertFalse(LocalMachine.isRemote(nil))
        XCTAssertFalse(LocalMachine.isRemote(""))
        XCTAssertFalse(LocalMachine.isRemote("   "))
    }

    func testPhysicalDeviceHasNoHostLabel() {
        XCTAssertNil(LocalMachine.label(for: nil))
        XCTAssertNil(LocalMachine.label(for: ""))
    }

    func testSimulatorOnThisMacIsNotRemote() {
        XCTAssertFalse(LocalMachine.isRemote(LocalMachine.name))
    }

    func testBonjourSuffixAndCaseAreIgnoredWhenMatching() {
        let bare = LocalMachine.displayName(LocalMachine.name) ?? ""
        XCTAssertFalse(bare.isEmpty)
        XCTAssertFalse(LocalMachine.isRemote(bare))
        XCTAssertFalse(LocalMachine.isRemote(bare.uppercased()))
        XCTAssertFalse(LocalMachine.isRemote("\(bare).local"))
    }

    func testSimulatorOnAnotherMacIsRemote() {
        XCTAssertTrue(LocalMachine.isRemote("some-other-machine.local"))
        XCTAssertEqual(LocalMachine.label(for: "some-other-machine.local"), "some-other-machine")
    }

    func testLocalSimulatorIsLabelledThisMac() {
        XCTAssertEqual(LocalMachine.label(for: LocalMachine.name), "This Mac".localized)
    }

    func testDisplayNameStripsOnlyTrailingLocalSuffix() {
        XCTAssertEqual(LocalMachine.displayName("mini.local"), "mini")
        XCTAssertEqual(LocalMachine.displayName("local.mini"), "local.mini")
        XCTAssertEqual(LocalMachine.displayName("  mini.local  "), "mini")
    }
}
