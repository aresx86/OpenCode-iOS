import SwiftUI
import UIKit

enum MdBlockType: Int {
    case paragraph = 0
    case heading = 1
    case code = 2
    case listItem = 3
    case quote = 4
    case rule = 5
}

struct MdBlock: Identifiable {
    var type: MdBlockType = .paragraph
    var text = ""
    var level = 0
    var ordered = false
    var index = 0
    var lang = ""
    var id: String { "\(index)-\(type.rawValue)-\(text.hashValue)" }
}

struct MdSpan {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link = false
}

func parseInline(_ src: String) -> [MdSpan] {
    var out: [MdSpan] = []
    var buf = ""
    let chars = Array(src)
    var i = 0
    func pushPlain() {
        if !buf.isEmpty {
            out.append(MdSpan(text: buf))
            buf = ""
        }
    }
    while i < chars.count {
        let c = chars[i]
        if c == "`" {
            var j = i + 1
            while j < chars.count && chars[j] != "`" { j += 1 }
            if j > i && j < chars.count {
                pushPlain()
                out.append(MdSpan(text: String(chars[(i + 1)..<j]), code: true))
                i = j + 1
                continue
            }
        }
        if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
            var j = i + 2
            var found = false
            while j + 1 < chars.count {
                if chars[j] == "*", chars[j + 1] == "*" {
                    found = true
                    break
                }
                j += 1
            }
            if found {
                pushPlain()
                out.append(MdSpan(text: String(chars[(i + 2)..<j]), bold: true))
                i = j + 2
                continue
            }
        }
        if c == "*" {
            var j = i + 1
            while j < chars.count && chars[j] != "*" { j += 1 }
            if j > i + 1 && j < chars.count {
                pushPlain()
                out.append(MdSpan(text: String(chars[(i + 1)..<j]), italic: true))
                i = j + 1
                continue
            }
        }
        if c == "[" {
            var close = i + 1
            while close < chars.count && chars[close] != "]" { close += 1 }
            if close > i + 1 && close + 2 < chars.count && chars[close + 1] == "(" {
                var end = close + 2
                while end < chars.count && chars[end] != ")" { end += 1 }
                if end < chars.count {
                    pushPlain()
                    out.append(MdSpan(text: String(chars[(i + 1)..<close]), link: true))
                    i = end + 1
                    continue
                }
            }
        }
        buf.append(c)
        i += 1
    }
    pushPlain()
    return out
}

private func orderedPrefixLen(_ t: String) -> Int {
    let chars = Array(t)
    var i = 0
    while i < chars.count && chars[i].isNumber {
        i += 1
    }
    if i > 0 && i + 1 < chars.count && (chars[i] == "." || chars[i] == ")") && chars[i + 1] == " " {
        return i + 2
    }
    return 0
}

private func isListLine(_ t: String) -> Bool {
    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
        return true
    }
    return orderedPrefixLen(t) > 0
}

private func isMdSpecial(_ t: String) -> Bool {
    if t.isEmpty || t.hasPrefix("```") || t.hasPrefix("#") || t.hasPrefix("> ") || t == "---" || t == "***" {
        return true
    }
    return isListLine(t)
}

func parseMarkdown(_ src: String) -> [MdBlock] {
    var blocks: [MdBlock] = []
    let lines = src.components(separatedBy: "\n")
    var i = 0
    var ordIdx = 1
    while i < lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            i += 1
            continue
        }
        if trimmed.hasPrefix("```") {
            let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            i += 1
            var codeLines: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeLines.append(lines[i])
                i += 1
            }
            if i < lines.count {
                i += 1
            }
            var b = MdBlock()
            b.type = .code
            b.lang = lang
            b.text = codeLines.joined(separator: "\n")
            blocks.append(b)
            continue
        }
        if trimmed.hasPrefix("#") {
            var level = 0
            let chars = Array(trimmed)
            while level < chars.count && chars[level] == "#" {
                level += 1
            }
            if level <= 4 && level < chars.count && chars[level] == " " {
                var b = MdBlock()
                b.type = .heading
                b.level = level
                b.text = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
                blocks.append(b)
                i += 1
                continue
            }
        }
        if trimmed == "---" || trimmed == "***" {
            var b = MdBlock()
            b.type = .rule
            blocks.append(b)
            i += 1
            continue
        }
        if trimmed.hasPrefix("> ") {
            var quoteLines: [String] = []
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("> ") {
                    quoteLines.append(String(t.dropFirst(2)))
                } else {
                    quoteLines.append(String(t.dropFirst(1)))
                }
                i += 1
            }
            var b = MdBlock()
            b.type = .quote
            b.text = quoteLines.joined(separator: "\n")
            blocks.append(b)
            continue
        }
        if isListLine(trimmed) {
            ordIdx = 1
            while i < lines.count && isListLine(lines[i].trimmingCharacters(in: .whitespaces)) {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                var b = MdBlock()
                b.type = .listItem
                if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                    b.ordered = false
                    b.text = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else {
                    b.ordered = true
                    b.index = ordIdx
                    ordIdx += 1
                    b.text = String(t.dropFirst(orderedPrefixLen(t))).trimmingCharacters(in: .whitespaces)
                }
                blocks.append(b)
                i += 1
            }
            continue
        }
        var paraLines: [String] = []
        while i < lines.count && !isMdSpecial(lines[i].trimmingCharacters(in: .whitespaces)) {
            paraLines.append(lines[i].trimmingCharacters(in: .whitespaces))
            i += 1
        }
        if !paraLines.isEmpty {
            var b = MdBlock()
            b.type = .paragraph
            b.text = paraLines.joined(separator: "\n")
            blocks.append(b)
        }
    }
    return blocks
}

private func spansText(_ spans: [MdSpan], baseColor: Color, size: CGFloat, baseWeight: Font.Weight = .regular) -> Text {
    var result = Text("")
    for s in spans {
        var t = Text(s.text)
        if s.code {
            t = t.font(.system(size: size - 2, weight: baseWeight == .bold ? .semibold : .regular, design: .monospaced))
                .foregroundColor(Theme.accent)
        } else if s.link {
            t = t.font(.system(size: size)).foregroundColor(Theme.accent).underline()
        } else {
            t = t.font(.system(size: size)).foregroundColor(baseColor)
        }
        if s.bold || baseWeight == .bold {
            t = t.bold()
        }
        if s.italic {
            t = t.italic()
        }
        result = result + t
    }
    return result
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = parseMarkdown(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                blockView(b)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ b: MdBlock) -> some View {
        switch b.type {
        case .code:
            CodeBlockView(lang: b.lang, code: b.text)
        case .heading:
            spansText(parseInline(b.text), baseColor: Theme.primaryText, size: headingSize(b.level), baseWeight: .bold)
        case .listItem:
            HStack(alignment: .top, spacing: 6) {
                Text(b.ordered ? "\(b.index)." : "•")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                spansText(parseInline(b.text), baseColor: Theme.primaryText, size: 14)
            }
        case .quote:
            spansText(parseInline(b.text), baseColor: Theme.secondaryText, size: 13)
                .padding(.leading, 10)
                .padding(.vertical, 2)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(hex: "#3B4F6E"))
                        .frame(width: 3)
                }
        case .rule:
            Divider().overlay(Theme.cardBorder)
        case .paragraph:
            spansText(parseInline(b.text), baseColor: Theme.primaryText, size: 14)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        if level <= 1 { return 19 }
        if level == 2 { return 17 }
        if level == 3 { return 15 }
        return 14
    }
}

struct CodeBlockView: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lang.isEmpty ? "代码" : lang)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
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
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(hex: "#0D1626"))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
    }
}
