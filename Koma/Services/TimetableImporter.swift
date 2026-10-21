import CoreGraphics
import Foundation
import UIKit
import Vision

/// 画像から読み取った1授業ぶん。名前は推測なので、取り込む前に直せる前提。
struct DetectedCourse: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var slots: [TimetableSlot]

    var slotSummary: String {
        slots
            .sorted { $0.weekday == $1.weekday ? $0.period < $1.period : sortKey($0.weekday) < sortKey($1.weekday) }
            .map { "\(WeekdayText.short($0.weekday)) P\($0.period)" }
            .joined(separator: " · ")
    }

    private func sortKey(_ weekday: Int) -> Int { weekday == 1 ? 8 : weekday }
}

/// ポータルの時間割のスクリーンショットから、コマを読み取る。
/// 端末内の Vision だけを使うので、画像が外に出ることはない。
enum TimetableImporter {
    enum ImportError: LocalizedError {
        case unreadableImage
        case noGridFound

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "That image could not be read."
            case .noGridFound: return "No timetable grid was found. A screenshot of the timetable table works best."
            }
        }
    }

    /// 読み取った文字と、画像の中での位置。
    private struct Block {
        var text: String
        /// 画像の左上を原点にした枠（0...1）。
        var box: CGRect

        var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
    }

    /// OCR にかける前の最低限の横幅。ポータルのスクショは細かく、そのままだと読み違えが増える。
    private static let minimumWidth = 2000

    static func detect(in image: UIImage) async throws -> [DetectedCourse] {
        guard let original = image.cgImage else { throw ImportError.unreadableImage }
        let cgImage = upscaled(original)

        // 1回目は全体を読んで、曜日の並びと各限の位置だけを取る。
        let blocks = try await recognize(cgImage, in: nil)
        guard !blocks.isEmpty else { throw ImportError.noGridFound }

        let aspect = CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let columns = try weekdayColumns(from: blocks, aspect: aspect)
        let gutterX = columns.centers[0].x - columns.width / 2
        let rows = try periodRows(from: blocks, below: columns.headerY, gutterX: gutterX)

        // 2回目は曜日ごとに縦に切って読む。
        // 切らずに読むと「火水」「4写真演...Webプ...」のように行がつながってしまうため。
        var cells: [String: String] = [:]
        let rowGap = medianGap(rows.map(\.y))
        let top = max(0, rows.first!.y - rowGap)
        let bottom = min(1, rows.last!.y + rowGap)

        for column in columns.centers {
            let strip = CGRect(
                x: max(0, column.x - columns.width * 0.49),
                y: top,
                width: min(1, columns.width * 0.98),
                height: bottom - top
            )
            let stripBlocks = try await recognize(cgImage, in: strip)
            for block in stripBlocks {
                guard !isNoise(block.text) else { continue }
                guard let index = nearest(rows.map(\.y), to: block.center.y, limit: rowGap * 0.6) else { continue }
                let key = "\(column.weekday)-\(rows[index].period)"
                cells[key] = [cells[key], block.text].compactMap { $0 }.joined()
            }
        }

        return courses(from: cells)
    }

    /// 小さい画像は引き伸ばしてから読む。文字が小さいままだと精度が落ちるため。
    private static func upscaled(_ image: CGImage) -> CGImage {
        guard image.width < minimumWidth else { return image }
        let scale = min(4, CGFloat(minimumWidth) / CGFloat(image.width))
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// `region` を渡すと、画像のその範囲だけを読む（左上原点の 0...1）。
    private static func recognize(_ cgImage: CGImage, in region: CGRect?) async throws -> [Block] {
        var target = cgImage
        var offset = CGPoint.zero
        var scale = CGSize(width: 1, height: 1)

        if let region {
            let pixels = CGRect(
                x: region.minX * CGFloat(cgImage.width),
                y: region.minY * CGFloat(cgImage.height),
                width: region.width * CGFloat(cgImage.width),
                height: region.height * CGFloat(cgImage.height)
            ).integral
            guard pixels.width > 1, pixels.height > 1, let cropped = cgImage.cropping(to: pixels) else {
                return []
            }
            target = cropped
            offset = region.origin
            scale = CGSize(width: region.width, height: region.height)
        }

        let blocks: [Block] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let blocks: [Block] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string
                        .replacingOccurrences(of: " ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    let box = observation.boundingBox
                    // Vision は左下原点。扱いやすいよう左上原点に直す。
                    // Vision は左下原点。扱いやすいよう左上原点に直す。
                    return Block(
                        text: text,
                        box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                    )
                }
                continuation.resume(returning: blocks)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: target, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // 切り出した座標を元の画像の座標に戻す。
        return blocks.map {
            Block(
                text: $0.text,
                box: CGRect(
                    x: offset.x + $0.box.minX * scale.width,
                    y: offset.y + $0.box.minY * scale.height,
                    width: $0.box.width * scale.width,
                    height: $0.box.height * scale.height
                )
            )
        }
    }

    // MARK: - 表の組み立て

    private static let weekdaySymbols: [String: Int] = [
        "日": 1, "月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7,
        "Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7,
    ]

    /// 曜日の見出しから列を割り出す。
    /// 見出しは「火水」のようにつながって読まれることがあるので、
    /// 中心ではなく**見出し全体の左端から右端まで**を使って等間隔に割る。
    private static func weekdayColumns(
        from blocks: [Block],
        aspect: CGFloat
    ) throws -> (centers: [(weekday: Int, x: CGFloat)], width: CGFloat, headerY: CGFloat) {
        var headers: [(weekdays: [Int], box: CGRect)] = []
        for block in blocks {
            let weekdays = block.text.compactMap { weekdaySymbols[String($0)] }
            guard weekdays.count == block.text.count, !weekdays.isEmpty else { continue }
            headers.append((weekdays, block.box))
        }
        headers.sort { $0.box.minX < $1.box.minX }
        guard !headers.isEmpty else { throw ImportError.noGridFound }

        var order: [Int] = []
        var union = headers[0].box
        var headerY: CGFloat = 0
        for header in headers {
            order.append(contentsOf: header.weekdays)
            union = union.union(header.box)
            headerY = max(headerY, header.box.maxY)
        }
        guard order.count >= 3 else { throw ImportError.noGridFound }

        // 見出しの文字幅ぶんだけ内側に寄っているので、その半分ずつを足し戻す。
        let characterWidth = min(union.width / CGFloat(order.count), union.height * aspect)
        let first = union.minX + characterWidth / 2
        let last = union.maxX - characterWidth / 2
        let step = (last - first) / CGFloat(order.count - 1)
        guard step > 0.02 else { throw ImportError.noGridFound }

        let centers = order.enumerated().map { (weekday: $1, x: first + step * CGFloat($0)) }
        return (centers, step, headerY)
    }

    /// 行は、見出しより下の文字を縦方向にまとめて作る。
    /// 表の外（左端）にある数字がその行の限。数字が読めない行は表の一部ではないとみなす。
    private static func periodRows(
        from blocks: [Block],
        below headerY: CGFloat,
        gutterX: CGFloat
    ) throws -> [(period: Int, y: CGFloat)] {
        let candidates = blocks
            .filter { $0.center.y > headerY }
            .sorted { $0.center.y < $1.center.y }

        var clusters: [[Block]] = []
        for block in candidates {
            if var last = clusters.last, let reference = last.first,
               abs(block.center.y - reference.center.y) < 0.012 {
                last.append(block)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([block])
            }
        }

        var rows: [(period: Int, y: CGFloat)] = []
        for cluster in clusters {
            guard let leftmost = cluster.min(by: { $0.box.minX < $1.box.minX }) else { continue }
            guard leftmost.box.minX < gutterX else { continue }
            guard let first = leftmost.text.first, let period = first.wholeNumberValue,
                  (1...9).contains(period) else { continue }
            guard !rows.contains(where: { $0.period == period }) else { continue }
            let y = cluster.map(\.center.y).reduce(0, +) / CGFloat(cluster.count)
            rows.append((period, y))
        }
        rows.sort { $0.y < $1.y }
        guard rows.count >= 2 else { throw ImportError.noGridFound }
        return rows
    }

    /// 同じ名前のマスをひとつの授業にまとめる。
    /// 濁点・半濁点は読み違えやすい（プとフ、ポとボ）ので、そこを無視して突き合わせる。
    private static func courses(from cells: [String: String]) -> [DetectedCourse] {
        var groups: [String: (names: [String: Int], slots: [TimetableSlot])] = [:]
        for (key, rawName) in cells {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let name = cleaned(rawName)
            guard !name.isEmpty else { continue }

            let folded = matchKey(for: name)
            var group = groups[folded] ?? (names: [:], slots: [])
            group.names[name, default: 0] += 1
            group.slots.append(TimetableSlot(weekday: parts[0], period: parts[1]))
            groups[folded] = group
        }

        return groups
            .compactMap { _, group -> DetectedCourse? in
                // いちばん多く読めた綴りを採る。同数なら、濁点が付いているほうを残す
                // （OCR は濁点を落とすことのほうが多いため）。
                guard let name = group.names
                    .sorted(by: { lhs, rhs in
                        if lhs.value != rhs.value { return lhs.value > rhs.value }
                        let lhsMarks = diacriticCount(lhs.key), rhsMarks = diacriticCount(rhs.key)
                        if lhsMarks != rhsMarks { return lhsMarks > rhsMarks }
                        return lhs.key.count > rhs.key.count
                    })
                    .first?.key
                else { return nil }
                return DetectedCourse(name: name, slots: group.slots.sorted { $0.period < $1.period })
            }
            .sorted { lhs, rhs in
                let l = lhs.slots.first, r = rhs.slots.first
                if l?.period != r?.period { return (l?.period ?? 0) < (r?.period ?? 0) }
                return (l?.weekday ?? 0) < (r?.weekday ?? 0)
            }
    }

    /// 突き合わせ用の鍵。濁点・半濁点と大文字小文字の違いを無視する。
    /// `diacriticInsensitive` は日本語の濁点を落とさないので、Unicode 分解して自分で外す。
    private static func matchKey(for name: String) -> String {
        let stripped = name
            .folding(options: [.widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .decomposedStringWithCanonicalMapping
            .unicodeScalars
            .filter { $0.value != 0x3099 && $0.value != 0x309A }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }

    private static func diacriticCount(_ text: String) -> Int {
        text.decomposedStringWithCanonicalMapping
            .unicodeScalars
            .filter { $0.value == 0x3099 || $0.value == 0x309A }
            .count
    }

    /// ポータルが名前を切り詰めたときの省略記号や、拾ってしまった括弧を落とす。
    private static func cleaned(_ text: String) -> String {
        let value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[.．。・…（）\(\)「」【】]+$"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func medianGap(_ values: [CGFloat]) -> CGFloat {
        guard values.count >= 2 else { return 0.08 }
        let gaps = zip(values, values.dropFirst()).map { $1 - $0 }.sorted()
        return gaps[gaps.count / 2]
    }

    /// 時間や昼休みなど、授業名ではない文字を落とす。
    private static func isNoise(_ text: String) -> Bool {
        if text.contains("昼") || text.contains("休み") { return true }
        if text.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil { return true }
        if text.filter(\.isNumber).count == text.count { return true }
        if text.count > 24 { return true }
        return false
    }

    private static func nearest(_ values: [CGFloat], to value: CGFloat, limit: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, candidate) in values.enumerated() {
            let distance = abs(candidate - value)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        guard let best, best.distance <= limit else { return nil }
        return best.index
    }
}
