const std = @import("std");
const net = std.net;

const httpConsts = @import("./http_consts.zig");

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

    try stdout.print("Listening on {s}:{d} for connections...\n", .{ ipAddress, port });

    while (true) {
        const connection = try listener.accept();
        try stdout.print("Accepted new connection\n", .{});

        const allocator = std.heap.page_allocator;

        const buffer = try allocator.alloc(u8, 200);
        defer allocator.free(buffer);

        for (0..buffer.len) |i| {
            buffer[i] = 0;
        }
        const byteCount = try connection.stream.read(buffer);
        try stdout.print("Received {d} bytes: {s}\n", .{ byteCount, buffer });

        const httpStatusLine = comptime std.fmt.comptimePrint(
            "HTTP/{s} {d} {s}\r\n",
            .{
                httpConsts.HTTP_VERSION,
                @intFromEnum(httpConsts.HttpStatus.Ok),
                httpConsts.HttpStatus.statusName(httpConsts.HttpStatus.Ok),
            },
        );
        try connection.stream.writeAll(httpStatusLine);

        // INFO: End header section
        try connection.stream.writeAll("\r\n");

        connection.stream.close();
    }
}
