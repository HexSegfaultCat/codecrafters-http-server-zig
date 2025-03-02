const std = @import("std");

const HeaderBufferSize = 1024;
const DataBufferSize = 4096;
const ReceiveTimeoutMiliseconds = 5_000;
const SendTimeoutMiliseconds = 5_000;

const Self = @This();

const HttpRoute = @import("utils/route.zig");
const HttpRouter = @import("router.zig");
const HttpRequest = @import("request.zig");
const HttpResponse = @import("response.zig");

pub const Config = struct {
    ipAddress: []const u8,
    port: u16 = 0,

    maxThreadsCount: u16 = 10,
};

pub const HttpClientError = error{
    Timeout,
    MissingStatusLine,
};

allocator: std.mem.Allocator,

address: std.net.Address = undefined,
server: std.net.Server = undefined,
threadPool: std.Thread.Pool = undefined,

router: HttpRouter,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .router = HttpRouter.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.router.deinit();
    self.threadPool.deinit();

    self.* = undefined;
}

pub fn configure(self: *Self, config: Config) !void {
    self.address = try std.net.Address.resolveIp(config.ipAddress, config.port);
    try self.threadPool.init(.{
        .allocator = self.allocator,
        .n_jobs = config.maxThreadsCount,
    });
}

pub fn run(self: *Self) !void {
    self.server = try self.address.listen(.{
        .reuse_address = true,
    });
    defer self.server.deinit();

    std.log.info("Server is listening on {any}", .{self.server.listen_address});

    const socketSendTimeout = std.posix.timeval{
        .tv_sec = SendTimeoutMiliseconds / 1000,
        .tv_usec = (SendTimeoutMiliseconds % 1000) * 1000,
    };

    while (self.server.accept()) |connection| {
        std.log.info("Client from {any} accepted", .{connection.address});

        try std.posix.setsockopt(
            connection.stream.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.SNDTIMEO,
            &std.mem.toBytes(socketSendTimeout),
        );

        try self.threadPool.spawn(threadClientHandler, .{ self, connection });
    } else |err| {
        return err;
    }
}

fn threadClientHandler(server: *Self, connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    handleConnection(server, connection) catch |err| {
        std.log.err(
            "[{any}] Unexpected error while handling connection: {any}",
            .{ connection.address, err },
        );
    };
}

fn handleConnection(self: *Self, connection: std.net.Server.Connection) !void {
    var request = try self.readAndParseRequest(connection);

    std.log.info("[{any}] < {s}: {s}", .{
        connection.address,
        @tagName(request.method),
        request.uri.url,
    });
    std.log.debug("[REQUEST]\n{s}\n[/REQUEST]", .{request.body.items});

    const matchedRoute = try self.router.matchEndpointHandlerAndUpdateRouteParams(
        request.method,
        &request.uri,
    );
    const response = try self.handleRequest(request, matchedRoute);

    std.log.info("[{any}] > {d}: {s}", .{
        connection.address,
        @intFromEnum(response.statusCode),
        response.statusCode.name(),
    });
    std.log.debug("[RESPONSE]\n{s}\n[/RESPONSE]", .{response.body.items});

    try sendResponse(connection, response);
}

fn handleRequest(self: *Self, request: HttpRequest, matchedRoute: ?HttpRoute) !HttpResponse {
    if (matchedRoute) |route| {
        var response = route.handler(request) catch |err| {
            std.log.err(
                "Unexpected error {s} occurred while handling endpoint: {any}",
                .{ @errorName(err), err },
            );

            var serverErrorResponse = HttpResponse.init(self.allocator);
            try serverErrorResponse.body.appendSlice(@errorName(err));
            serverErrorResponse.statusCode = .ServerError;

            return serverErrorResponse;
        };

        const bodySize = try std.fmt.allocPrint(
            self.allocator,
            "{d}",
            .{response.body.items.len},
        );
        defer self.allocator.free(bodySize);

        try response.headers.addOrUpdate("Content-Type", "text/plain");
        try response.headers.addOrUpdate("Content-Length", bodySize);

        return response;
    } else {
        var notFoundResponse = HttpResponse.init(self.allocator);
        notFoundResponse.statusCode = .NotFound;

        return notFoundResponse;
    }
}

