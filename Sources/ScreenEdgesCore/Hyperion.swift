import Foundation

public struct HyperionReply: Equatable, Sendable {
    public var json: String
    public var streaming: Bool
}

/// Speaks the Hyperion NG JSON API used by screen-grabber clients.
/// Four LEDs, in order: left, top, right, bottom.
public final class HyperionSession: @unchecked Sendable {
    public let token: String
    public private(set) var authorized = false
    public private(set) var streaming = false

    public init(token: String) {
        self.token = token
    }

    public func handle(_ text: String) -> HyperionReply? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HyperionReply(json: errorJSON(command: "unknown", tan: nil, message: "Invalid JSON"), streaming: streaming)
        }
        let command = object["command"] as? String ?? ""
        let sub = object["subcommand"] as? String
        let tan = object["tan"] as? Int

        if command == "authorize" && sub == "login" {
            let given = (object["token"] as? String) ?? (object["password"] as? String) ?? ""
            authorized = given == token && !token.isEmpty
            streaming = authorized ? streaming : false
            if authorized {
                return HyperionReply(
                    json: okJSON(command: "authorize-login", tan: tan, info: ["token": token]),
                    streaming: streaming
                )
            }
            return HyperionReply(
                json: errorJSON(command: "authorize-login", tan: tan, message: "Invalid token"),
                streaming: false
            )
        }

        guard authorized else {
            return HyperionReply(
                json: errorJSON(command: command.isEmpty ? "unknown" : command, tan: tan, message: "No authorization"),
                streaming: streaming
            )
        }

        switch (command, sub) {
        case ("serverinfo", _), ("serverinfo", nil):
            return HyperionReply(json: serverInfoJSON(tan: tan), streaming: streaming)
        case ("ledcolors", "ledstream-start"):
            streaming = true
            return HyperionReply(
                json: okJSON(command: "ledcolors-ledstream-start", tan: tan, info: [:]),
                streaming: true
            )
        case ("ledcolors", "ledstream-stop"):
            streaming = false
            return HyperionReply(
                json: okJSON(command: "ledcolors-ledstream-stop", tan: tan, info: [:]),
                streaming: false
            )
        default:
            return HyperionReply(
                json: errorJSON(command: command, tan: tan, message: "Unsupported command"),
                streaming: streaming
            )
        }
    }

    public func streamUpdate(_ colors: EdgeColors) -> String? {
        guard authorized && streaming else { return nil }
        let leds = colors.leds.map { ["RGB Value": [$0.r, $0.g, $0.b]] }
        let body: [String: Any] = [
            "command": "ledcolors-ledstream-update",
            "data": ["leds": leds],
            "result": ["leds": leds],
        ]
        return stringify(body)
    }

    private func serverInfoJSON(tan: Int?) -> String {
        let leds: [[String: Any]] = [
            ["name": "left", "hmin": 0.0, "hmax": 0.08, "vmin": 0.0, "vmax": 1.0],
            ["name": "top", "hmin": 0.0, "hmax": 1.0, "vmin": 0.0, "vmax": 0.12],
            ["name": "right", "hmin": 0.92, "hmax": 1.0, "vmin": 0.0, "vmax": 1.0],
            ["name": "bottom", "hmin": 0.0, "hmax": 1.0, "vmin": 0.88, "vmax": 1.0],
        ]
        let info: [String: Any] = [
            "hostname": Host.current().localizedName ?? "screen-edges",
            "leds": leds,
            "components": [["name": "VIDEOGRABBER", "enabled": true]],
            "priorities": [],
        ]
        return okJSON(command: "serverinfo", tan: tan, info: info)
    }
}

private func okJSON(command: String, tan: Int?, info: [String: Any]) -> String {
    var body: [String: Any] = ["command": command, "success": true, "info": info]
    if let tan { body["tan"] = tan }
    return stringify(body)
}

private func errorJSON(command: String, tan: Int?, message: String) -> String {
    var body: [String: Any] = ["command": command, "success": false, "error": message]
    if let tan { body["tan"] = tan }
    return stringify(body)
}

private func stringify(_ body: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: body, options: [])
    return String(data: data, encoding: .utf8)!
}
