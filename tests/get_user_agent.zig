const std = @import("std");
const http = std.http;
const testing = std.testing;

const httpClient = @import("./shared/http_client.zig");

test "Check user agent response" {
    const customUserAgent = "zig/0.12.0 (custom-user-agent)";

    var response = try httpClient.fetchResponse(
        "http://127.0.0.1:4221/user-agent",
        http.Method.GET,
        .{
            .user_agent = .{ .override = customUserAgent },
        },
    );
    defer response.deinit();

    try testing.expectEqual(
        http.Status.ok,
        response.status,
    );
    try testing.expectEqualStrings(
        customUserAgent,
        response.body.items,
    );
}
