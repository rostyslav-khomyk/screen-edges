import Darwin
import Foundation
import Network

private let hyperionST = "urn:hyperion-project.org:device:basic:1"
private let descriptionPort: UInt16 = 8092

func startHyperionDiscovery(websocketPort: UInt16) {
    let name = Host.current().localizedName ?? "Screen Edges"
    let address = lanIPv4()
    DispatchQueue.global(qos: .utility).async {
        serveDescription(name: name, address: address, websocketPort: websocketPort)
        listenForSearch(name: name, address: address, websocketPort: websocketPort)
    }
}

private func serveDescription(name: String, address: String, websocketPort: UInt16) {
    guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: descriptionPort)!) else {
        fputs("Hyperion description port \(descriptionPort) is unavailable\n", stderr)
        return
    }
    let xml = descriptionXML(name: name, websocketPort: websocketPort)
    listener.newConnectionHandler = { connection in
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
            let body = Data(xml.utf8)
            let header = """
            HTTP/1.1 200 OK\r
            Content-Type: text/xml\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """
            var response = Data(header.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    listener.start(queue: .global(qos: .utility))
    fputs("Hyperion description http://\(address):\(descriptionPort)/description.xml\n", stderr)
}

private func listenForSearch(name: String, address: String, websocketPort: UInt16) {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return }
    var reuse: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var local = sockaddr_in()
    local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    local.sin_family = sa_family_t(AF_INET)
    local.sin_port = UInt16(1900).bigEndian
    local.sin_addr.s_addr = inet_addr("0.0.0.0")
    let bound = withUnsafePointer(to: &local) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0 else {
        fputs("Hyperion discovery could not listen on UDP 1900\n", stderr)
        close(fd)
        return
    }
    var loop: Int32 = 1
    setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<Int32>.size))
    var group = ip_mreq()
    group.imr_multiaddr.s_addr = inet_addr("239.255.255.250")
    group.imr_interface.s_addr = INADDR_ANY
    let joined = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &group, socklen_t(MemoryLayout<ip_mreq>.size))
    if joined != 0 {
        group.imr_interface.s_addr = inet_addr(address)
        let again = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &group, socklen_t(MemoryLayout<ip_mreq>.size))
        if again != 0 {
            fputs("Hyperion discovery is listening, but not on the multicast group\n", stderr)
        }
    }
    fputs("Hyperion discovery on \(address)\n", stderr)
    let reply = searchReply(name: name, address: address, websocketPort: websocketPort)
    var buffer = [UInt8](repeating: 0, count: 2048)
    while true {
        var sender = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
            }
        }
        guard count > 0 else { continue }
        let text = String(bytes: buffer.prefix(count), encoding: .utf8) ?? ""
        let upper = text.uppercased()
        guard upper.contains("M-SEARCH"),
              upper.contains(hyperionST.uppercased()) || upper.contains("SSDP:ALL")
        else { continue }
        _ = reply.withCString { bytes in
            withUnsafePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, strlen(bytes), 0, $0, length)
                }
            }
        }
    }
}

private func searchReply(name: String, address: String, websocketPort: UInt16) -> String {
    """
    HTTP/1.1 200 OK\r
    CACHE-CONTROL: max-age=1800\r
    LOCATION: http://\(address):\(descriptionPort)/description.xml\r
    SERVER: Screen Edges UPnP/1.0\r
    ST: \(hyperionST)\r
    USN: uuid:screen-edges-\(name.filter { $0.isLetter || $0.isNumber })::\(hyperionST)\r
    \r

    """
}

private func descriptionXML(name: String, websocketPort: UInt16) -> String {
    let safe = name
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
    return """
    <?xml version="1.0"?>
    <root>
      <device>
        <friendlyName>\(safe)</friendlyName>
        <manufacturer>Hyperion Open Source Ambient Lighting</manufacturer>
        <modelName>Screen Edges</modelName>
        <serialNumber>screen-edges</serialNumber>
        <websocket>\(websocketPort)</websocket>
      </device>
    </root>
    """
}

private func lanIPv4() -> String {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else { return "0.0.0.0" }
    defer { freeifaddrs(interfaces) }
    var fallback = "0.0.0.0"
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let iface = cursor {
        cursor = iface.pointee.ifa_next
        let flags = Int32(iface.pointee.ifa_flags)
        if flags & IFF_UP == 0 || flags & IFF_LOOPBACK != 0 { continue }
        guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            continue
        }
        let ip = String(cString: host)
        if String(cString: iface.pointee.ifa_name) == "en0" { return ip }
        if fallback == "0.0.0.0" { fallback = ip }
    }
    return fallback
}
