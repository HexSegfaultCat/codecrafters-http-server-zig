const std = @import("std");
const net = std.net;

const HttpServer = @import("http/server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = HttpServer.init(allocator);
    defer server.deinit();

    try server.configure(.{ .ipAddress = "127.0.0.1", .port = 4221 });

    try server.run();
}
