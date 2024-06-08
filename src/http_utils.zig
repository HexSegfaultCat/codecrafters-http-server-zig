const std = @import("std");

pub const HTTP_VERSION = "1.1";
pub const BUFFER_SIZE = 512;

pub const HttpStatus = enum(u16) {
    Ok = 200,
    NotFound = 404,

    pub fn statusName(status: HttpStatus) []const u8 {
        return switch (status) {
            HttpStatus.Ok => "OK",
            HttpStatus.NotFound => "Not Found",
        };
    }
};

const MethodError = error{
    MissingHttpMethod,
    MalformedHttpMethod,
};
pub const HttpMethod = enum {
    Get,
    Post,

    pub fn fromString(status: ?[]const u8) MethodError!HttpMethod {
        if (status == null) {
            return MethodError.MissingHttpMethod;
        }

        var upperCaseStatus: [10]u8 = undefined;
        _ = std.ascii.upperString(
            &upperCaseStatus,
            status.?,
        );

        if (std.mem.eql(u8, upperCaseStatus[0..3], "GET")) {
            return HttpMethod.Get;
        } else if (std.mem.eql(u8, upperCaseStatus[0..4], "POST")) {
            return HttpMethod.Post;
        } else {
            return MethodError.MalformedHttpMethod;
        }
    }
};

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
    } else if (std.mem.eql(u8, protocolVersion, HTTP_VERSION) == false) {
        return ProtocolError.UnsupportedProtocolVersion;
    }

    return protocol.?;
}
