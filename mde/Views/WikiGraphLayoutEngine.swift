//
//  WikiGraphLayoutEngine.swift
//  MDE
//

import CoreGraphics
import Foundation

/// Display node for the wiki-link graph canvas (includes unresolved link targets).
struct WikiGraphDisplayNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let isUnresolved: Bool
    let linkCount: Int
    var position: CGPoint

    var radius: CGFloat {
        let base: CGFloat = isUnresolved ? 10 : 12
        return base + CGFloat(min(linkCount, 8)) * 1.5
    }
}

struct WikiGraphDisplayEdge: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let isUnresolved: Bool
}

struct WikiGraphLayoutResult: Equatable, Sendable {
    var nodes: [WikiGraphDisplayNode]
    var edges: [WikiGraphDisplayEdge]
}

enum WikiGraphLayoutMode: String, CaseIterable, Identifiable {
    case forceDirected
    case circular

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forceDirected: return "Force"
        case .circular: return "Circle"
        }
    }
}

enum WikiGraphLayoutEngine {
    static let unresolvedIDPrefix = "unresolved:"

    static func unresolvedNodeID(for title: String) -> String {
        unresolvedIDPrefix + title.lowercased()
    }

    static func buildDisplayGraph(
        nodes: [WikiGraphNode],
        edges: [WikiGraphEdge]
    ) -> (nodes: [WikiGraphDisplayNode], edges: [WikiGraphDisplayEdge]) {
        var degree: [String: Int] = [:]
        var displayEdges: [WikiGraphDisplayEdge] = []
        var nodeByID: [String: WikiGraphNode] = [:]
        for node in nodes {
            nodeByID[node.id] = node
        }

        var unresolvedTitles: [String: String] = [:]

        for edge in edges {
            let targetID: String
            let isUnresolved: Bool
            if let resolved = edge.targetID {
                targetID = resolved
                isUnresolved = false
            } else {
                let key = edge.targetTitle.lowercased()
                targetID = unresolvedNodeID(for: edge.targetTitle)
                unresolvedTitles[key] = edge.targetTitle
                isUnresolved = true
            }

            displayEdges.append(WikiGraphDisplayEdge(
                id: edge.id,
                sourceID: edge.sourceID,
                targetID: targetID,
                isUnresolved: isUnresolved
            ))

            degree[edge.sourceID, default: 0] += 1
            degree[targetID, default: 0] += 1
        }

        var displayNodes: [WikiGraphDisplayNode] = nodes.map { node in
            WikiGraphDisplayNode(
                id: node.id,
                title: node.title,
                isUnresolved: false,
                linkCount: degree[node.id, default: 0],
                position: .zero
            )
        }

        for title in unresolvedTitles.values.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let nodeID = unresolvedNodeID(for: title)
            displayNodes.append(WikiGraphDisplayNode(
                id: nodeID,
                title: title,
                isUnresolved: true,
                linkCount: degree[nodeID, default: 0],
                position: .zero
            ))
        }

