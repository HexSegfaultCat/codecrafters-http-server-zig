const std = @import("std");
const http = std.http;
const testing = std.testing;

test "Check user agent response" {
    const allocator = std.heap.page_allocator;

    const expectedUserAgent = "zig/0.13.0 (custom-user-agent)";

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{
            .uri = try std.Uri.parse("http://127.0.0.1:4221/user-agent"),
        },
        .headers = .{
            .user_agent = .{ .override = expectedUserAgent },
            .accept_encoding = .omit,
        },
        .response_storage = .{
            .dynamic = &data,
        },
        .keep_alive = false,
    });

    try testing.expectEqual(.ok, response.status);
    try testing.expectEqualStrings(expectedUserAgent, data.items);
}
