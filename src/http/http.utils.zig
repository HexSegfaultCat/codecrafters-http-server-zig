const std = @import("std");

const httpConsts = @import("./http.consts.zig");
const httpEnums = @import("./http.enums.zig");
const httpStructs = @import("./http.structs.zig");

pub fn readStreamData(allocator: std.mem.Allocator, stream: std.net.Stream) !std.ArrayList(u8) {
    var outputData = std.ArrayList(u8).init(allocator);

    const buffer = try allocator.alloc(u8, httpConsts.BUFFER_SIZE);
    defer allocator.free(buffer);
    @memset(buffer, 0);

    var fds =
        [_]std.posix.pollfd{.{
        .fd = stream.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    while (stream.read(buffer)) |bytesRead| {
        try outputData.appendSlice(buffer[0..bytesRead]);

        // INFO: Handle edgecase where socket waits for data if `bytesRead == buffer.len`
        const dataAvailable = try std.posix.poll(&fds, 0);
        if (bytesRead < buffer.len or dataAvailable == 0) {
            break;
        }
    } else |err| {
        return err;
    }

    return outputData;
}

pub fn parseRequest(rawRequest: std.ArrayList(u8)) !httpStructs.HttpRequestStatusLine {
    var iterator = std.mem.splitSequence(
        u8,
        rawRequest.items,
        "\r\n",
    );
    iterator.reset();

    var statusLine = std.mem.splitScalar(u8, iterator.first(), ' ');

    const method = try httpEnums.HttpMethod.fromString(statusLine.next());
    const path = try validatedPath(statusLine.next());
    const protocol = try validatedProtocol(statusLine.next());

    while (iterator.next()) |line| {
        // TODO: Read headers
        // std.debug.print("Payload {d} bytes: {s}\n", .{ line.len, line });
        _ = line;
    }

    const statusLineStruct = httpStructs.HttpRequestStatusLine{
        .method = method,
        .path = path,
        .protocol = protocol,
    };

    return statusLineStruct;
}

pub fn sendResponse(response: httpStructs.HttpResponse, stream: std.net.Stream) !void {
    const statusResponse = try std.fmt.allocPrint(
        response.allocator,
        "HTTP/{s} {d} {s}\r\n",
        .{
            response.status.protocolVersion,
            @intFromEnum(response.status.statusCode),
            httpEnums.HttpStatus.statusName(response.status.statusCode),
        },
    );
    defer response.allocator.free(statusResponse);

    std.debug.print("[RESPONSE] {s}\n", .{statusResponse});
    try stream.writeAll(statusResponse);

    var headersIterator = response.headers.iterator();
    while (headersIterator.next()) |headerEntry| {
        const headerResponse = try std.fmt.allocPrint(
            response.allocator,
            "{s}: {s}\r\n",
            .{ headerEntry.key_ptr.*, headerEntry.value_ptr.* },
        );
        defer response.allocator.free(headerResponse);

        try stream.writeAll(headerResponse);
    }

    // INFO: Ends header section
    try stream.writeAll("\r\n");

    if (response.body != null) {
        try stream.writeAll(response.body.?);
    }
}

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
