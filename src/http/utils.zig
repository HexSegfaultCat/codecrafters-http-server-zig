const std = @import("std");

const httpConsts = @import("./consts.zig");
const httpEnums = @import("./enums.zig");

const PathError = error{
    MissingPath,
    MalformedPath,
};
pub fn validatedPath(path: ?[]const u8) PathError![]const u8 {
    if (path == null) {
        return PathError.MissingPath;
    } else if (path.?.len == 0 or path.?[0] != '/') {
        return PathError.MalformedPath;
    }

    return path.?;
}

const ProtocolError = error{
    MissingProtocol,
    MalformedProtocol,
    UnknownProtocol,
    UnsupportedProtocolVersion,
};
pub fn validatedProtocol(protocol: ?[]const u8) ProtocolError![]const u8 {
    if (protocol == null) {
        return ProtocolError.MissingProtocol;
    }

    const separatorIndex = std.mem.indexOf(u8, protocol.?, "/") orelse {
        return ProtocolError.MalformedProtocol;
    };

    const protocolName = protocol.?[0..separatorIndex];
    const protocolVersion = protocol.?[(separatorIndex + 1)..];

    if (std.mem.eql(u8, protocolName, "HTTP") == false) {
        return ProtocolError.UnknownProtocol;
    } else if (std.mem.eql(u8, protocolVersion, httpConsts.HTTP_VERSION) == false) {
        return ProtocolError.UnsupportedProtocolVersion;
    }

    return protocol.?;
}
