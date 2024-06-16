const std = @import("std");

const httpConsts = @import("./consts.zig");

pub const HttpResponse = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    protocolVersion: []const u8,
    statusCode: HttpStatus,
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

        if (self.body) |body| {
            self.allocator.free(body);
        }

        self.* = undefined;
    }

    pub fn updateResponse(
        self: *Self,
        builder: ?ResponseBuilder,
        response: EndpointResponse,
    ) !void {
        _ = builder;

        self.protocolVersion = httpConsts.HTTP_VERSION;
        self.statusCode = response.statusCode;

        if (response.body) |body| {
            self.body = try self.allocator.dupe(u8, body);

            try self.headers.put(
                httpConsts.HEADER_CONTENT_LENGTH,
                try std.fmt.allocPrint(self.allocator, "{d}", .{body.len}),
            );
        }

        if (response.contentType) |contentType| {
            try self.headers.put(
                httpConsts.HEADER_CONTENT_TYPE,
                try self.allocator.dupe(u8, contentType),
            );
        }
    }

    pub const HttpStatus = enum(u16) {
        Ok = 200,
        Created = 201,
        Unauthorized = 401,
        NotFound = 404,
        ServerError = 500,

        pub fn statusName(status: HttpStatus) []const u8 {
            return switch (status) {
                HttpStatus.Ok => "OK",
                HttpStatus.Created => "Created",
                HttpStatus.Unauthorized => "Unauthorized",
                HttpStatus.NotFound => "Not Found",
                HttpStatus.ServerError => "Internal Server Error",
            };
        }
    };
};

pub const EndpointResponse = struct {
    contentType: ?[]const u8 = "text/plain",
    statusCode: HttpResponse.HttpStatus = HttpResponse.HttpStatus.Ok,
    body: ?[]const u8 = null,
};

pub const ResponseBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    allocatedMemoryTracker: std.ArrayList([]u8),

    responseHeaders: *std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, headers: *std.StringHashMap([]const u8)) Self {
        return .{
            .allocator = allocator,
            .allocatedMemoryTracker = std.ArrayList([]u8).init(allocator),

            .responseHeaders = headers,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.allocatedMemoryTracker.items) |memory| {
            self.allocator.free(memory);
        }
        self.allocatedMemoryTracker.deinit();

        self.* = undefined;
    }

    pub fn deferMemoryToFree(self: *Self, memory: []u8) void {
        self.allocatedMemoryTracker.append(memory) catch {};
    }
};
