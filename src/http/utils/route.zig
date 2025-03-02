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

pub const Error = error{
    NotStartsWithSlash,
    MissingLeftBrace,
    MissingRightBrace,
    IncorrectOrderOfBraces,
    EmptyParamName,
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
    errdefer route.deinit();

    var pathIt = std.mem.splitScalar(comptime u8, route.path, '/');
    if (pathIt.next().?.len != 0) {
        std.log.warn("Path needs to start with '/': {s}", .{route.path});
        return Error.NotStartsWithSlash;
    }

    var pathPartIndex: usize = 1;
    while (pathIt.next()) |pathPart| : (pathPartIndex += 1) {
        const paramStartIndex = std.mem.indexOfScalar(u8, pathPart, '{');
        const paramEndIndex = std.mem.indexOfScalar(u8, pathPart, '}');

        if (paramStartIndex == null and paramEndIndex == null) {
            continue;
        }

        if (paramStartIndex == null) {
            std.log.warn("Missing '{{' symbol in path: {s}", .{route.path});
            return Error.MissingLeftBrace;
        } else if (paramEndIndex == null) {
            std.log.warn("Missing '}}' symbol in path: {s}", .{route.path});
            return Error.MissingRightBrace;
        } else if (paramStartIndex.? > paramEndIndex.?) {
            std.log.warn("Incorrect order of path param symbols: {s}", .{route.path});
            return Error.IncorrectOrderOfBraces;
        } else if (pathPart[(paramStartIndex.? + 1)..(paramEndIndex.?)].len == 0) {
            std.log.warn("Path param name must be at least 1 character long: {s}", .{route.path});
            return Error.EmptyParamName;
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
    self.params.clearAndFree();
    self.params.deinit();

    self.* = undefined;
}

test "path not starting with /" {
    const allocator = std.testing.allocator;

    const route = Self.init(allocator, .{
        .path = "some-path/other-part",
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    try std.testing.expectError(Error.NotStartsWithSlash, route);
}

test "path has '}' but doesn't have '{'" {
    const allocator = std.testing.allocator;

    const route = Self.init(allocator, .{
        .path = "/some-path/foo}abc",
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    try std.testing.expectError(Error.MissingLeftBrace, route);
}

test "path has '{' but doesn't have '}'" {
    const allocator = std.testing.allocator;

    const route = Self.init(allocator, .{
        .path = "/some-path/foo{abc",
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    try std.testing.expectError(Error.MissingRightBrace, route);
}

test "path has braces in incorrect order" {
    const allocator = std.testing.allocator;

    const route = Self.init(allocator, .{
        .path = "/some-path/foo}abc{",
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    try std.testing.expectError(Error.IncorrectOrderOfBraces, route);
}

test "path has empty param" {
    const allocator = std.testing.allocator;

    const route = Self.init(allocator, .{
        .path = "/some-path/{}",
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    try std.testing.expectError(Error.EmptyParamName, route);
}

test "path is valid" {
    const allocator = std.testing.allocator;

    const expectedPath = "/some-path/another-part";

    var route = try Self.init(allocator, .{
        .path = expectedPath,
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    defer route.deinit();

    try std.testing.expectEqualStrings(expectedPath, route.path);
    try std.testing.expectEqual(0, route.params.count());
}

test "path is valid and has params" {
    const allocator = std.testing.allocator;

    const urlTemplate = "/some-{s}/{s}/{s}-value";

    const expectedParamName1 = "someId";
    const expectedParamName2 = "product";
    const expectedParamName3 = "val";

    const expectedPath = std.fmt.comptimePrint(urlTemplate, .{
        "{" ++ expectedParamName1 ++ "}",
        "{" ++ expectedParamName2 ++ "}",
        "{" ++ expectedParamName3 ++ "}",
    });

    var route = try Self.init(allocator, .{
        .path = expectedPath,
        .method = .Get,
        .handler = struct {
            fn any(_: HttpRequest) anyerror!HttpResponse {
                return HttpResponse.init(allocator);
            }
        }.any,
    });
    defer route.deinit();

    try std.testing.expectEqualStrings(expectedPath, route.path);

    try std.testing.expectEqual(3, route.params.count());
    try std.testing.expectEqualStrings(expectedParamName1, route.params.get(1).?.name);
    try std.testing.expectEqualStrings(expectedParamName2, route.params.get(2).?.name);
    try std.testing.expectEqualStrings(expectedParamName3, route.params.get(3).?.name);
}
