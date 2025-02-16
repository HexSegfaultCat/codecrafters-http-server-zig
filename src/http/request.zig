const std = @import("std");

const HttpHeaders = @import("headers.zig");
const HttpMethod = enum {
    GET,
    POST,
    DELETE,
    PATCH,
    OPTIONS,
};

pub const HttpStatusError = error{
    MissingMethod,
    MissingUrl,
    MissingVersion,
    UnknownMethod,
    TooManyParameters,
};

pub const HttpHeaderError = error{
    MissingSeparator,
};

const Self = @This();

allocator: std.mem.Allocator,

method: HttpMethod = undefined,
version: []const u8 = "",
url: []const u8 = "",

headers: HttpHeaders,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .headers = HttpHeaders.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.version);
    self.allocator.free(self.url);

    self.headers.deinit();

    self.* = undefined;
}

pub fn parseStatusLine(self: *Self, rawStatusLine: []const u8) !void {
    var it = std.mem.splitSequence(u8, rawStatusLine, " ");

    if (it.next()) |method| {
        self.method = std.meta.stringToEnum(HttpMethod, method) orelse
            return HttpStatusError.UnknownMethod;
    } else {
        return HttpStatusError.MissingMethod;
    }

    if (it.next()) |url| {
        self.url = try self.allocator.dupe(u8, url);
    } else {
        return HttpStatusError.MissingUrl;
    }

    if (it.next()) |version| {
        self.version = try self.allocator.dupe(u8, version);
    } else {
        return HttpStatusError.MissingVersion;
    }

    if (it.next() != null) {
        return HttpStatusError.TooManyParameters;
    }
}

pub fn parseHeaders(self: *Self, rawHeaders: []const u8) !void {
    var it = std.mem.splitSequence(u8, rawHeaders, "\r\n");
    while (it.next()) |header| {
        const separatorIndex = std.mem.indexOfScalar(
            u8,
            header,
            ':',
        ) orelse return HttpHeaderError.MissingSeparator;

        try self.headers.addOrUpdate(
            header[0..separatorIndex],
            std.mem.trimLeft(u8, header[(separatorIndex + 1)..], " "),
        );
    }
}
