const std = @import("std");

const Self = @This();

const HttpRequest = @import("../request.zig");
const HttpResponse = @import("../response.zig");

pub const Handler = *const fn (request: HttpRequest) anyerror!HttpResponse;
pub const Param = struct {
    startIndex: usize,
    endIndex: usize,
    name: []const u8,
};

method: HttpRequest.Method,
path: []const u8,
handler: Handler,

params: std.AutoArrayHashMap(usize, Param) = undefined,

pub fn init(allocator: std.mem.Allocator, endpointDetails: Self) !Self {
    var route = Self{
        .method = endpointDetails.method,
        .path = endpointDetails.path,
        .handler = endpointDetails.handler,

        .params = std.AutoArrayHashMap(usize, Param).init(allocator),
    };

    var pathIt = std.mem.splitScalar(comptime u8, route.path, '/');
    if (pathIt.next().?.len != 0) {
        @panic("Path needs to start with '/'");
    }

    var pathPartIndex: usize = 1;
    while (pathIt.next()) |pathPart| : (pathPartIndex += 1) {
        const paramStartIndex = std.mem.indexOfScalar(u8, pathPart, '{');
        const paramEndIndex = std.mem.indexOfScalar(u8, pathPart, '}');

        if (paramStartIndex == null and paramEndIndex == null) {
            continue;
        }

        if (paramStartIndex == null and paramEndIndex != null) {
            @panic("Missing '{' symbol in path");
        } else if (paramStartIndex != null and paramEndIndex == null) {
            @panic("Missing '}' symbol in path");
        } else if (paramStartIndex.? > paramEndIndex.?) {
            @panic("Incorrect order of path param symbols");
        } else if (pathPart[(paramStartIndex.?)..(paramEndIndex.?)].len == 0) {
            @panic("Path param name must be at least 1 character long");
        }

        try route.params.put(pathPartIndex, .{
            .startIndex = paramStartIndex.?,
            .endIndex = paramEndIndex.?,
            .name = pathPart[(paramStartIndex.? + 1)..paramEndIndex.?],
        });
    }

    return route;
}

pub fn deinit(self: *Self) void {
    self.params.deinit();

    self.* = undefined;
}
