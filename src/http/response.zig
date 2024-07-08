const std = @import("std");

const HttpConsts = @import("./consts.zig");

const HttpHeaders = @import("./headers.zig");
const HttpCompressionScheme = @import("./compression.zig").CompressionScheme;

const Self = @This();

allocator: std.mem.Allocator,

protocolVersion: []const u8,
statusCode: HttpStatus,
headers: HttpHeaders,

body: ?[]const u8,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .protocolVersion = undefined,
        .statusCode = undefined,
        .headers = HttpHeaders.init(allocator),

        .body = null,
    };
}

pub fn deinit(self: *Self) void {
    self.headers.deinit();

    if (self.body) |body| {
        self.allocator.free(body);
    }

    self.* = undefined;
}

pub fn updateResponse(
    self: *Self,
    endpointResponse: EndpointResponse,
    compressionSchemes: std.ArrayList(HttpCompressionScheme),
) !void {
    self.protocolVersion = HttpConsts.HTTP_VERSION;
    self.statusCode = endpointResponse.statusCode;

    if (endpointResponse.body) |body| {
        self.body = try self.allocator.dupe(u8, body);

        const lengthCopy = try std.fmt.allocPrint(self.allocator, "{d}", .{body.len});
        defer self.allocator.free(lengthCopy);

        try self.headers.addOrReplaceValue(
            HttpHeaders.HEADER_CONTENT_LENGTH,
            lengthCopy,
        );
    }

    if (endpointResponse.contentType) |contentType| {
        const contentTypeCopy = try self.allocator.dupe(u8, contentType);
        defer self.allocator.free(contentTypeCopy);

        try self.headers.addOrReplaceValue(
            HttpHeaders.HEADER_CONTENT_TYPE,
            contentTypeCopy,
        );
    }

    for (compressionSchemes.items) |compression| {
        try self.headers.addOrAppendValue(
            HttpHeaders.HEADER_CONTENT_ENCODING,
            compression.toString(),
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

pub const EndpointResponse = struct {
    contentType: ?[]const u8 = "text/plain",
    statusCode: HttpStatus = .Ok,
    body: ?[]const u8 = null,
};

pub const ResponseAllocator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    allocatedMemoryTracker: std.ArrayList([]u8),

    responseHeaders: *HttpHeaders,

    pub fn init(allocator: std.mem.Allocator, headers: *HttpHeaders) ResponseAllocator.Self {
        return .{
            .allocator = allocator,
            .allocatedMemoryTracker = std.ArrayList([]u8).init(allocator),

            .responseHeaders = headers,
        };
    }

    pub fn deinit(self: *ResponseAllocator.Self) void {
        for (self.allocatedMemoryTracker.items) |memory| {
            self.allocator.free(memory);
        }
        self.allocatedMemoryTracker.deinit();

        self.* = undefined;
    }

    pub fn deferMemoryToFree(self: *ResponseAllocator.Self, memory: []u8) void {
        self.allocatedMemoryTracker.append(memory) catch {};
    }
};
