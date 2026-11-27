import SwiftUI
import UIKit

struct DiffLine: Identifiable {
    var kind: Int
    var text: String
    var id: String { "\(kind)-\(text.hashValue)-\(UUID().uuidString.hashValue)" }
}

private let maxDiffLines = 400

func computeEditDiff(_ oldText: String, _ newText: String) -> [DiffLine] {
    let a = oldText.isEmpty ? [] : oldText.components(separatedBy: "\n")
    let b = newText.isEmpty ? [] : newText.components(separatedBy: "\n")
    var out: [DiffLine] = []
    if a.count > 300 || b.count > 300 {
        for l in a { out.append(DiffLine(kind: 2, text: l)) }
        for l in b { out.append(DiffLine(kind: 1, text: l)) }
        return out
    }
    let n = a.count
    let m = b.count
    var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    if n > 0 && m > 0 {
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
    }
    var i = 0
    var j = 0
    while i < n && j < m {
        if a[i] == b[j] {
            out.append(DiffLine(kind: 0, text: a[i]))
            i += 1
            j += 1
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            out.append(DiffLine(kind: 2, text: a[i]))
            i += 1
        } else {
            out.append(DiffLine(kind: 1, text: b[j]))
            j += 1
        }
    }
    while i < n {
        out.append(DiffLine(kind: 2, text: a[i]))
        i += 1
    }
    while j < m {
        out.append(DiffLine(kind: 1, text: b[j]))
        j += 1
    }
    return out
}

func parsePatchDiff(_ patch: String) -> [DiffLine] {
    var out: [DiffLine] = []
    for l in patch.components(separatedBy: "\n") {
        let text = l.isEmpty ? " " : l
        var kind = 0
        if l.hasPrefix("@@") {
            kind = 3
        } else if l.hasPrefix("+") && !l.hasPrefix("+++") {
            kind = 1
        } else if l.hasPrefix("-") && !l.hasPrefix("---") {
            kind = 2
        }
        out.append(DiffLine(kind: kind, text: text))
    }
    return out
}

private func diffToText(_ lines: [DiffLine]) -> String {
    lines.map { l -> String in
        switch l.kind {
        case 1: return "+" + l.text
        case 2: return "-" + l.text
        case 3: return l.text
        default: return " " + l.text
        }
    }
    .joined(separator: "\n")
}

struct DiffView: View {
    let filePath: String
    let diffOld: String
    let diffNew: String
    let diffPatch: String

    @State private var copied = false

    private var lines: [DiffLine] {
        if !diffPatch.isEmpty {
            return parsePatchDiff(diffPatch)
        }
        return computeEditDiff(diffOld, diffNew)
    }

    private var displayLines: [DiffLine] {
        let all = lines
        return all.count <= maxDiffLines ? all : Array(all[..<maxDiffLines])
    }

    private func countKind(_ kind: Int) -> Int {
        lines.filter { $0.kind == kind }.count
    }

    private func lineLabel(_ l: DiffLine) -> String {
        let text = l.text.isEmpty ? " " : l.text
        if !diffPatch.isEmpty {
            return text
        }
        if l.kind == 1 { return "+" + text }
        if l.kind == 2 { return "-" + text }
        return " " + text
    }

    private func lineColor(_ l: DiffLine) -> Color {
        if l.kind == 1 { return Color(hex: "#86EFAC") }
        if l.kind == 2 { return Color(hex: "#FCA5A5") }
        if l.kind == 3 { return Theme.accent }
        return Theme.secondaryText
    }

    private func lineBg(_ l: DiffLine) -> Color {
        if l.kind == 1 { return Color(hex: "#163024") }
        if l.kind == 2 { return Color(hex: "#321F26") }
        if l.kind == 3 { return Color(hex: "#0F2A3A") }
        return .clear
    }

    var body: some View {
        let all = lines
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(filePath.isEmpty ? "差异" : shortNameOf(filePath))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(countKind(1))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#86EFAC"))
                Text("-\(countKind(2))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#FCA5A5"))
                Button {
                    UIPasteboard.general.string = diffPatch.isEmpty ? diffToText(all) : diffPatch
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Text(copied ? "已复制" : "复制")
                        .font(.system(size: 11))
                        .foregroundColor(copied ? Theme.success : Theme.accent)
                }
            }
            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, l in
                Text(lineLabel(l))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(lineColor(l))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(lineBg(l))
                    .cornerRadius(4)
            }
            if all.count > maxDiffLines {
                Text("仅显示前 \(maxDiffLines) 行（共 \(all.count) 行），点击「复制」可获取完整差异")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }
}