fn readAndParseRequest(self: *Self, connection: std.net.Server.Connection) !HttpRequest {
    var request = HttpRequest.init(self.allocator);

    var receivedData = std.ArrayList(u8).init(self.allocator);
    defer receivedData.deinit();

    const statusAndHeaderLength = try readStatusAndHeaderWithPartialBody(
        connection,
        &receivedData,
    );

    var statusEndIndex: usize = 0;
    if (std.mem.indexOf(u8, receivedData.items, "\r\n")) |endIndex| {
        try request.parseStatusLine(receivedData.items[0..endIndex]);
        statusEndIndex = endIndex;
    } else {
        return HttpClientError.MissingStatusLine;
    }

    if (statusEndIndex != statusAndHeaderLength) {
        const headersStartIndex = statusEndIndex + 2;
        try request.parseHeaders(
            receivedData.items[headersStartIndex..statusAndHeaderLength],
        );
    }

    const expectedDataLength = if (request.headers.get("Content-Length")) |header|
        try std.fmt.parseInt(usize, header.value, 10)
    else
        0;

    const dataStartIndex = statusAndHeaderLength + 4;
    const partialDataLength = receivedData.items.len - dataStartIndex;

    try request.body.appendSlice(receivedData.items[dataStartIndex..]);

    if (expectedDataLength > partialDataLength) {
        const bytesToFetch = expectedDataLength - partialDataLength;
        try readRemainingBodyData(
            connection,
            bytesToFetch,
            &request.body,
        );
    }

    return request;
}

fn readStatusAndHeaderWithPartialBody(
    connection: std.net.Server.Connection,
    receivedData: *std.ArrayList(u8),
) !usize {
    var buffer: [HeaderBufferSize]u8 = undefined;
    var pollFd = [_]std.posix.pollfd{.{
        .fd = connection.stream.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    while (std.posix.poll(&pollFd, ReceiveTimeoutMiliseconds)) |dataAvailable| {
        if (dataAvailable == 0) {
            std.log.warn("Did not receive header's end delimiter", .{});
            return HttpClientError.Timeout;
        }

        const fetchedBytesCount = try connection.stream.read(buffer[0..]);
        try receivedData.appendSlice(buffer[0..fetchedBytesCount]);

        if (std.mem.indexOf(u8, receivedData.items, "\r\n\r\n")) |headerEndingAt| {
            return headerEndingAt;
        }
    } else |err| {
        return err;
    }
}

fn readRemainingBodyData(
    connection: std.net.Server.Connection,
    bytesToFetchCount: usize,
    requestBodyData: *std.ArrayList(u8),
) !void {
    var buffer: [DataBufferSize]u8 = undefined;
    var pollFd = [_]std.posix.pollfd{.{
        .fd = connection.stream.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    var fetchedBytes: usize = 0;
    while (std.posix.poll(&pollFd, ReceiveTimeoutMiliseconds)) |dataAvailable| {
        if (dataAvailable == 0) {
            std.log.warn(
                "Did not receive any bytes in time. Got {d} bytes, but expected {d}",
                .{ bytesToFetchCount, fetchedBytes },
            );
            return HttpClientError.Timeout;
        }

        const fetchedBytesCount = try connection.stream.read(
            if (bytesToFetchCount >= buffer.len)
                buffer[0..]
            else
                buffer[0..(bytesToFetchCount - fetchedBytes)],
        );
        try requestBodyData.appendSlice(buffer[0..fetchedBytesCount]);

        fetchedBytes += fetchedBytesCount;
        if (fetchedBytes >= bytesToFetchCount) {
            break;
        }
    } else |err| {
        return err;
    }
}

fn sendResponse(connection: std.net.Server.Connection, response: HttpResponse) !void {
    const writer = connection.stream.writer();

    try std.fmt.format(
        writer,
        "{s}/{s} {d} {s}\r\n",
        .{
            "HTTP",
            response.version,
            @intFromEnum(response.statusCode),
            response.statusCode.name(),
        },
    );

    for (response.headers.headers.items) |header| {
        try std.fmt.format(
            writer,
            "{s}: {s}\r\n",
            .{ header.name, header.value },
        );
    }

    try writer.writeAll("\r\n");
    try writer.writeAll(response.body.items);
}
