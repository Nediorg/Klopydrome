import XCTest
@testable import Klopydrome

final class AutomixCrossfadeTests: XCTestCase {
    func testEqualPowerGainsStartWithOutgoingTrackOnly() {
        let gains = AutomixCrossfade.gains(progress: 0)

        XCTAssertEqual(gains.outgoing, 1, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 0, accuracy: 0.000_1)
    }

    func testEqualPowerGainsPreserveEnergyAtMidpoint() {
        let gains = AutomixCrossfade.gains(progress: 0.5)

        XCTAssertEqual(gains.outgoing, 0.707_106_8, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 0.707_106_8, accuracy: 0.000_1)
    }

    func testEqualPowerGainsEndWithIncomingTrackOnly() {
        let gains = AutomixCrossfade.gains(progress: 1)

        XCTAssertEqual(gains.outgoing, 0, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 1, accuracy: 0.000_1)
    }

    func testGainsClampProgressOutsideTransition() {
        XCTAssertEqual(AutomixCrossfade.gains(progress: -1).outgoing, 1)
        XCTAssertEqual(AutomixCrossfade.gains(progress: 2).incoming, 1)
    }
}
