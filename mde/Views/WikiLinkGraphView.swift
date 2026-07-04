//
//  WikiLinkGraphView.swift
//  MDE
//

import SwiftUI

struct WikiLinkGraphView: View {
    let store: VaultStore
    @Binding var selectedNoteID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var graphSearchText = ""
    @State private var rawNodes: [WikiGraphNode] = []
    @State private var rawEdges: [WikiGraphEdge] = []
    @State private var layoutResult = WikiGraphLayoutResult(nodes: [], edges: [])
    @State private var layoutMode: WikiGraphLayoutMode = .forceDirected
    @State private var focusNeighbors = false
    @State private var viewportTransform = WikiGraphViewportTransform.identity
    @State private var gestureScale: CGFloat = 1
    @State private var gestureTranslation = CGSize.zero
    @State private var pinnedPositions: [String: CGPoint] = [:]
    @State private var draggedNodeID: String?
    @State private var dragOriginGraphPoint: CGPoint?
    @State private var canvasSize = CGSize(width: 480, height: 360)
    @State private var errorMessage: String?

    private var displayGraph: WikiGraphLayoutResult {
        let base = WikiGraphLayoutEngine.visibleGraph(
            result: layoutResult,
            focusNodeID: selectedNoteID,
            focusEnabled: focusNeighbors
        )
        let trimmed = graphSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let lowered = trimmed.lowercased()
        let matchingIDs = Set(base.nodes.filter { $0.title.lowercased().contains(lowered) }.map(\.id))
        let filteredNodes = base.nodes.filter { matchingIDs.contains($0.id) }
        let filteredEdges = base.edges.filter {
            matchingIDs.contains($0.sourceID) && matchingIDs.contains($0.targetID)
        }
        return WikiGraphLayoutResult(nodes: filteredNodes, edges: filteredEdges)
    }

