const std = @import("std");
const net = std.net;

const _debug = @import("./http/_debug.zig");

const httpConsts = @import("./http/consts.zig");
const httpEnums = @import("./http/enums.zig");
const httpUtils = @import("./http/utils.zig");

const httpRequest = @import("./http/request.zig");
const HttpRequest = httpRequest.HttpRequest;

const httpResponse = @import("./http/response.zig");
const HttpResponse = httpResponse.HttpResponse;

var clientsThreadPool: std.ArrayList(std.Thread) = undefined;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    clientsThreadPool = std.ArrayList(std.Thread).init(allocator);
    defer clientsThreadPool.deinit();

    try createHttpServer("127.0.0.1", 4221);
}

pub fn createHttpServer(ipAddress: []const u8, port: u16) !void {
    const stdout = std.io.getStdOut().writer();
    const address = try net.Address.resolveIp(ipAddress, port);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    try stdout.print(
        "Listening on {s}:{d} for connections...\n",
        .{ ipAddress, port },
    );

    while (listener.accept()) |connection| {
        try stdout.print(
            "Accepted new connection from {any}\n",
            .{connection.address},
        );

        const thread = try std.Thread.spawn(
            .{},
            clientHandler,
            .{connection},
        );
        try clientsThreadPool.append(thread);
    } else |err| {
        return err;
    }
}

fn clientHandler(connection: std.net.Server.Connection) !void {
    const allocator = std.heap.page_allocator;

    const rawRequestData = try httpRequest.readStreamData(
        allocator,
        connection.stream,
    );
    defer rawRequestData.deinit();

    var requestStruct = HttpRequest.init(allocator);
    defer requestStruct.deinit();

    try httpRequest.parseUpdateRequest(
        rawRequestData,
        &requestStruct,
    );

    var responseStruct = HttpResponse.init(allocator);
    defer responseStruct.deinit();

    try routerUpdateResponse(requestStruct, &responseStruct);
    try httpResponse.sendResponse(responseStruct, connection.stream);

    // _debug.printRawRequest(rawRequestData);
    _debug.printParsedRequest(requestStruct);
    _debug.printParsedResponse(responseStruct);

    connection.stream.close();
}

fn routerUpdateResponse(request: HttpRequest, response: *HttpResponse) !void {
    if (std.mem.eql(u8, request.path, "/") or
        std.mem.eql(u8, request.path, "/index.html"))
    {
        try response.prepare(
            httpEnums.HttpStatus.Ok,
            null,
            null,
        );
    } else if (std.mem.startsWith(u8, request.path, "/echo/")) {
        const prefixLength = "/echo/".len;
        try response.prepare(
            httpEnums.HttpStatus.Ok,
            request.path[prefixLength..],
            "text/plain",
        );
    } else if (std.mem.eql(u8, request.path, "/user-agent")) {
        const userAgentHeaderUpper = try std.ascii.allocUpperString(
            request.allocator,
            httpConsts.HEADER_USER_AGENT,
        );
        defer request.allocator.free(userAgentHeaderUpper);

        try response.prepare(
            httpEnums.HttpStatus.Ok,
            request.headers.get(userAgentHeaderUpper),
            "text/plain",
        );
    } else {
        try response.prepare(
            httpEnums.HttpStatus.NotFound,
            null,
            null,
        );
    }
}
