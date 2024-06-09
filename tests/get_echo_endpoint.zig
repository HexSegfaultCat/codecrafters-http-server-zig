const std = @import("std");
const http = std.http;
const testing = std.testing;

const httpClient = @import("./shared/http_client.zig");

test "Check echo response" {
    const echoValue = "abcdefg";

    var response = try httpClient.fetchResponse(
        "http://127.0.0.1:4221/echo/" ++ echoValue,
        http.Method.GET,
    );
    defer response.deinit();

    try testing.expectEqual(
        http.Status.ok,
        response.status,
    );
    try testing.expectEqualStrings(
        echoValue,
        response.body.items,
    );
}
