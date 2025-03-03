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

pub const Encoding = enum {
    None,
    Gzip,
};

allocator: std.mem.Allocator,

version: []const u8 = "1.1",
statusCode: StatusCode,
headers: HttpHeaders,

encoding: Encoding = .None,

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
    self.headers.deinit();
    self.plain.deinit();
    if (self.file) |file| {
        file.close();
    }

    self.* = undefined;
}

pub inline fn dataStream(self: Self) !std.io.AnyReader {
    if (self.file) |file| {
        try file.seekTo(0);
        return file.reader().any();
    } else {
        var stream = std.io.fixedBufferStream(self.plain.items);
        return stream.reader().any();
    }
}
