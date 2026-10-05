import Foundation

/// A JSON document as byte ranges of its source text, so one value can be
/// added or removed while every other byte of the file stays as it is.
struct JSONSourceNode: Equatable {
    struct Member: Equatable {
        let key: String
        /// From the opening quote of the key.
        let start: Int
        let value: JSONSourceNode
    }

    enum Kind: Equatable {
        case object([Member])
        case array([JSONSourceNode])
        case string(String)
        /// A number, true, false or null.
        case other
    }

    let kind: Kind
    let range: Range<Int>

    var members: [Member]? {
        if case .object(let members) = kind { return members }
        return nil
    }

    var elements: [JSONSourceNode]? {
        if case .array(let elements) = kind { return elements }
        return nil
    }

    var string: String? {
        if case .string(let text) = kind { return text }
        return nil
    }

    func member(_ key: String) -> Member? {
        members?.first { $0.key == key }
    }

    /// The source ranges of the children, each from its first byte (the key
    /// of a member) to the end of its value.
    var childRanges: [Range<Int>] {
        switch kind {
        case .object(let members): return members.map { $0.start..<$0.value.range.upperBound }
        case .array(let elements): return elements.map(\.range)
        case .string, .other: return []
        }
    }
}

struct JSONSourceError: Error, Equatable {
    let offset: Int
}

/// A strict parser: no comments, no trailing commas. A file it refuses is
/// never rewritten.
struct JSONSourceParser {
    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ bytes: [UInt8]) throws -> JSONSourceNode {
        var parser = JSONSourceParser(bytes: bytes)
        // A byte order mark.
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) { parser.index = 3 }
        parser.skipSpace()
        let node = try parser.value(depth: 0)
        parser.skipSpace()
        guard parser.index == bytes.count else { throw JSONSourceError(offset: parser.index) }
        return node
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipSpace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d { index += 1 }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard current == byte else { throw JSONSourceError(offset: index) }
        index += 1
    }

    private mutating func value(depth: Int) throws -> JSONSourceNode {
        guard depth < 256, let byte = current else { throw JSONSourceError(offset: index) }
        let start = index
        switch byte {
        case UInt8(ascii: "{"):
            index += 1
            var members: [JSONSourceNode.Member] = []
            skipSpace()
            if current == UInt8(ascii: "}") {
                index += 1
                return JSONSourceNode(kind: .object([]), range: start..<index)
            }
            while true {
                skipSpace()
                let keyStart = index
                let key = try string()
                skipSpace()
                try expect(UInt8(ascii: ":"))
                skipSpace()
                members.append(JSONSourceNode.Member(key: key, start: keyStart, value: try value(depth: depth + 1)))
                skipSpace()
                if current == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                try expect(UInt8(ascii: "}"))
                return JSONSourceNode(kind: .object(members), range: start..<index)
            }
        case UInt8(ascii: "["):
            index += 1
            var elements: [JSONSourceNode] = []
            skipSpace()
            if current == UInt8(ascii: "]") {
                index += 1
                return JSONSourceNode(kind: .array([]), range: start..<index)
            }
            while true {
                skipSpace()
                elements.append(try value(depth: depth + 1))
                skipSpace()
                if current == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                try expect(UInt8(ascii: "]"))
                return JSONSourceNode(kind: .array(elements), range: start..<index)
            }
        case UInt8(ascii: "\""):
            return JSONSourceNode(kind: .string(try string()), range: start..<index)
        default:
            while let byte = current, !Self.endsLiteral(byte) { index += 1 }
            guard index > start, Self.isLiteral(bytes[start..<index]) else { throw JSONSourceError(offset: start) }
            return JSONSourceNode(kind: .other, range: start..<index)
        }
    }

    private static func endsLiteral(_ byte: UInt8) -> Bool {
        [0x20, 0x09, 0x0a, 0x0d, UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]")].contains(byte)
    }

    /// Foundation decides what a number is.
    private static func isLiteral(_ slice: ArraySlice<UInt8>) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(slice), options: .fragmentsAllowed)) != nil
    }

    /// `index` is on the opening quote and ends after the closing one.
    private mutating func string() throws -> String {
        let start = index
        try expect(UInt8(ascii: "\""))
        while let byte = current {
            if byte == UInt8(ascii: "\\") {
                index += 2
            } else if byte == UInt8(ascii: "\"") {
                index += 1
                guard let text = try? JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed) as? String else {
                    throw JSONSourceError(offset: start)
                }
                return text
            } else {
                index += 1
            }
        }
        throw JSONSourceError(offset: start)
    }
}

/// Changes to the source text of a JSON document. Each one touches only the
/// bytes of the value it adds or removes and the comma next to it.
struct JSONSourceText: Equatable {
    private(set) var bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    func parsed() throws -> JSONSourceNode {
        try JSONSourceParser.parse(bytes)
    }

    var lineEnding: String {
        bytes.contains(0x0d) ? "\r\n" : "\n"
    }

    /// One level of indentation: the indentation of the first indented line.
    var indentUnit: String {
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0a {
                var end = index + 1
                while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
                if end > index + 1, end < bytes.count, bytes[end] != 0x0a, bytes[end] != 0x0d {
                    return String(decoding: bytes[(index + 1)..<end], as: UTF8.self)
                }
                index = end
            } else {
                index += 1
            }
        }
        return "  "
    }

    private func lineStart(of offset: Int) -> Int {
        var start = offset
        while start > 0, bytes[start - 1] != 0x0a { start -= 1 }
        return start
    }

    /// The indentation of the line that holds `offset`.
    func lineIndent(at offset: Int) -> String {
        let start = lineStart(of: offset)
        var end = start
        while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func isFirstOnLine(_ offset: Int) -> Bool {
        bytes[lineStart(of: offset)..<offset].allSatisfy { $0 == 0x20 || $0 == 0x09 }
    }

    /// Adds a child at the end of an object or array. `text` gets the
    /// indentation of the new child's line and gives the child's source: a
    /// value for an array, `"key": value` for an object.
    mutating func append(to container: JSONSourceNode, text: (_ indent: String) -> String) {
        let children = container.childRanges
        if let last = children.last {
            if isFirstOnLine(last.lowerBound) {
                let indent = lineIndent(at: last.lowerBound)
                insert("," + lineEnding + indent + text(indent), at: last.upperBound)
            } else {
                insert(", " + text(lineIndent(at: container.range.lowerBound)), at: last.upperBound)
            }
        } else {
            let closing = lineIndent(at: container.range.lowerBound)
            let indent = closing + indentUnit
            let inner = lineEnding + indent + text(indent) + lineEnding + closing
            bytes.replaceSubrange((container.range.lowerBound + 1)..<(container.range.upperBound - 1), with: Array(inner.utf8))
        }
    }

    /// Removes one child with its comma. Removing what `append` added gives
    /// the bytes from before.
    mutating func removeChild(at index: Int, of container: JSONSourceNode) {
        let children = container.childRanges
        guard children.indices.contains(index) else { return }
        if children.count == 1 {
            bytes.removeSubrange((container.range.lowerBound + 1)..<(container.range.upperBound - 1))
        } else if index > 0 {
            bytes.removeSubrange(children[index - 1].upperBound..<children[index].upperBound)
        } else {
            bytes.removeSubrange(children[0].lowerBound..<children[1].lowerBound)
        }
    }

    private mutating func insert(_ text: String, at offset: Int) {
        bytes.insert(contentsOf: Array(text.utf8), at: offset)
    }

    /// A JSON string literal, with slashes left as they are.
    static func literal(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
