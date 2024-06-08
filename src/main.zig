const std = @import("std");
const net = std.net;

const httpUtils = @import("./http_utils.zig");
const httpStructs = @import("./http_structs.zig");

pub fn main() !void {
    try createHttpServer("127.0.0.1", 4221);
}

pub fn createHttpServer(ipAddress: []const u8, port: u16) !void {
    const stdout = std.io.getStdOut().writer();
    const address = try net.Address.resolveIp(ipAddress, port);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    try stdout.print(
        "Listening on {s}:{d} for connections...\n",
        .{ ipAddress, port },
    );

    while (listener.accept()) |connection| {
        try stdout.print("Accepted new connection\n", .{});

        const allocator = std.heap.page_allocator;

        const requestData = try readStreamData(allocator, connection.stream);
        defer requestData.deinit();

        std.debug.print("[REQUEST] Received {d} bytes\n---\n{s}\n---\n", .{
            requestData.items.len,
            requestData.items,
        });

        const requestStruct = try parseRequest(requestData);

        const pathExistsOnServer =
            std.mem.eql(u8, requestStruct.path, "/") or
            std.mem.eql(u8, requestStruct.path, "/index.html");

        const responseStatus = switch (pathExistsOnServer) {
            true => httpUtils.HttpStatus.Ok,
            false => httpUtils.HttpStatus.NotFound,
        };

        const rawResponse = try std.fmt.allocPrint(
            allocator,
            "HTTP/{s} {d} {s}\r\n",
            .{
                httpUtils.HTTP_VERSION,
                @intFromEnum(responseStatus),
                httpUtils.HttpStatus.statusName(responseStatus),
            },
        );
        defer allocator.free(rawResponse);

        std.debug.print("[RESPONSE] {s}\n", .{rawResponse});
        try connection.stream.writeAll(rawResponse);

        // INFO: End header section
        try connection.stream.writeAll("\r\n");

        connection.stream.close();
    } else |err| {
        return err;
    }
}

fn readStreamData(allocator: std.mem.Allocator, stream: std.net.Stream) !std.ArrayList(u8) {
    var outputData = std.ArrayList(u8).init(allocator);

    const buffer = try allocator.alloc(u8, httpUtils.BUFFER_SIZE);
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

fn parseRequest(rawRequest: std.ArrayList(u8)) !httpStructs.StatusLine {
    var iterator = std.mem.splitSequence(
        u8,
        rawRequest.items,
        "\r\n",
    );
    iterator.reset();

    var statusLine = std.mem.splitScalar(u8, iterator.first(), ' ');

    const method = try httpUtils.HttpMethod.fromString(statusLine.next());
    const path = try httpUtils.validatedPath(statusLine.next());
    const protocol = try httpUtils.validatedProtocol(statusLine.next());

    while (iterator.next()) |line| {
        // TODO: Read headers
        // std.debug.print("Payload {d} bytes: {s}\n", .{ line.len, line });
        _ = line;
    }

    const statusLineStruct = httpStructs.StatusLine{
        .method = method,
        .path = path,
        .protocol = protocol,
    };

    return statusLineStruct;
}
