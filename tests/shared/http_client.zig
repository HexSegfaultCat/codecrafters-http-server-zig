const std = @import("std");
const http = std.http;

pub const Response = struct {
    const Self = @This();

    status: http.Status,
    body: std.ArrayList(u8),

    pub fn deinit(self: *Self) void {
        defer self.body.deinit();
    }
};

pub fn fetchResponse(comptime url: []const u8, method: http.Method) !Response {
    const allocator = std.heap.page_allocator;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var bodyResponse = std.ArrayList(u8).init(allocator);
    const httpResponse = try client.fetch(.{
        .location = .{ .uri = try std.Uri.parse(url) },
        .method = method,
        .keep_alive = false,
        .response_storage = .{
            .dynamic = &bodyResponse,
        },
    });

    return .{
        .status = httpResponse.status,
        .body = bodyResponse,
    };
}
