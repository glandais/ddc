// ddc — minimal DDC/CI over IOAVService (Apple Silicon)
// usage: ddc get <vcp>   |   ddc set <vcp> <value>     (vcp/value in decimal or 0x..)
import Foundation
import IOKit

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ s: CFTypeRef, _ chip: UInt32, _ offset: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ s: CFTypeRef, _ chip: UInt32, _ offset: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func externalServices() -> [CFTypeRef] {
    var result: [CFTypeRef] = []
    var iter = io_iterator_t()
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iter) }
    while case let entry = IOIteratorNext(iter), entry != 0 {
        defer { IOObjectRelease(entry) }
        let loc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        guard loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
        result.append(av)
    }
    return result
}

func packet(_ payload: [UInt8]) -> [UInt8] {
    var p = [UInt8(0x80 | payload.count)] + payload
    p.append(p.reduce(UInt8(0x6E ^ 0x51)) { $0 ^ $1 })
    return p
}

func write(_ s: CFTypeRef, _ bytes: [UInt8]) -> Bool {
    var b = bytes
    for _ in 0..<5 {
        // Some displays only accept the command when sent twice in a row.
        var ok = true
        for _ in 0..<2 {
            usleep(10_000)
            if IOAVServiceWriteI2C(s, 0x37, 0x51, &b, UInt32(b.count)) != KERN_SUCCESS { ok = false }
        }
        if ok { return true }
        usleep(50_000)
    }
    return false
}

func readVCP(_ s: CFTypeRef, _ vcp: UInt8) -> (Int, Int)? {
    for _ in 0..<3 {
        guard write(s, packet([0x01, vcp])) else { continue }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        if IOAVServiceReadI2C(s, 0x37, 0x51, &reply, 11) == KERN_SUCCESS, reply[2] == 0x02, reply[3] == 0 {
            return (Int(reply[8]) << 8 | Int(reply[9]), Int(reply[6]) << 8 | Int(reply[7]))
        }
    }
    return nil
}

func parse(_ s: String) -> Int? {
    s.hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) : Int(s)
}

let args = CommandLine.arguments
guard args.count >= 3, let vcp = parse(args[2]).map(UInt8.init) else {
    print("usage: ddc get <vcp> | ddc set <vcp> <value>"); exit(2)
}
// Several "External" AV services may exist (unused ports); keep the one that answers.
guard let service = externalServices().first(where: { readVCP($0, 0x60) != nil }) else {
    print("no DDC-capable external display found"); exit(1)
}

switch args[1] {
case "set":
    guard args.count == 4, let v = parse(args[3]) else { print("missing value"); exit(2) }
    if !write(service, packet([0x03, vcp, UInt8(v >> 8), UInt8(v & 0xFF)])) { print("DDC write failed"); exit(1) }
case "get":
    guard let (cur, max) = readVCP(service, vcp) else { print("DDC read failed"); exit(1) }
    print("current=\(cur) max=\(max)")
default:
    print("usage: ddc get <vcp> | ddc set <vcp> <value>"); exit(2)
}
