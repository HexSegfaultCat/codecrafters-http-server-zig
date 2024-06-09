const std = @import("std");
const net = std.net;

const httpConsts = @import("./http/http.consts.zig");
const httpEnums = @import("./http/http.enums.zig");
const httpStructs = @import("./http/http.structs.zig");
const httpUtils = @import("./http/http.utils.zig");

pub fn main() !void {
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
        try stdout.print("Accepted new connection\n", .{});

        const allocator = std.heap.page_allocator;

        const requestData = try httpUtils.readStreamData(
            allocator,
            connection.stream,
        );
        defer requestData.deinit();

        // TODO: Remove this debbuing print
        std.debug.print("[REQUEST] Received {d} bytes\n---\n{s}\n---\n", .{
            requestData.items.len,
            requestData.items,
        });

        const requestStruct = try httpUtils.parseRequest(requestData);

        var responseStruct = httpStructs.HttpResponse.init(allocator);
        defer responseStruct.deinit();

        try routerUpdateResponse(requestStruct, &responseStruct);
        try httpUtils.sendResponse(responseStruct, connection.stream);

        connection.stream.close();
    } else |err| {
        return err;
    }
}

fn routerUpdateResponse(request: httpStructs.HttpRequestStatusLine, response: *httpStructs.HttpResponse) !void {
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
    } else {
        try response.prepare(
            httpEnums.HttpStatus.NotFound,
            null,
            null,
        );
    }
}
