const std = @import("std");
const http = std.http;
const testing = std.testing;

const httpClient = @import("./shared/http_client.zig");

test "Check response for empty request" {
    var response = try httpClient.fetchResponse(
        "http://127.0.0.1:4221",
        http.Method.GET,
        .{ .accept_encoding = .omit },
    );
    defer response.deinit();

    try testing.expectEqual(
        http.Status.ok,
        response.status,
    );
}

test "Check response for `index.html`" {
    var response = try httpClient.fetchResponse(
        "http://127.0.0.1:4221/index.html",
        http.Method.GET,
        .{ .accept_encoding = .omit },
    );
    defer response.deinit();

    try testing.expectEqual(
        http.Status.ok,
        response.status,
    );
}