    private var linkedNoteCount: Int {
        layoutResult.nodes.filter { !$0.isUnresolved }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if rawEdges.isEmpty {
                ContentUnavailableView(
                    "No links yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Add [[WikiLinks]] between notes to see the graph.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                graphCanvas
                    .frame(minHeight: 360)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomLeading) { legend }
                footer
            }
        }
        .padding()
        .onAppear(perform: reload)
        .onChange(of: layoutMode) { _, _ in recomputeLayout() }
        .onChange(of: focusNeighbors) { _, _ in fitGraphToView() }
        .onChange(of: selectedNoteID) { _, _ in
            if focusNeighbors { fitGraphToView() }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Link Graph")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            TextField("Find node", text: $graphSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
                .accessibilityLabel("Search graph nodes")

            Picker("Layout", selection: $layoutMode) {
                ForEach(WikiGraphLayoutMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .accessibilityLabel(AccessibilityLabels.graphLayoutPicker)

            Toggle(isOn: $focusNeighbors) {
                Image(systemName: "scope")
            }
            .toggleStyle(.button)
            .help("Focus on selected note and neighbors")
            .accessibilityLabel(AccessibilityLabels.graphFocusToggle)

            Button {
                fitGraphToView()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit graph to view")
            .accessibilityLabel(AccessibilityLabels.graphFitView)

            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload graph")
            .accessibilityLabel(AccessibilityLabels.graphReload)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(linkedNoteCount) notes · \(layoutResult.edges.count) links")
            if layoutResult.nodes.contains(where: \.isUnresolved) {
                Text("·")
                Text("\(layoutResult.nodes.filter(\.isUnresolved).count) unresolved")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let selectedNoteID,
               let title = layoutResult.nodes.first(where: { $0.id == selectedNoteID })?.title {
                Text("Selected: \(title.isEmpty ? "Untitled" : title)")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(color: .accentColor, label: "Note", dashed: false)
            legendRow(color: .orange, label: "Unresolved [[link]]", dashed: true)
        }
        .font(.caption2)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AccessibilityLabels.graphLegend)
    }

    private func legendRow(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .background(Circle().fill(color.opacity(0.15)))
                .frame(width: 10, height: 10)
            Text(label)
        }
    }

    private var graphCanvas: some View {
        GeometryReader { geometry in
            let graph = displayGraph
            let transform = composedTransform

            ZStack {
                Canvas { context, size in
                    drawEdges(context: &context, graph: graph, transform: transform, size: size)
                }

                Canvas { context, size in
                    drawEdgeArrows(context: &context, graph: graph, transform: transform)
                }
                .allowsHitTesting(false)

                ForEach(graph.nodes) { node in
                    nodeButton(node, transform: transform)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onAppear {
                canvasSize = geometry.size
                recomputeLayout()
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
                recomputeLayout()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AccessibilityLabels.graphCanvas)
        }
    }

    private var composedTransform: WikiGraphViewportTransform {
        WikiGraphViewportTransform(
            scale: viewportTransform.scale * gestureScale,
            translation: CGSize(
                width: viewportTransform.translation.width + gestureTranslation.width,
                height: viewportTransform.translation.height + gestureTranslation.height
            )
        )
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard draggedNodeID == nil else { return }
                gestureTranslation = value.translation
            }
            .onEnded { value in
                guard draggedNodeID == nil else { return }
                viewportTransform.translation.width += value.translation.width
                viewportTransform.translation.height += value.translation.height
                gestureTranslation = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = min(max(value, 0.35), 4)
            }
            .onEnded { _ in
                viewportTransform.scale *= gestureScale
                viewportTransform.scale = min(max(viewportTransform.scale, 0.35), 4)
                gestureScale = 1
            }
    }

    private func nodeButton(_ node: WikiGraphDisplayNode, transform: WikiGraphViewportTransform) -> some View {
        let viewPosition = transform.graphToView(node.position)
        let isSelected = selectedNoteID == node.id
        let isNeighbor = isNeighborOfSelection(node.id)

        return Button {
            if !node.isUnresolved {
                selectedNoteID = node.id
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(nodeFill(node: node, isSelected: isSelected, isNeighbor: isNeighbor))
                    Circle()
                        .strokeBorder(
                            nodeStroke(node: node, isSelected: isSelected),
                            style: StrokeStyle(
                                lineWidth: isSelected ? 2.5 : 1.5,
                                dash: node.isUnresolved ? [4, 3] : []
                            )
                        )
                    if node.linkCount > 0 {
                        Text("\(node.linkCount)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: node.radius * 2, height: node.radius * 2)

                Text(node.title.isEmpty ? "Untitled" : node.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 88)
                    .foregroundStyle(node.isUnresolved ? .orange : .primary)
            }
        }
        .buttonStyle(.plain)
        .position(viewPosition)
        .accessibilityLabel(AccessibilityLabels.graphNode(
            title: node.title.isEmpty ? "Untitled" : node.title,
            isUnresolved: node.isUnresolved,
            linkCount: node.linkCount
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    draggedNodeID = node.id
                    if dragOriginGraphPoint == nil {
                        dragOriginGraphPoint = node.position
                    }
                    guard let origin = dragOriginGraphPoint else { return }
                    let graphDelta = CGSize(
                        width: value.translation.width / transform.scale,
                        height: value.translation.height / transform.scale
                    )
                    pinnedPositions[node.id] = CGPoint(
                        x: origin.x + graphDelta.width,
                        y: origin.y + graphDelta.height
                    )
                    recomputeLayout()
                }
                .onEnded { _ in
                    draggedNodeID = nil
                    dragOriginGraphPoint = nil
                }
        )
    }

    private func nodeFill(node: WikiGraphDisplayNode, isSelected: Bool, isNeighbor: Bool) -> Color {
        if node.isUnresolved { return .orange.opacity(0.12) }
        if isSelected { return .accentColor.opacity(0.35) }
        if isNeighbor { return .accentColor.opacity(0.18) }
        return .accentColor.opacity(0.12)
    }

    private func nodeStroke(node: WikiGraphDisplayNode, isSelected: Bool) -> Color {
        if node.isUnresolved { return .orange }
        if isSelected { return .accentColor }
        return .accentColor.opacity(0.7)
    }

    private func isNeighborOfSelection(_ nodeID: String) -> Bool {
        guard let selectedNoteID, selectedNoteID != nodeID else { return false }
        return layoutResult.edges.contains {
            ($0.sourceID == selectedNoteID && $0.targetID == nodeID)
                || ($0.targetID == selectedNoteID && $0.sourceID == nodeID)
        }
    }

    private func drawEdges(
        context: inout GraphicsContext,
        graph: WikiGraphLayoutResult,
        transform: WikiGraphViewportTransform,
        size: CGSize
    ) {
        let positions = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.position) })
        let selected = selectedNoteID

        for edge in graph.edges {
            guard let from = positions[edge.sourceID] else { continue }
            guard let to = positions[edge.targetID] else { continue }

            let start = transform.graphToView(from)
            let end = transform.graphToView(to)
            let isHighlighted = selected != nil
                && (edge.sourceID == selected || edge.targetID == selected)

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            let color: Color = edge.isUnresolved
                ? .orange.opacity(isHighlighted ? 0.75 : 0.45)
                : .secondary.opacity(isHighlighted ? 0.85 : 0.4)
            let width: CGFloat = isHighlighted ? 2 : 1
            context.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    private func drawEdgeArrows(
        context: inout GraphicsContext,
        graph: WikiGraphLayoutResult,
        transform: WikiGraphViewportTransform
    ) {
        let positions = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.position) })
        let radii = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.radius) })

        for edge in graph.edges {
            guard let from = positions[edge.sourceID], let to = positions[edge.targetID] else { continue }
            let start = transform.graphToView(from)
            let end = transform.graphToView(to)
            let targetRadius = (radii[edge.targetID] ?? 12) * transform.scale

            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.01)
            let tip = CGPoint(
                x: end.x - dx / length * (targetRadius + 2),
                y: end.y - dy / length * (targetRadius + 2)
            )
            let angle = atan2(dy, dx)
            let arrowLength: CGFloat = 7
            let wing = CGFloat.pi / 7

            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(
                x: tip.x - arrowLength * cos(angle - wing),
                y: tip.y - arrowLength * sin(angle - wing)
            ))
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(
                x: tip.x - arrowLength * cos(angle + wing),
                y: tip.y - arrowLength * sin(angle + wing)
            ))

            let color: Color = edge.isUnresolved ? .orange.opacity(0.6) : .secondary.opacity(0.55)
            context.stroke(arrow, with: .color(color), lineWidth: 1.25)
        }
    }

    private func reload() {
        do {
            let graph = try store.fetchWikiLinkGraph()
            rawNodes = graph.nodes
            rawEdges = graph.edges
            pinnedPositions = [:]
            recomputeLayout()
            fitGraphToView()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recomputeLayout() {
        let built = WikiGraphLayoutEngine.buildDisplayGraph(nodes: rawNodes, edges: rawEdges)
        let mode: WikiGraphLayoutMode = reduceMotion ? .circular : layoutMode
        layoutResult = WikiGraphLayoutEngine.layout(
            nodes: built.nodes,
            edges: built.edges,
            in: canvasSize,
            mode: mode,
            pinnedPositions: pinnedPositions
        )
    }

    private func fitGraphToView() {
        let graph = displayGraph
        guard !graph.nodes.isEmpty else { return }
        viewportTransform = WikiGraphLayoutEngine.fitTransform(for: graph.nodes, in: canvasSize)
        gestureScale = 1
        gestureTranslation = .zero
    }
}
