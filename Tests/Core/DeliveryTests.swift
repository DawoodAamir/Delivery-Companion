import XCTest

@testable import DeliveryCore

final class DeliveryTests: XCTestCase {
  func testProofRequiresArrivalAndPhoto() throws {
    var stop = Stop.sample[0]
    XCTAssertThrowsError(try stop.complete(recipient: "Alex", note: "", proof: Data([1])))
    stop.arrive()
    XCTAssertThrowsError(try stop.complete(recipient: "", note: "", proof: Data([1])))
    XCTAssertThrowsError(try stop.complete(recipient: "Alex", note: "", proof: nil))
    try stop.complete(
      recipient: "Alex", note: "Front desk", proof: Data([1]), at: Date(timeIntervalSince1970: 1))
    XCTAssertEqual(stop.status, "Delivered")
    stop.arrive()
    XCTAssertEqual(stop.status, "Delivered")
  }
  func testProofSurvivesRelaunch() throws {
    var stop = Stop.sample[0]
    stop.arrive()
    try stop.complete(recipient: "Alex", note: "", proof: Data([1, 2]))
    XCTAssertEqual(try JSONDecoder().decode(Stop.self, from: JSONEncoder().encode(stop)), stop)
  }
}
