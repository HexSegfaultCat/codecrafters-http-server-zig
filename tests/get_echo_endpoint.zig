const std = @import("std");
const http = std.http;
const testing = std.testing;

test "Check echo response" {
    const allocator = std.heap.page_allocator;

    const expectedEchoValue = "abcdefg";

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{
            .uri = try std.Uri.parse(
                "http://127.0.0.1:4221/echo/" ++ expectedEchoValue,
            ),
        },
        .headers = .{ .accept_encoding = .omit },
        .response_storage = .{
            .dynamic = &data,
        },
        .keep_alive = false,
    });

    try testing.expectEqual(.ok, response.status);
    try testing.expectEqualStrings(expectedEchoValue, data.items);
}
