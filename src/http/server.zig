const std = @import("std");

const HeaderBufferSize = 1024;
const DataBufferSize = 4096;
const ReceiveTimeoutMiliseconds = 5_000;

const Self = @This();
const HttpRequest = @import("request.zig");

pub const Config = struct {
    ipAddress: []const u8,
    port: u16,
};

pub const HttpClientError = error{
    Timeout,
    MissingStatusLine,
};

allocator: std.mem.Allocator,

address: std.net.Address = undefined,
server: std.net.Server = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    self.* = undefined;
}

pub fn configure(self: *Self, config: Config) !void {
    self.address = try std.net.Address.resolveIp(config.ipAddress, config.port);
}

pub fn run(self: *Self) !void {
    self.server = try self.address.listen(.{
        .reuse_address = true,
    });
    defer self.server.deinit();

    std.log.info("Server is listening on {any}", .{self.server.listen_address});

    while (self.server.accept()) |connection| {
        std.log.info("Client from {any} accepted", .{connection.address});
        defer connection.stream.close();

        try self.handleConnection(connection);
    } else |err| {
        return err;
    }
}

fn handleConnection(self: *Self, connection: std.net.Server.Connection) !void {
    var receivedData = std.ArrayList(u8).init(self.allocator);
    defer receivedData.deinit();

    const statusAndHeaderLength = try fetchStatusAndHeaderWithPartialBody(
        connection,
        &receivedData,
    );
    const dataStartIndex = statusAndHeaderLength + 4;

    var request = HttpRequest.init(self.allocator);
    defer request.deinit();

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

    const partialDataLength = receivedData.items.len - dataStartIndex;
    const expectedDataLength = if (request.headers.get("Content-Length")) |header|
        try std.fmt.parseInt(usize, header.value, 10)
    else
        0;

    if (expectedDataLength > partialDataLength) {
        const bytesToFetch = expectedDataLength - partialDataLength;
        try fetchRemainingData(
            connection,
            &receivedData,
            bytesToFetch,
        );
    }

    if (std.mem.eql(u8, request.url, "/") or
        std.mem.eql(u8, request.url, "/index.html"))
    {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

fn fetchStatusAndHeaderWithPartialBody(
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

fn fetchRemainingData(
    connection: std.net.Server.Connection,
    receivedData: *std.ArrayList(u8),
    bytesToFetchCount: usize,
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
                buffer[0..bytesToFetchCount],
        );
        try receivedData.appendSlice(buffer[0..fetchedBytesCount]);

        fetchedBytes += fetchedBytesCount;
        if (fetchedBytes >= bytesToFetchCount) {
            break;
        }
    } else |err| {
        return err;
    }
}
