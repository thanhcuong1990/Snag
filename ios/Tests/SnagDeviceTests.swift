import XCTest
@testable import Snag

final class SnagDeviceTests: XCTestCase {

    func testHostMachineIsEncodedUnderTheKeyTheDesktopDecodes() throws {
        var device = SnagDevice()
        device.id = "abc"
        device.name = "iPhone 18 Pro - RN"
        device.hostMachine = "mini.local"

        let data = try JSONEncoder().encode(device)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["hostMachine"] as? String, "mini.local")
        XCTAssertEqual(json["deviceName"] as? String, "iPhone 18 Pro - RN")
    }

    func testHostMachineSurvivesRoundTrip() throws {
        var device = SnagDevice()
        device.hostMachine = "mini.local"

        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(SnagDevice.self, from: data)

        XCTAssertEqual(decoded.hostMachine, "mini.local")
    }

    func testHostMachineIsOmittedWhenAbsent() throws {
        let device = SnagDevice()

        let data = try JSONEncoder().encode(device)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["hostMachine"])
    }

    func testPayloadWithoutHostMachineStillDecodes() throws {
        let payload = Data(#"{"deviceId":"abc","deviceName":"iPhone"}"#.utf8)

        let decoded = try JSONDecoder().decode(SnagDevice.self, from: payload)

        XCTAssertEqual(decoded.id, "abc")
        XCTAssertNil(decoded.hostMachine)
    }
}
