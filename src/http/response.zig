const std = @import("std");

const Self = @This();

const HttpHeaders = @import("headers.zig");

pub const StatusCode = enum(u16) {
    Ok = 200,
    Created = 201,
    Unauthorized = 401,
    NotFound = 404,
    ServerError = 500,

    pub fn name(status: StatusCode) []const u8 {
        return switch (status) {
            .Ok => "OK",
            .Created => "Created",
            .Unauthorized => "Unauthorized",
            .NotFound => "Not Found",
            .ServerError => "Internal Server Error",
        };
    }
};

allocator: std.mem.Allocator,

version: []const u8 = "1.1",
statusCode: StatusCode,
headers: HttpHeaders,

plain: std.ArrayList(u8) = undefined,
file: ?std.fs.File = null,

pub fn initPlain(
    allocator: std.mem.Allocator,
    statusCode: StatusCode,
    data: []const u8,
) !Self {
    var self = Self{
        .allocator = allocator,

        .statusCode = statusCode,
        .headers = HttpHeaders.init(allocator),

        .plain = std.ArrayList(u8).init(allocator),
    };

    try self.headers.addOrUpdate("Content-Type", "text/plain");
    try self.plain.appendSlice(data);

    return self;
}

pub fn initAsFileStream(allocator: std.mem.Allocator, file: std.fs.File) !Self {
    var self = Self{
        .allocator = allocator,

        .statusCode = .Ok,
        .headers = HttpHeaders.init(allocator),

        .file = file,
    };

    try self.headers.addOrUpdate("Content-Type", "application/octet-stream");

    return self;
}

pub fn deinit(self: *Self) void {
    self.plain.deinit();
    self.headers.deinit();

    self.* = undefined;
}
