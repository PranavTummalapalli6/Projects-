import Foundation

public struct ClusterItem<ID: Hashable & Sendable>: Hashable, Sendable {
    public var id: ID
    public var point: GeoPoint
    public init(id: ID, point: GeoPoint) { self.id = id; self.point = point }
}

public struct MapCluster<ID: Hashable & Sendable>: Hashable, Sendable, Identifiable {
    public var memberIDs: [ID]
    public var center: GeoPoint
    public var isSingle: Bool { memberIDs.count == 1 }
    /// Stable id derived from members so SwiftUI animates correctly.
    public var id: String { memberIDs.map { "\($0)" }.sorted().joined(separator: "|") }
}

/// Grid clustering in coordinate space scaled to the visible span. Cheap, deterministic, testable.
public enum FacilityClusterer {
    /// - Parameter cellsAcross: roughly how many marker "slots" fit across the screen.
    public static func cluster<ID>(_ items: [ClusterItem<ID>], visible: GeoBoundingBox, cellsAcross: Double = 7) -> [MapCluster<ID>] {
        guard !items.isEmpty else { return [] }
        let cellLng = max(visible.longitudeDelta / cellsAcross, 1e-6)
        let cellLat = max(visible.latitudeDelta / (cellsAcross * 1.6), 1e-6)
        var buckets: [String: [ClusterItem<ID>]] = [:]
        for item in items {
            let x = Int(floor(item.point.longitude / cellLng))
            let y = Int(floor(item.point.latitude / cellLat))
            buckets["\(x):\(y)", default: []].append(item)
        }
        return buckets.values.map { members in
            let lat = members.reduce(0) { $0 + $1.point.latitude } / Double(members.count)
            let lng = members.reduce(0) { $0 + $1.point.longitude } / Double(members.count)
            return MapCluster(memberIDs: members.map(\.id), center: GeoPoint(latitude: lat, longitude: lng))
        }
        .sorted { $0.id < $1.id }
    }
}
