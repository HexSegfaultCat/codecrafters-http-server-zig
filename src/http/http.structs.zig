const std = @import("std");

const httpConsts = @import("./http.consts.zig");
const httpEnums = @import("./http.enums.zig");

pub const HttpRequestStatusLine = struct {
    method: httpEnums.HttpMethod,
    path: []const u8,
    protocol: []const u8,
};

pub const HttpResponseStatus = struct {
    protocolVersion: []const u8,
    statusCode: httpEnums.HttpStatus,
};

pub const HttpResponse = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    status: HttpResponseStatus,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .status = undefined,
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
        self.status = .{
            .protocolVersion = httpConsts.HTTP_VERSION,
            .statusCode = status,
        };

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
