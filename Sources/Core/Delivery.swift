import Foundation

struct Stop: Codable, Identifiable, Equatable {
  let id: String
  let business: String
  let address: String
  let latitude, longitude: Double
  var status = "Assigned"
  var recipient = ""
  var note = ""
  var proof: Data?
  var completedAt: Date?
  mutating func arrive() { if status == "Assigned" { status = "Arrived" } }
  mutating func complete(recipient: String, note: String, proof: Data?, at date: Date = Date())
    throws
  {
    guard status == "Arrived", !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let proof, !proof.isEmpty, proof.count <= 5_000_000
    else { throw DeliveryError.invalidProof }
    self.recipient = recipient
    self.note = note
    self.proof = proof
    self.completedAt = date
    status = "Delivered"
  }
  static let sample = [
    Stop(
      id: "DC-1041", business: "North Beach Studio", address: "535 Columbus Ave, San Francisco",
      latitude: 37.7991, longitude: -122.4085),
    Stop(
      id: "DC-1042", business: "Marina Workshop", address: "2300 Chestnut St, San Francisco",
      latitude: 37.8007, longitude: -122.4412),
    Stop(
      id: "DC-1043", business: "Sunset Books", address: "1231 9th Ave, San Francisco",
      latitude: 37.7655, longitude: -122.4666),
  ]
}
enum DeliveryError: LocalizedError {
  case invalidProof
  var errorDescription: String? {
    "Arrive first, then enter the recipient and attach a photo under 5 MB."
  }
}