        return (displayNodes, displayEdges)
    }

    static func layout(
        nodes: [WikiGraphDisplayNode],
        edges: [WikiGraphDisplayEdge],
        in size: CGSize,
        mode: WikiGraphLayoutMode,
        pinnedPositions: [String: CGPoint] = [:],
        seed: UInt64 = 0xC0FFEE
    ) -> WikiGraphLayoutResult {
        guard !nodes.isEmpty, size.width > 1, size.height > 1 else {
            return WikiGraphLayoutResult(nodes: [], edges: edges)
        }

        var positioned = nodes
        switch mode {
        case .circular:
            applyCircularLayout(to: &positioned, in: size)
        case .forceDirected:
            applyForceDirectedLayout(to: &positioned, edges: edges, in: size, seed: seed)
        }

        for index in positioned.indices {
            if let pinned = pinnedPositions[positioned[index].id] {
                positioned[index].position = pinned
            }
        }

        return WikiGraphLayoutResult(nodes: positioned, edges: edges)
    }

    static func visibleGraph(
        result: WikiGraphLayoutResult,
        focusNodeID: String?,
        focusEnabled: Bool
    ) -> WikiGraphLayoutResult {
        guard focusEnabled, let focusNodeID else { return result }

        var neighborIDs = Set<String>([focusNodeID])
        for edge in result.edges {
            if edge.sourceID == focusNodeID {
                neighborIDs.insert(edge.targetID)
            }
            if edge.targetID == focusNodeID {
                neighborIDs.insert(edge.sourceID)
            }
        }

        let filteredNodes = result.nodes.filter { neighborIDs.contains($0.id) }
        let filteredEdges = result.edges.filter {
            neighborIDs.contains($0.sourceID) && neighborIDs.contains($0.targetID)
        }
        return WikiGraphLayoutResult(nodes: filteredNodes, edges: filteredEdges)
    }

    static func fitTransform(
        for nodes: [WikiGraphDisplayNode],
        in viewport: CGSize,
        padding: CGFloat = 40
    ) -> WikiGraphViewportTransform {
        guard let first = nodes.first else {
            return .identity
        }

        var minX = first.position.x
        var maxX = first.position.x
        var minY = first.position.y
        var maxY = first.position.y

        for node in nodes {
            let r = node.radius
            minX = min(minX, node.position.x - r)
            maxX = max(maxX, node.position.x + r)
            minY = min(minY, node.position.y - r)
            maxY = max(maxY, node.position.y + r)
        }

        let graphWidth = max(maxX - minX, 1)
        let graphHeight = max(maxY - minY, 1)
        let availableWidth = max(viewport.width - padding * 2, 1)
        let availableHeight = max(viewport.height - padding * 2, 1)
        let scale = min(availableWidth / graphWidth, availableHeight / graphHeight, 2.5)

        let graphCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let viewCenter = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let translation = CGSize(
            width: viewCenter.x - graphCenter.x * scale,
            height: viewCenter.y - graphCenter.y * scale
        )

        return WikiGraphViewportTransform(scale: scale, translation: translation)
    }

    static func hitTest(
        point: CGPoint,
        nodes: [WikiGraphDisplayNode],
        transform: WikiGraphViewportTransform
    ) -> String? {
        let graphPoint = transform.viewToGraph(point)
        for node in nodes.reversed() {
            let distance = hypot(node.position.x - graphPoint.x, node.position.y - graphPoint.y)
            if distance <= node.radius + 4 {
                return node.id
            }
        }
        return nil
    }

    // MARK: - Layout algorithms

    private static func applyCircularLayout(to nodes: inout [WikiGraphDisplayNode], in size: CGSize) {
        let radius = min(size.width, size.height) * 0.35
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = nodes.count
        for index in nodes.indices {
            let angle = (Double(index) / Double(count)) * 2 * Double.pi
            nodes[index].position = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
    }

    private static func applyForceDirectedLayout(
        to nodes: inout [WikiGraphDisplayNode],
        edges: [WikiGraphDisplayEdge],
        in size: CGSize,
        seed: UInt64
    ) {
        let count = nodes.count
        guard count > 0 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let orbit = min(size.width, size.height) * 0.38
        var rng = SeededRNG(seed: seed)

        for index in nodes.indices {
            let angle = (Double(index) / Double(count)) * 2 * Double.pi + rng.nextUnit() * 0.2
            let jitter = CGFloat(0.85 + rng.nextUnit() * 0.3)
            nodes[index].position = CGPoint(
                x: center.x + CGFloat(cos(angle)) * orbit * jitter,
                y: center.y + CGFloat(sin(angle)) * orbit * jitter
            )
        }

        var velocities = [CGPoint](repeating: .zero, count: count)
        let idToIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let iterations = min(140, 60 + count)

        let repulsionStrength = 9_000 * max(1, CGFloat(count) / 12)
        let attractionStrength: CGFloat = 0.045
        let idealLength = max(48, min(size.width, size.height) / max(6, CGFloat(count).squareRoot() * 1.4))
        let damping: CGFloat = 0.82
        let maxVelocity: CGFloat = 18

        for _ in 0..<iterations {
            var forces = [CGPoint](repeating: .zero, count: count)

            for i in 0..<count {
                for j in (i + 1)..<count {
                    let dx = nodes[j].position.x - nodes[i].position.x
                    let dy = nodes[j].position.y - nodes[i].position.y
                    let distance = max(hypot(dx, dy), 0.01)
                    let force = repulsionStrength / (distance * distance)
                    let fx = force * dx / distance
                    let fy = force * dy / distance
                    forces[i].x -= fx
                    forces[i].y -= fy
                    forces[j].x += fx
                    forces[j].y += fy
                }
            }

            for edge in edges {
                guard let sourceIndex = idToIndex[edge.sourceID],
                      let targetIndex = idToIndex[edge.targetID]
                else { continue }

                let dx = nodes[targetIndex].position.x - nodes[sourceIndex].position.x
                let dy = nodes[targetIndex].position.y - nodes[sourceIndex].position.y
                let distance = max(hypot(dx, dy), 0.01)
                let displacement = distance - idealLength
                let force = attractionStrength * displacement
                let fx = force * dx / distance
                let fy = force * dy / distance
                forces[sourceIndex].x += fx
                forces[sourceIndex].y += fy
                forces[targetIndex].x -= fx
                forces[targetIndex].y -= fy
            }

            for index in nodes.indices {
                let toCenterX = center.x - nodes[index].position.x
                let toCenterY = center.y - nodes[index].position.y
                forces[index].x += toCenterX * 0.002
                forces[index].y += toCenterY * 0.002

                velocities[index].x = (velocities[index].x + forces[index].x) * damping
                velocities[index].y = (velocities[index].y + forces[index].y) * damping
                let speed = hypot(velocities[index].x, velocities[index].y)
                if speed > maxVelocity {
                    velocities[index].x *= maxVelocity / speed
                    velocities[index].y *= maxVelocity / speed
                }

                nodes[index].position.x += velocities[index].x
                nodes[index].position.y += velocities[index].y
            }
        }

        let padding: CGFloat = 32
        for index in nodes.indices {
            nodes[index].position.x = min(max(nodes[index].position.x, padding), size.width - padding)
            nodes[index].position.y = min(max(nodes[index].position.y, padding), size.height - padding)
        }
    }
}

struct WikiGraphViewportTransform: Equatable, Sendable {
    var scale: CGFloat
    var translation: CGSize

    static let identity = WikiGraphViewportTransform(scale: 1, translation: .zero)

    func graphToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + translation.width,
            y: point.y * scale + translation.height
        )
    }

    func viewToGraph(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - translation.width) / scale,
            y: (point.y - translation.height) / scale
        )
    }
}

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double(z ^ (z >> 31)) / Double(UInt64.max)
    }
}
