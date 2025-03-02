const std = @import("std");

const Self = @This();

const HttpUri = @import("utils/uri.zig");
const HttpRoute = @import("utils/route.zig");
const HttpRequest = @import("request.zig");
const HttpResponse = @import("response.zig");

const PathPairIterator = struct {
    index: usize = 0,
    requestPathIt: std.mem.SplitIterator(u8, .scalar),
    endpointPathIt: std.mem.SplitIterator(u8, .scalar),

    fn reset(
        self: *PathPairIterator,
        endpointPathIt: std.mem.SplitIterator(u8, .scalar),
    ) void {
        self.index = 0;
        self.requestPathIt.reset();
        self.endpointPathIt = endpointPathIt;
    }

    fn next(self: *PathPairIterator) ?struct {
        pathPartIndex: usize,
        requestPathPart: ?[]const u8,
        endpointPathPart: ?[]const u8,
    } {
        defer self.index += 1;

        const requestPathPart = self.requestPathIt.next();
        const endpointPathPart = self.endpointPathIt.next();

        if (requestPathPart == null and endpointPathPart == null) {
            return null;
        }

        return .{
            .pathPartIndex = self.index,
            .requestPathPart = requestPathPart,
            .endpointPathPart = endpointPathPart,
        };
    }
};

allocator: std.mem.Allocator,

routes: std.ArrayList(HttpRoute),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .routes = std.ArrayList(HttpRoute).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.routes.items) |*route| {
        route.deinit();
    }
    self.routes.deinit();

    self.* = undefined;
}

pub fn registerRoute(
    self: *Self,
    comptime method: HttpRequest.Method,
    comptime path: []const u8,
    comptime handler: HttpRoute.Handler,
) !void {
    const route = try HttpRoute.init(self.allocator, .{
        .method = method,
        .path = path,
        .handler = handler,
    });
    try self.routes.append(route);
}

pub fn matchEndpointHandlerAndUpdateRouteParams(
    self: *Self,
    method: HttpRequest.Method,
    uri: *HttpUri,
) !?HttpRoute {
    var pathPairIt = PathPairIterator{
        .requestPathIt = std.mem.splitScalar(u8, uri.url, '/'),
        .endpointPathIt = undefined,
    };

    endpoint: for (self.routes.items) |route| {
        if (method != route.method) {
            continue;
        }

        pathPairIt.reset(std.mem.splitScalar(u8, route.path, '/'));
        _ = pathPairIt.next();

        uri.pathParams.clearAndFree();

        while (pathPairIt.next()) |pathPair| {
            if (pathPair.requestPathPart == null or pathPair.endpointPathPart == null) {
                continue :endpoint;
            }

            if (route.params.get(pathPair.pathPartIndex)) |param| {
                const requestPrefix = pathPair.requestPathPart.?[0..param.startIndex];
                const endpointPrefix = pathPair.endpointPathPart.?[0..param.startIndex];
                if (false == std.mem.eql(u8, endpointPrefix, requestPrefix)) {
                    continue :endpoint;
                }

                const paramNameEndOffset =
                    pathPair.endpointPathPart.?.len - param.endIndex;
                const paramValueEndIndex =
                    pathPair.requestPathPart.?.len - paramNameEndOffset;

                const requestSuffix = pathPair.requestPathPart.?[(paramValueEndIndex + 1)..];
                const endpointSuffix = pathPair.endpointPathPart.?[(param.endIndex + 1)..];
                if (false == std.mem.eql(u8, endpointSuffix, requestSuffix)) {
                    continue :endpoint;
                }

                const paramValue = pathPair
                    .requestPathPart.?[param.startIndex..(paramValueEndIndex + 1)];

                try uri.pathParams.put(param.name, paramValue);
            } else if (false == std.mem.eql(
                u8,
                pathPair.endpointPathPart.?,
                pathPair.requestPathPart.?,
            )) {
                continue :endpoint;
            }
        }

        return route;
    }

    return null;
}

test "match route when different path registered with the same method" {
    const allocator = std.testing.allocator;

    const expectedMethod = HttpRequest.Method.Get;

    var router = init(allocator);
    defer router.deinit();

    try router.registerRoute(
        .Get,
        "/some-path",
        struct {
            fn handler(_: HttpRequest) anyerror!HttpResponse {
                return try HttpResponse.initPlain(allocator, .Ok, "");
            }
        }.handler,
    );

    var uri = try HttpUri.init(allocator, "/another-path");
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        expectedMethod,
        &uri,
    );

    try std.testing.expect(route == null);
}

test "match route when the same path registered with different method" {
    const allocator = std.testing.allocator;

    const expectedPath = "/some/long/path/for/this/test";

    var router = init(allocator);
    defer router.deinit();

    try router.registerRoute(
        .Get,
        expectedPath,
        struct {
            fn handler(_: HttpRequest) anyerror!HttpResponse {
                return try HttpResponse.initPlain(allocator, .Ok, "");
            }
        }.handler,
    );

    var uri = try HttpUri.init(allocator, expectedPath);
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        .Post,
        &uri,
    );

    try std.testing.expect(route == null);
}

