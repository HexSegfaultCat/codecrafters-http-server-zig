const std = @import("std");

const _debug = @import("./_debug.zig");

const httpConsts = @import("./consts.zig");
const httpEnums = @import("./enums.zig");

const HttpRequest = @import("./request.zig").HttpRequest;
const HttpResponse = @import("./response.zig").HttpResponse;

const HttpRouter = @import("./router.zig").HttpRouter;

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

    pub fn setupServer(
        self: *Self,
        ipAddress: []const u8,
        port: u16,
    ) !void {
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
                clientHandler,
                .{ self, connection },
            );
            try self.clientThreads.append(thread);
        } else |err| {
            return err;
        }
    }

    pub fn clientHandler(self: *Self, connection: std.net.Server.Connection) !void {
        var request = HttpRequest.init(self.allocator);
        defer request.deinit();

        const rawRequestData = try request.readStreamData(
            connection.stream,
        );
        defer rawRequestData.deinit();

        try request.parseUpdateRequest(
            rawRequestData,
        );

        var responseStruct = HttpResponse.init(self.allocator);
        defer responseStruct.deinit();

        try self.router.updateResponse(request, &responseStruct);
        try self.sendResponse(responseStruct, connection.stream);

        // _debug.printRawRequest(rawRequestData);
        _debug.printParsedRequest(request);
        _debug.printParsedResponse(responseStruct);

        connection.stream.close();
    }

    pub fn sendResponse(self: *Self, response: HttpResponse, stream: std.net.Stream) !void {
        _ = self;

        const statusResponse = try std.fmt.allocPrint(
            response.allocator,
            "HTTP/{s} {d} {s}\r\n",
            .{
                response.protocolVersion,
                @intFromEnum(response.statusCode),
                httpEnums.HttpStatus.statusName(response.statusCode),
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

        // INFO: Ends header section
        try stream.writeAll("\r\n");

        if (response.body != null) {
            try stream.writeAll(response.body.?);
        }
    }
};
