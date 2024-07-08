const std = @import("std");

const httpConsts = @import("./consts.zig");
const httpUtils = @import("./utils.zig");

const HttpHeaders = @import("./headers.zig");

const Self = @This();

allocator: std.mem.Allocator,

method: HttpMethod,
path: []const u8,
protocol: []const u8,
headers: HttpHeaders,

pathVariables: std.StringHashMap([]const u8),

body: ?[]const u8,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .method = undefined,
        .path = undefined,
        .protocol = undefined,
        .headers = HttpHeaders.init(allocator),

        .pathVariables = std.StringHashMap([]const u8).init(allocator),

        .body = null,
    };
}

pub fn deinit(self: *Self) void {
    self.headers.deinit();
    self.pathVariables.deinit();

    if (self.body) |body| {
        self.allocator.free(body);
    }

    self.* = undefined;
}

const ParseRequestError = error{
    MissingEndOfHeaderSection,
    MalformedHeader,
};
pub fn parseUpdateRequest(self: *Self, rawRequestData: std.ArrayList(u8)) !void {
    var requestIterator = std.mem.splitSequence(u8, rawRequestData.items, "\r\n");
    requestIterator.reset();

    var statusLine = std.mem.splitScalar(u8, requestIterator.first(), ' ');
    self.method = try HttpMethod.fromString(statusLine.next());
    self.path = try httpUtils.validatedPath(statusLine.next());
    self.protocol = try httpUtils.validatedProtocol(statusLine.next());

    while (requestIterator.next()) |headerLine| {
        // INFO: Empty line ends headers section
        if (headerLine.len == 0) {
            break;
        }

        const separatorIndex = std.mem.indexOfScalar(u8, headerLine, ':') orelse {
            return ParseRequestError.MalformedHeader;
        };

        const headerName = try std.ascii.allocUpperString(
            self.allocator,
            headerLine[0..separatorIndex],
        );
        const headerValue = try self.allocator.dupe(
            u8,
            std.mem.trimLeft(u8, headerLine[(separatorIndex + 1)..], " "),
        );
        try self.headers.addOrReplaceValue(headerName, headerValue);
    } else {
        return ParseRequestError.MissingEndOfHeaderSection;
    }

    const bodyData = requestIterator.next();
    if (bodyData) |body| {
        self.body = try self.allocator.dupe(u8, body);
    }
}

pub const HttpMethod = enum {
    Get,
    Post,

    pub const MethodError = error{
        MissingHttpMethod,
        MalformedHttpMethod,
    };

    pub fn fromString(methodName: ?[]const u8) MethodError!HttpMethod {
        if (methodName == null) {
            return MethodError.MissingHttpMethod;
        }

        var upperCaseStatus: [5]u8 = undefined;
        _ = std.ascii.upperString(
            &upperCaseStatus,
            methodName.?,
        );

        if (std.mem.eql(u8, upperCaseStatus[0..3], "GET")) {
            return HttpMethod.Get;
        } else if (std.mem.eql(u8, upperCaseStatus[0..4], "POST")) {
            return HttpMethod.Post;
        } else {
            return MethodError.MalformedHttpMethod;
        }
    }
};
