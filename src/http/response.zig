const std = @import("std");

const HttpConsts = @import("./consts.zig");

const HttpHeaders = @import("./headers.zig");
const HttpCompressionScheme = @import("./compression.zig").CompressionScheme;

const Self = @This();

allocator: std.mem.Allocator,

protocolVersion: []const u8,
statusCode: HttpStatus,
headers: HttpHeaders,

compression: HttpCompressionScheme,
plainTextBody: []const u8,
compressedBytesBody: ?std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .protocolVersion = undefined,
        .statusCode = undefined,
        .headers = HttpHeaders.init(allocator),

        .compression = .None,
        .plainTextBody = &[_]u8{},
        .compressedBytesBody = null,
    };
}

pub fn deinit(self: *Self) void {
    self.headers.deinit();

    self.allocator.free(self.plainTextBody);
    if (self.compressedBytesBody) |byteBody| {
        byteBody.deinit();
    }

    self.* = undefined;
}

pub fn updateResponse(
    self: *Self,
    endpointResponse: EndpointResponse,
    compressionSchemes: std.ArrayList(HttpCompressionScheme),
) !void {
    try updateData(self, endpointResponse, compressionSchemes);

    if (self.compression == .Gzip) {
        self.compressedBytesBody = std.ArrayList(u8).init(self.allocator);

        var compressor = try std.compress.gzip.compressor(
            self.compressedBytesBody.?.writer(),
            .{ .level = .default },
        );
        _ = try compressor.write(self.plainTextBody);
        try compressor.flush();
        try compressor.finish();
    }

    try updateHeaders(self, endpointResponse);
}

fn updateData(
    self: *Self,
    endpointResponse: EndpointResponse,
    compressionSchemes: std.ArrayList(HttpCompressionScheme),
) !void {
    self.protocolVersion = HttpConsts.HTTP_VERSION;
    self.statusCode = endpointResponse.statusCode;

    if (endpointResponse.body) |body| {
        self.plainTextBody = try self.allocator.dupe(u8, body);
    }

    for (compressionSchemes.items) |compression| {
        if (compression == .Gzip) {
            self.compression = compression;
        }
    }
}

fn updateHeaders(self: *Self, endpointResponse: EndpointResponse) !void {
    if (endpointResponse.contentType) |contentType| {
        try self.headers.addOrReplaceValue(
            HttpHeaders.HEADER_CONTENT_TYPE,
            contentType,
        );
    }

    if (self.compression == .Gzip) {
        try self.headers.addOrAppendValue(
            HttpHeaders.HEADER_CONTENT_ENCODING,
            self.compression.toString(),
        );
    }

    const length = if (self.compressedBytesBody) |bytesBody|
        bytesBody.items.len
    else
        self.plainTextBody.len;

    const lengthAsString = try std.fmt.allocPrint(
        self.allocator,
        "{d}",
        .{length},
    );
    defer self.allocator.free(lengthAsString);

    try self.headers.addOrReplaceValue(
        HttpHeaders.HEADER_CONTENT_LENGTH,
        lengthAsString,
    );
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
