const std = @import("std");

const httpEnums = @import("./enums.zig");

const HttpRequest = @import("./request.zig").HttpRequest;
const HttpResponse = @import("./response.zig").HttpResponse;

pub const HttpRouter = struct {
    const Self = @This();

    pub const EndpointHandler = *const fn (request: HttpRequest, data: *EndpointData) ?[]const u8;
    pub const EndpointData = struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        pathVariables: std.StringHashMap([]const u8),
        allocatedMemoryTracker: std.ArrayList([]u8),

        contentType: []const u8,
        httpStatus: httpEnums.HttpStatus,

        pub fn init(allocator: std.mem.Allocator, pathVariables: std.StringHashMap([]const u8)) EndpointData.Self {
            return .{
                .allocator = allocator,

                .pathVariables = pathVariables,
                .allocatedMemoryTracker = std.ArrayList([]u8).init(allocator),

                .contentType = "text/plain",
                .httpStatus = httpEnums.HttpStatus.Ok,
            };
        }

        pub fn deinit(self: *EndpointData.Self) void {
            self.pathVariables.deinit();

            for (self.allocatedMemoryTracker.items) |memory| {
                self.allocator.free(memory);
            }
            self.allocatedMemoryTracker.deinit();
        }

        pub fn deferMemoryToFree(self: *EndpointData.Self, memory: []u8) void {
            self.allocatedMemoryTracker.append(memory) catch {};
        }
    };

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

    pub const RouteError = error{
        MalformedPath,
    };

    pub fn registerRoute(self: *Self, comptime path: []const u8, comptime handler: EndpointHandler) !void {
        // TODO: Add validations
        try self.routes.put(path, handler);
    }

    pub const EndpointSearchResult = struct {
        handler: EndpointHandler,
        variables: std.StringHashMap([]const u8),
    };
    pub fn findRoute(self: *Self, path: []const u8) !?EndpointSearchResult {
        var pathIterator = std.mem.splitScalar(
            u8,
            path,
            '/',
        );
        var routerIterator = self.routes.keyIterator();

        var pathVariables = std
            .StringHashMap([]const u8)
            .init(self.allocator);

        while (routerIterator.next()) |routerPath| {
            pathIterator.reset();

            var routerPathIterator = std.mem.splitScalar(
                u8,
                routerPath.*,
                '/',
            );
            while (routerPathIterator.next()) |routerPathPart| {
                const pathPart = pathIterator.next();

                const comparisonResult = comparePathParts(
                    routerPathPart,
                    pathPart,
                );

                if (comparisonResult.variable != null) {
                    try pathVariables.put(
                        comparisonResult.variable.?.name,
                        comparisonResult.variable.?.value,
                    );
                    continue;
                } else if (comparisonResult.isEqual) {
                    continue;
                } else {
                    break;
                }
            } else {
                return .{
                    .handler = self.routes.get(routerPath.*).?,
                    .variables = pathVariables,
                };
            }
        }

        pathVariables.deinit();
        return null;
    }

    pub fn updateResponse(self: *Self, request: HttpRequest, response: *HttpResponse) !void {
        var routeMatch = try self.findRoute(request.path);

        if (routeMatch != null) {
            var data = EndpointData.init(
                request.allocator,
                routeMatch.?.variables,
            );
            defer data.deinit();

            const endpointResponse = routeMatch.?.handler(
                request,
                &data,
            );

            try response.prepare(
                data.httpStatus,
                endpointResponse,
                data.contentType,
            );
        } else {
            try response.prepare(
                httpEnums.HttpStatus.NotFound,
                null,
                null,
            );
        }
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
};
