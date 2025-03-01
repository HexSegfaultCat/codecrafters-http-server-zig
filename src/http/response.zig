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

body: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .statusCode = .Ok,
        .headers = HttpHeaders.init(allocator),

        .body = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.body.deinit();
    self.headers.deinit();

    self.* = undefined;
}
