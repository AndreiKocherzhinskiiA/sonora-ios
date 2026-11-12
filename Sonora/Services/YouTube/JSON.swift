import Foundation

/// A forgiving view over decoded JSON, so a response can be walked with optional chaining the way
/// the desktop `Nav` trait walks `serde_json::Value`. Anything missing is an empty node.
struct JSON {
    let raw: Any?

    init(_ raw: Any?) {
        self.raw = raw
    }

    init(data: Data) throws {
        self.raw = try JSONSerialization.jsonObject(with: data)
    }

    subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSON {
        guard let list = raw as? [Any], list.indices.contains(index) else { return JSON(nil) }
        return JSON(list[index])
    }

    /// Follows a path of keys, where a key that is all digits indexes an array.
    func at(_ path: String...) -> JSON {
        path.reduce(self) { node, key in
            if let index = Int(key) { node[index] } else { node[key] }
        }
    }

    var string: String? { raw as? String }
    var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    var exists: Bool { raw != nil && !(raw is NSNull) }

    var int: Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let text = raw as? String { return Int(text) }
        return nil
    }

    var double: Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let text = raw as? String { return Double(text) }
        return nil
    }

    /// The text of a node that is a string, a `simpleText`, or a list of `runs`.
    var runText: String? {
        if let text = string { return text }
        if let text = self["simpleText"].string { return text }
        let joined = self["runs"].array.compactMap { $0["text"].string }.joined()
        return joined.isEmpty ? nil : joined
    }

    /// Every value stored under `key` anywhere below this node, without descending into a match.
    func find(_ key: String) -> [JSON] {
        var found: [JSON] = []
        func walk(_ node: Any?) {
            if let map = node as? [String: Any] {
                for (name, value) in map {
                    if name == key { found.append(JSON(value)) } else { walk(value) }
                }
            } else if let list = node as? [Any] {
                list.forEach(walk)
            }
        }
        walk(raw)
        return found
    }
}
