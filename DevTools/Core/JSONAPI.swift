import Foundation

/// A loosely-typed JSON:API resource. Used for the many App Store Connect resources that are only
/// shown and edited in a few places (analytics, pricing, IAP, Xcode Cloud, webhooks, users, ...).
struct JRes: Identifiable, Hashable {
    let id: String
    let type: String
    let attrs: [String: Any]
    let rels: [String: Any]

    init(_ dict: [String: Any]) {
        id = dict["id"] as? String ?? UUID().uuidString
        type = dict["type"] as? String ?? ""
        attrs = dict["attributes"] as? [String: Any] ?? [:]
        rels = dict["relationships"] as? [String: Any] ?? [:]
    }

    static func == (a: JRes, b: JRes) -> Bool { a.id == b.id && a.type == b.type }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(type) }

    // Attribute helpers
    func s(_ key: String) -> String? {
        if let v = attrs[key] as? String { return v }
        if let n = attrs[key] as? NSNumber { return n.stringValue }
        return nil
    }
    func str(_ key: String, _ fallback: String = "") -> String { s(key) ?? fallback }
    func i(_ key: String) -> Int? {
        if let n = attrs[key] as? NSNumber { return n.intValue }
        if let s = attrs[key] as? String { return Int(s) }
        return nil
    }
    func dbl(_ key: String) -> Double? {
        if let n = attrs[key] as? NSNumber { return n.doubleValue }
        if let s = attrs[key] as? String { return Double(s) }
        return nil
    }
    func b(_ key: String) -> Bool? { (attrs[key] as? NSNumber)?.boolValue }
    func date(_ key: String) -> Date? { ASCDate.parse(s(key)) }
    func obj(_ key: String) -> [String: Any]? { attrs[key] as? [String: Any] }
    func list(_ key: String) -> [Any] { attrs[key] as? [Any] ?? [] }
    func strings(_ key: String) -> [String] { attrs[key] as? [String] ?? [] }

    /// ID of a to-one relationship.
    func rel(_ key: String) -> String? {
        ((rels[key] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String
    }
    /// IDs of a to-many relationship.
    func relIDs(_ key: String) -> [String] {
        (((rels[key] as? [String: Any])?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
    }
}

struct JDoc {
    var data: [JRes] = []
    var included: [JRes] = []
    var total: Int?
    var raw: [String: Any] = [:]

    func inc(_ id: String?, type: String? = nil) -> JRes? {
        guard let id else { return nil }
        return included.first { $0.id == id && (type == nil || $0.type == type) }
    }
}

extension ConnectAPI {
    static func parseDoc(_ data: Data) -> JDoc {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return JDoc() }
        var doc = JDoc(raw: json)
        if let list = json["data"] as? [[String: Any]] { doc.data = list.map(JRes.init) }
        else if let one = json["data"] as? [String: Any] { doc.data = [JRes(one)] }
        doc.included = (json["included"] as? [[String: Any]] ?? []).map(JRes.init)
        doc.total = ((json["meta"] as? [String: Any])?["paging"] as? [String: Any])?["total"] as? Int
        return doc
    }

    /// GET a JSON:API document. With `all: true`, follows `links.next` (bounded by `max`).
    func jget(_ path: String, _ query: [(String, String)] = [], all: Bool = false, max: Int = 600) async throws -> JDoc {
        var next: URL? = url(path, query)
        var seen = Set<String>()
        var out = JDoc()
        var first = true
        while let u = next, !seen.contains(u.absoluteString) {
            seen.insert(u.absoluteString)
            let (data, _) = try await send("GET", u)
            let page = Self.parseDoc(data)
            if first { out.raw = page.raw; out.total = page.total; first = false }
            out.data += page.data
            out.included += page.included
            guard all, out.data.count < max,
                  let links = page.raw["links"] as? [String: Any], let n = links["next"] as? String else { break }
            next = URL(string: n)
        }
        return out
    }

    /// POST/PATCH/DELETE with a JSON body; returns the parsed response (empty for 204).
    @discardableResult
    func jsend(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> JDoc {
        let data = try await write(method, path, body)
        return data.isEmpty ? JDoc() : Self.parseDoc(data)
    }

    /// Creates a resource of `type` with attributes and to-one relationships ([key: (type, id)]).
    @discardableResult
    func jcreate(_ path: String, type: String, attributes: [String: Any] = [:], relationships: [String: (String, String)] = [:]) async throws -> JRes? {
        var data: [String: Any] = ["type": type]
        if !attributes.isEmpty { data["attributes"] = attributes }
        if !relationships.isEmpty {
            var rels: [String: Any] = [:]
            for (k, v) in relationships { rels[k] = ["data": ["type": v.0, "id": v.1]] }
            data["relationships"] = rels
        }
        return try await jsend("POST", path, ["data": data]).data.first
    }

    func jpatch(_ path: String, type: String, id: String, attributes: [String: Any]) async throws {
        try await jsend("PATCH", path, ["data": ["type": type, "id": id, "attributes": attributes]])
    }

    func jdelete(_ path: String) async throws {
        try await jsend("DELETE", path)
    }

    /// Raw GET without the JSON:API envelope (e.g. crash logs, CSV code lists).
    func raw(_ path: String, _ query: [(String, String)] = [], accept: String = "application/json") async throws -> Data {
        try await send("GET", url(path, query), accept: accept).0
    }
}

/// Pretty labels for Apple's UPPER_SNAKE enum values.
enum Pretty {
    static func label(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let words = raw.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
