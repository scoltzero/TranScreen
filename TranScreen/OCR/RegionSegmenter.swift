import CoreGraphics
import Foundation

struct TextRegion: Sendable {
    let blocks: [TextBlock]
    let boundingBox: CGRect
    let fontSizeCategory: FontSizeCategory
    let id: UUID

    init(blocks: [TextBlock], fontSizeCategory: FontSizeCategory) {
        self.id = UUID()
        self.blocks = blocks
        self.fontSizeCategory = fontSizeCategory
        self.boundingBox = blocks.reduce(CGRect.null) { $0.union($1.boundingBox) }
    }
}

enum FontSizeCategory: Sendable {
    case title
    case body
    case footnote
}

struct RegionSegmenter {

    /// Segment OCR text blocks into regions by font size and paragraph gaps.
    func segment(blocks: [TextBlock]) -> [TextRegion] {
        guard !blocks.isEmpty else { return [] }

        // 1. Cluster by observation boundingBox height (each observation is a line of text)
        let withAvgHeight: [(TextBlock, CGFloat)] = blocks.map { block in
            (block, block.boundingBox.height)
        }

        let allHeights = withAvgHeight.map(\.1).sorted()
        let clusters = clusterHeights(allHeights)

        // 2. Assign each block to a cluster
        var blocksByCluster: [FontSizeCategory: [TextBlock]] = [
            .title: [], .body: [], .footnote: []
        ]
        for (block, avgH) in withAvgHeight {
            let cat = categoryForHeight(avgH, clusters: clusters)
            blocksByCluster[cat]!.append(block)
        }

        // 3. Within each category, split by paragraph gaps
        var regions: [TextRegion] = []
        let sortedCategories: [FontSizeCategory] = [.title, .body, .footnote]

        for cat in sortedCategories {
            guard let catBlocks = blocksByCluster[cat], !catBlocks.isEmpty else { continue }
            let subRegions = splitByParagraphGaps(catBlocks, category: cat)
            regions.append(contentsOf: subRegions)
        }

        return regions
    }

    // MARK: - Clustering

    private func clusterHeights(_ heights: [CGFloat]) -> [CGFloat] {
        guard heights.count > 1 else { return heights }
        let minH = heights.first!
        let maxH = heights.last!
        let range = maxH - minH

        // If range is small, single cluster
        if range < 0.005 || (minH > 0 && range / minH < 0.5) {
            return [heights.reduce(0, +) / CGFloat(heights.count)]
        }

        // Try 2-way split
        let bestSplit = findBestSplit(heights)
        let left = Array(heights[0..<bestSplit])
        let right = Array(heights[bestSplit...])

        let leftMean = left.reduce(0, +) / CGFloat(left.count)
        let rightMean = right.reduce(0, +) / CGFloat(right.count)

        if rightMean / leftMean > 1.8 {
            // Check for 3-way split in the larger group
            let larger = left.count >= right.count ? left : right
            if larger.count > 2 {
                let subSplit = findBestSplit(larger)
                let subLeft = larger[0..<subSplit]
                let subRight = larger[subSplit...]
                let subLMean = subLeft.reduce(0, +) / CGFloat(subLeft.count)
                let subRMean = subRight.reduce(0, +) / CGFloat(subRight.count)
                if subRMean / subLMean > 1.5 {
                    return [subLeft.first!, subLeft.last!, subRight.last!, right.last!].sorted()
                }
            }
            return [leftMean, rightMean]
        }
        return [heights.reduce(0, +) / CGFloat(heights.count)]
    }

    private func findBestSplit(_ sorted: [CGFloat]) -> Int {
        var bestGap: CGFloat = 0
        var bestIdx = 1
        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            if gap > bestGap {
                bestGap = gap
                bestIdx = i
            }
        }
        return bestIdx
    }

    private func categoryForHeight(_ h: CGFloat, clusters: [CGFloat]) -> FontSizeCategory {
        let sorted = clusters.sorted()
        switch sorted.count {
        case 1: return .body
        case 2:
            let mid = (sorted[0] + sorted[1]) / 2
            return h > mid ? .title : .body
        default:
            let mid1 = (sorted[0] + sorted[1]) / 2
            let mid2 = (sorted[1] + sorted[2]) / 2
            if h > mid2 { return .title }
            if h > mid1 { return .body }
            return .footnote
        }
    }

    // MARK: - Paragraph gap splitting

    private func splitByParagraphGaps(_ blocks: [TextBlock], category: FontSizeCategory) -> [TextRegion] {
        let sorted = blocks.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        guard sorted.count > 1 else {
            return [TextRegion(blocks: sorted, fontSizeCategory: category)]
        }

        // Compute gaps between consecutive lines
        var gaps: [CGFloat] = []
        for i in 1..<sorted.count {
            let prevBottom = sorted[i - 1].boundingBox.origin.y
            let currTop = sorted[i].boundingBox.origin.y + sorted[i].boundingBox.height
            gaps.append(prevBottom - currTop)
        }
        guard !gaps.isEmpty else {
            return [TextRegion(blocks: sorted, fontSizeCategory: category)]
        }

        let sortedGaps = gaps.sorted()
        let medianGap = sortedGaps[sortedGaps.count / 2]
        let splitThreshold = max(medianGap * 2.0, 0.01)

        // Split into groups where gap > threshold
        var groups: [[TextBlock]] = []
        var current: [TextBlock] = [sorted[0]]
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if gaps[i - 1] > splitThreshold || shouldSplitLayout(prev: prev, curr: curr) {
                groups.append(current)
                current = [sorted[i]]
            } else {
                current.append(sorted[i])
            }
        }
        groups.append(current)

        return groups.map { TextRegion(blocks: $0, fontSizeCategory: category) }
    }

    private func shouldSplitLayout(prev: TextBlock, curr: TextBlock) -> Bool {
        let verticalOverlap = min(prev.boundingBox.maxY, curr.boundingBox.maxY)
            - max(prev.boundingBox.minY, curr.boundingBox.minY)
        let minHeight = min(prev.boundingBox.height, curr.boundingBox.height)
        let sameVisualRow = minHeight > 0 && verticalOverlap > minHeight * 0.45

        if sameVisualRow {
            let horizontalGap = max(
                max(prev.boundingBox.minX, curr.boundingBox.minX) - min(prev.boundingBox.maxX, curr.boundingBox.maxX),
                0
            )
            return horizontalGap > minHeight * 2.0
        }

        return !hasHorizontalOverlap(prev.boundingBox, curr.boundingBox)
    }

    private func hasHorizontalOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlapWidth = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        guard overlapWidth > 0 else { return false }
        return overlapWidth > min(a.width, b.width) * 0.2
    }
}