test "match route when the same path registered with the same method" {
    const allocator = std.testing.allocator;

    const expectedMethod = HttpRequest.Method.Get;
    const expectedPath = "/some/long/path/for/this/test";

    var router = init(allocator);
    defer router.deinit();

    try router.registerRoute(
        expectedMethod,
        expectedPath,
        struct {
            fn handler(_: HttpRequest) anyerror!HttpResponse {
                return try HttpResponse.initPlain(allocator, .Ok, "");
            }
        }.handler,
    );

    var uri = try HttpUri.init(allocator, expectedPath);
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        expectedMethod,
        &uri,
    );

    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings(expectedPath, route.?.path);
}

test "match route with single param when matching route registered" {
    const allocator = std.testing.allocator;

    const urlTemplate = "/product/{s}";

    const expectedParamName = "id";
    const expectedParamValue = "some-id";

    const expectedRouteUrl = std.fmt.comptimePrint(urlTemplate, .{
        "{" ++ expectedParamName ++ "}",
    });

    var router = init(allocator);
    defer router.deinit();

    try router.registerRoute(
        .Get,
        expectedRouteUrl,
        struct {
            fn handler(_: HttpRequest) anyerror!HttpResponse {
                return try HttpResponse.initPlain(allocator, .Ok, "");
            }
        }.handler,
    );

    var uri = try HttpUri.init(
        allocator,
        std.fmt.comptimePrint(urlTemplate, .{expectedParamValue}),
    );
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        .Get,
        &uri,
    );

    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings(expectedRouteUrl, route.?.path);

    try std.testing.expectEqual(1, uri.pathParams.count());
    try std.testing.expectEqualStrings(
        expectedParamValue,
        uri.pathParams.getEntry(expectedParamName).?.value_ptr.*,
    );
}

test "match route with multiple params when matching route registered" {
    const allocator = std.testing.allocator;

    const urlTemplate = "/product/{s}/prop-{s}";

    const expectedParamName1 = "id";
    const expectedParamValue1 = "some-id";
    const expectedParamName2 = "param";
    const expectedParamValue2 = "x1";

    const expectedRouteUrl = std.fmt.comptimePrint(urlTemplate, .{
        "{" ++ expectedParamName1 ++ "}",
        "{" ++ expectedParamName2 ++ "}",
    });

    var router = init(allocator);
    defer router.deinit();

    try router.registerRoute(
        .Get,
        expectedRouteUrl,
        struct {
            fn handler(_: HttpRequest) anyerror!HttpResponse {
                return try HttpResponse.initPlain(allocator, .Ok, "");
            }
        }.handler,
    );

    var uri = try HttpUri.init(
        allocator,
        std.fmt.comptimePrint(urlTemplate, .{
            expectedParamValue1,
            expectedParamValue2,
        }),
    );
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        .Get,
        &uri,
    );

    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings(expectedRouteUrl, route.?.path);

    try std.testing.expectEqual(2, uri.pathParams.count());
    try std.testing.expectEqualStrings(
        expectedParamValue1,
        uri.pathParams.getEntry(expectedParamName1).?.value_ptr.*,
    );
    try std.testing.expectEqualStrings(
        expectedParamValue2,
        uri.pathParams.getEntry(expectedParamName2).?.value_ptr.*,
    );
}

test "match route with multiple params when matching and non matching routes registered" {
    const allocator = std.testing.allocator;

    const urlTemplate = "/product/example/prop-{s}";

    const expectedParamName = "param";
    const expectedParamValue = "x1";

    const expectedRouteUrl = std.fmt.comptimePrint(urlTemplate, .{
        "{" ++ expectedParamName ++ "}",
    });

    var router = init(allocator);
    defer router.deinit();

    const handlers = struct {
        fn proper(_: HttpRequest) anyerror!HttpResponse {
            return try HttpResponse.initPlain(allocator, .Ok, "");
        }
        fn wrong(_: HttpRequest) anyerror!HttpResponse {
            return try HttpResponse.initPlain(allocator, .Ok, "");
        }
    };
    try router.registerRoute(.Get, "/{name}", handlers.wrong);
    try router.registerRoute(.Get, "/data/{id}/prop-{param}", handlers.wrong);
    try router.registerRoute(.Get, expectedRouteUrl, handlers.proper);

    var uri = try HttpUri.init(
        allocator,
        std.fmt.comptimePrint(urlTemplate, .{
            expectedParamValue,
        }),
    );
    defer uri.deinit();

    const route = try router.matchEndpointHandlerAndUpdateRouteParams(
        .Get,
        &uri,
    );

    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings(expectedRouteUrl, route.?.path);
    try std.testing.expectEqual(handlers.proper, route.?.handler);

    try std.testing.expectEqual(1, uri.pathParams.count());
    try std.testing.expectEqualStrings(
        expectedParamValue,
        uri.pathParams.getEntry(expectedParamName).?.value_ptr.*,
    );
}
