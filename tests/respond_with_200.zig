const std = @import("std");
const http = std.http;
const testing = std.testing;

pub fn sendGetRequest(comptime url: []const u8) !http.Status {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var bodyResponse = std.ArrayListAligned(u8, null).init(allocator);
    defer bodyResponse.deinit();

    const httpResponse = try client.fetch(.{
        .location = .{ .uri = try std.Uri.parse(url) },
        .method = http.Method.GET,
        .keep_alive = false,
        .response_storage = .{
            .dynamic = &bodyResponse,
        },
    });

    return httpResponse.status;
}

test "Check response for empty request" {
    try testing.expectEqual(
        http.Status.ok,
        try sendGetRequest("http://127.0.0.1:4221"),
    );
}

test "Check response for `index.html`" {
    try testing.expectEqual(
        http.Status.ok,
        try sendGetRequest("http://127.0.0.1:4221/index.html"),
    );
}
