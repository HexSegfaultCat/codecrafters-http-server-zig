const std = @import("std");

const Self = @This();

const HttpUri = @import("utils/uri.zig");
const HttpHeaders = @import("headers.zig");

pub const Method = enum {
    Get,
    Put,
    Post,
    Head,
    Patch,
    Delete,
    Options,

    pub const MethodError = error{
        UnknownMethod,
    };

    pub fn fromString(method: []const u8) MethodError!Method {
        if (std.ascii.eqlIgnoreCase(method, "GET")) {
            return .Get;
        } else if (std.ascii.eqlIgnoreCase(method, "PUT")) {
            return .Put;
        } else if (std.ascii.eqlIgnoreCase(method, "POST")) {
            return .Post;
        } else if (std.ascii.eqlIgnoreCase(method, "HEAD")) {
            return .Head;
        } else if (std.ascii.eqlIgnoreCase(method, "PATCH")) {
            return .Patch;
        } else if (std.ascii.eqlIgnoreCase(method, "DELETE")) {
            return .Delete;
        } else if (std.ascii.eqlIgnoreCase(method, "OPTIONS")) {
            return .Options;
        } else {
            return MethodError.UnknownMethod;
        }
    }
};

pub const HttpStatusError = error{
    MissingMethod,
    MissingUrl,
    MissingProtocol,
    MissingVersion,
    TooManyParameters,
    IncorrectProtocol,
} || Method.MethodError;

pub const HttpHeaderError = error{
    MissingSeparator,
};

allocator: std.mem.Allocator,

uri: HttpUri = undefined,
method: Method = undefined,
version: []const u8 = "",

headers: HttpHeaders,

body: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .headers = HttpHeaders.init(allocator),
        .body = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.version);

    self.uri.deinit();
    self.headers.deinit();

    self.* = undefined;
}

pub fn parseStatusLine(self: *Self, rawStatusLine: []const u8) !void {
    var statusIt = std.mem.splitSequence(u8, rawStatusLine, " ");

    const method = statusIt.next();
    const uri = statusIt.next();
    const protocolVersion = statusIt.next();

    if (method == null) {
        return HttpStatusError.MissingMethod;
    } else if (uri == null) {
        return HttpStatusError.MissingUrl;
    } else if (protocolVersion == null) {
        return HttpStatusError.MissingProtocol;
    } else if (statusIt.next() != null) {
        return HttpStatusError.TooManyParameters;
    } else {
        self.method = try Method.fromString(method.?);
        self.uri = try HttpUri.init(self.allocator, uri.?);
    }

    var versionIt = std.mem.splitScalar(u8, protocolVersion.?, '/');

    const protocol = versionIt.next();
    const version = versionIt.next();

    if (protocol == null) {
        return HttpStatusError.MissingProtocol;
    } else if (std.ascii.eqlIgnoreCase(protocol.?, "HTTP") == false) {
        return HttpStatusError.IncorrectProtocol;
    } else if (version == null) {
        return HttpStatusError.MissingVersion;
    } else if (versionIt.next() != null) {
        return HttpStatusError.TooManyParameters;
    } else {
        self.version = try self.allocator.dupe(u8, version.?);
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
