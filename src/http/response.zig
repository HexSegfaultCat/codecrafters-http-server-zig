const std = @import("std");

const httpConsts = @import("./consts.zig");
const httpEnums = @import("./enums.zig");

pub const HttpResponse = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    protocolVersion: []const u8,
    statusCode: httpEnums.HttpStatus,
    headers: std.StringHashMap([]const u8),

    body: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,

            .protocolVersion = undefined,
            .statusCode = undefined,

            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var headerValueIterator = self.headers.valueIterator();
        while (headerValueIterator.next()) |headerValue| {
            self.allocator.free(headerValue.*);
        }
        self.headers.deinit();
        if (self.body != null) {
            self.allocator.free(self.body.?);
        }
    }

    pub fn prepare(
        self: *Self,
        status: httpEnums.HttpStatus,
        body: ?[]const u8,
        contentType: ?[]const u8,
    ) !void {
        self.protocolVersion = httpConsts.HTTP_VERSION;
        self.statusCode = status;

        if (body != null) {
            self.body = try self.allocator.dupe(u8, body.?);

            try self.headers.put(
                httpConsts.HEADER_CONTENT_LENGTH,
                try std.fmt.allocPrint(
                    self.allocator,
                    "{d}",
                    .{body.?.len},
                ),
            );
        }

        if (contentType != null) {
            try self.headers.put(
                httpConsts.HEADER_CONTENT_TYPE,
                try self.allocator.dupe(u8, contentType.?),
            );
        }
    }
};

pub fn sendResponse(response: HttpResponse, stream: std.net.Stream) !void {
    const statusResponse = try std.fmt.allocPrint(
        response.allocator,
        "HTTP/{s} {d} {s}\r\n",
        .{
            response.protocolVersion,
            @intFromEnum(response.statusCode),
            httpEnums.HttpStatus.statusName(response.statusCode),
        },
    );
    defer response.allocator.free(statusResponse);

    try stream.writeAll(statusResponse);

    var headersIterator = response.headers.iterator();
    while (headersIterator.next()) |headerEntry| {
        const headerResponse = try std.fmt.allocPrint(
            response.allocator,
            "{s}: {s}\r\n",
            .{ headerEntry.key_ptr.*, headerEntry.value_ptr.* },
        );
        defer response.allocator.free(headerResponse);

        try stream.writeAll(headerResponse);
    }

    // INFO: Ends header section
    try stream.writeAll("\r\n");

    if (response.body != null) {
        try stream.writeAll(response.body.?);
    }
}
