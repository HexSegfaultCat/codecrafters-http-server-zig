const std = @import("std");

const HttpRequest = @import("./request.zig");
const HttpResponse = @import("./response.zig");

const HttpMethod = HttpRequest.HttpMethod;
const HttpStatus = HttpResponse.HttpStatus;

const ResponseAllocator = HttpResponse.ResponseAllocator;
const EndpointResponse = HttpResponse.EndpointResponse;

const Self = @This();

pub const EndpointHandler =
    *const fn (request: HttpRequest, builder: *ResponseAllocator) EndpointResponse;

allocator: std.mem.Allocator,

routes: std.StringHashMap(EndpointHandler),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .routes = std.StringHashMap(EndpointHandler).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.routes.deinit();
    self.* = undefined;
}

pub fn registerRoute(
    self: *Self,
    comptime method: HttpMethod,
    comptime path: []const u8,
    comptime handler: EndpointHandler,
) !void {
    const routingKey = @tagName(method) ++ ":" ++ path;

    // TODO: Add validations
    try self.routes.put(routingKey, handler);
}

pub fn findRouteHandlerAndUpdateVariablesMap(
    self: *Self,
    method: HttpMethod,
    path: []const u8,
    pathVariables: *std.StringHashMap([]const u8),
) !?EndpointHandler {
    var pathIterator = std.mem.splitScalar(
        u8,
        path,
        '/',
    );
    var routerIterator = self.routes.keyIterator();

    while (routerIterator.next()) |routerMethodPath| {
        const methodPathSeparatorIndex = std.mem.indexOfScalar(
            u8,
            routerMethodPath.*,
            ':',
        );

        const httpMethod = try HttpMethod.fromString(
            routerMethodPath.*[0..methodPathSeparatorIndex.?],
        );
        if (httpMethod != method) {
            continue;
        }

        pathIterator.reset();
        var routerPathIterator = std.mem.splitScalar(
            u8,
            routerMethodPath.*[(methodPathSeparatorIndex.? + 1)..],
            '/',
        );

        var clearingPathMapIterator = pathVariables.keyIterator();
        while (clearingPathMapIterator.next()) |variableKey| {
            pathVariables.removeByPtr(variableKey);
        }

        const wasPathMatched = try comparePathIterators(
            &routerPathIterator,
            &pathIterator,
            pathVariables,
        );
        if (wasPathMatched) {
            return self.routes.get(routerMethodPath.*).?;
        }
    }

    return null;
}

fn comparePathIterators(
    routerPathIterator: *std.mem.SplitIterator(u8, .scalar),
    lookupPathIterator: *std.mem.SplitIterator(u8, .scalar),
    variables: *std.StringHashMap([]const u8),
) !bool {
    while (routerPathIterator.next()) |routerPathPart| {
        const pathPart = lookupPathIterator.next();

        const comparisonResult = comparePathParts(
            routerPathPart,
            pathPart,
        );

        if (comparisonResult.variable != null) {
            try variables.put(
                comparisonResult.variable.?.name,
                comparisonResult.variable.?.value,
            );
        } else if (comparisonResult.isEqual == false) {
            return false;
        }
    }

    return true;
}

const PathPartCompareResult = struct {
    isEqual: bool,
    variable: ?struct {
        name: []const u8,
        value: []const u8,
    } = null,
};

// Assumes `routerPart.len` >= `requestPart.len`
fn comparePathParts(routerPart: []const u8, requestPart: ?[]const u8) PathPartCompareResult {
    if (requestPart == null) {
        return .{ .isEqual = false };
    } else if (routerPart.len == 0) {
        return .{ .isEqual = requestPart.?.len == 0 };
    }

    const lastIndex = routerPart.len - 1;
    if (routerPart[0] == '{' and routerPart[lastIndex] == '}') {
        return .{
            .isEqual = true,
            .variable = .{
                .name = routerPart[1..lastIndex],
                .value = requestPart.?,
            },
        };
    }

    return .{
        .isEqual = std.mem.eql(u8, requestPart.?, routerPart),
    };
}
