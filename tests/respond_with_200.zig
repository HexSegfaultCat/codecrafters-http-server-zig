const std = @import("std");
const http = std.http;
const testing = std.testing;

test "Check response for empty request" {
    const allocator = std.heap.page_allocator;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{
            .uri = try std.Uri.parse("http://127.0.0.1:4221"),
        },
        .headers = .{ .accept_encoding = .omit },
        .keep_alive = false,
    });

    try testing.expectEqual(
        .ok,
        response.status,
    );
}

test "Check response for `index.html`" {
    const allocator = std.heap.page_allocator;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{
            .uri = try std.Uri.parse("http://127.0.0.1:4221/index.html"),
        },
        .headers = .{ .accept_encoding = .omit },
        .keep_alive = false,
    });

    try testing.expectEqual(
        .ok,
        response.status,
    );
}
