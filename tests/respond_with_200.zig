const std = @import("std");
const http = std.http;
const testing = std.testing;

pub fn sendGetRequest(comptime ipAddress: []const u8, comptime port: u16) !http.Status {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var bodyResponse = std.ArrayListAligned(u8, null).init(allocator);
    defer bodyResponse.deinit();

    const httpResponse = try client.fetch(.{
        .location = .{
            .url = comptime std.fmt.comptimePrint(
                "http://{s}:{d}",
                .{ ipAddress, port },
            ),
        },
        .method = http.Method.GET,
        .keep_alive = false,
        .response_storage = .{
            .dynamic = &bodyResponse,
        },
    });

    return httpResponse.status;
}

test "switch on tagged union" {
    try testing.expectEqual(
        http.Status.ok,
        try sendGetRequest("127.0.0.1", 4221),
    );
}
