const std = @import("std");

const _debug = @import("./_debug.zig");

const httpConsts = @import("./consts.zig");

const HttpRouter = @import("./router.zig").HttpRouter;

const HttpRequest = @import("./request.zig").HttpRequest;
const HttpResponse = @import("./response.zig").HttpResponse;

const HttpStatus = HttpResponse.HttpStatus;
const EndpointHandler = HttpRouter.EndpointHandler;

const ResponseBuilder = @import("./response.zig").ResponseBuilder;
const EndpointResponse = @import("./response.zig").EndpointResponse;

pub const HttpServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    writerStream: std.fs.File.Writer,

    address: std.net.Address,
    listener: std.net.Server,

    router: HttpRouter,

    clientThreads: std.ArrayList(std.Thread),

    pub fn init(allocator: std.mem.Allocator, writerStream: std.fs.File.Writer) Self {
        return .{
            .allocator = allocator,
            .writerStream = writerStream,

            .address = undefined,
            .listener = undefined,

            .router = HttpRouter.init(allocator),

            .clientThreads = std.ArrayList(std.Thread).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.listener.deinit();
        self.router.deinit();
        self.clientThreads.deinit();
        self.* = undefined;
    }

    pub fn setupServer(self: *Self, ipAddress: []const u8, port: u16) !void {
        self.address = try std.net.Address.resolveIp(ipAddress, port);
    }

    pub fn runServer(self: *Self) !void {
        self.listener = try self.address.listen(.{
            .reuse_address = true,
        });

        try self.writerStream.print(
            "Listening on {any} for connections...\n",
            .{self.address},
        );

        while (self.listener.accept()) |connection| {
            try self.writerStream.print(
                "Accepted new connection from {any}\n",
                .{connection.address},
            );

            const thread = try std.Thread.spawn(
                .{},
                clientThreadHandler,
                .{ self, connection },
            );
            try self.clientThreads.append(thread);
        } else |err| {
            return err;
        }
    }

    fn clientThreadHandler(self: *Self, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        const rawRequestData = try self.readRequestData(connection.stream);
        defer rawRequestData.deinit();

        var request = HttpRequest.init(self.allocator);
        defer request.deinit();

        try request.parseUpdateRequest(rawRequestData);
        const routeMatch = try self.router.findRouteHandlerAndUpdateVariablesMap(
            request.method,
            request.path,
            &request.pathVariables,
        );

        var response = HttpResponse.init(self.allocator);
        defer response.deinit();

        try self.writerStream.print("[{any}] {s} {s}\n", .{
            connection.address,
            @tagName(request.method),
            request.path,
        });

        if (routeMatch) |routeHandler| {
            var responseBuilder = ResponseBuilder.init(request.allocator, &response.headers);
            defer responseBuilder.deinit();

            const endpointResponse = routeHandler(request, &responseBuilder);
            try response.updateResponse(responseBuilder, endpointResponse);
        } else {
            try response.updateResponse(null, .{ .statusCode = HttpStatus.NotFound });
        }

        try sendResponse(response, connection.stream);

        _debug.printParsedRequest(request);
        _debug.printParsedResponse(response);
    }

    fn readRequestData(self: *Self, stream: std.net.Stream) !std.ArrayList(u8) {
        var outputData = std.ArrayList(u8).init(self.allocator);

        const buffer = try self.allocator.alloc(u8, httpConsts.BUFFER_SIZE);
        defer self.allocator.free(buffer);

        var fds = [_]std.posix.pollfd{.{
            .fd = stream.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        while (stream.read(buffer)) |bytesRead| {
            try outputData.appendSlice(buffer[0..bytesRead]);

            const dataAvailable = try std.posix.poll(&fds, 0);
            if (bytesRead < buffer.len or dataAvailable == 0) {
                break;
            }
        } else |err| {
            return err;
        }

        return outputData;
    }

    fn sendResponse(response: HttpResponse, stream: std.net.Stream) !void {
        const statusResponse = try std.fmt.allocPrint(
            response.allocator,
            "{s}/{s} {d} {s}\r\n",
            .{
                httpConsts.HTTP_PROTOCOL,
                response.protocolVersion,
                @intFromEnum(response.statusCode),
                HttpStatus.statusName(response.statusCode),
            },
        );
        defer response.allocator.free(statusResponse);

        try stream.writeAll(statusResponse);

        var headersIterator = response.headers.iterator();
        while (headersIterator.next()) |headerEntry| {
            const headerResponse = try std.fmt.allocPrint(
                response.allocator,
                "{s}: {s}\r\n",
                .{ headerEntry.key_ptr.*, headerEntry.value_ptr.* },
            );
            defer response.allocator.free(headerResponse);

            try stream.writeAll(headerResponse);
        }

        try stream.writeAll("\r\n");

        if (response.body) |body| {
            try stream.writeAll(body);
        }
    }
};
