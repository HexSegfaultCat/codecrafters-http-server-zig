const std = @import("std");
const net = std.net;

const DIRECTORY_ARG = "directory";

const HttpHeaders = @import("./http/headers.zig");

const HttpServer = @import("./http/server.zig");

const HttpRequest = @import("./http/request.zig");
const HttpResponse = @import("./http/response.zig");

const EndpointResponse = HttpResponse.EndpointResponse;
const ResponseAllocator = HttpResponse.ResponseAllocator;

var argParams: std.StringHashMap([]const u8) = undefined;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    argParams = std.StringHashMap([]const u8).init(allocator);
    defer argParams.deinit();

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--") == false) {
            continue;
        }

        const name = arg[2..];
        const value = args.next();

        if (value == null) {
            std.process.exit(1);
        }
        try argParams.put(name, value.?);
    }

    var server = HttpServer.init(allocator, stdout);
    defer server.deinit();

    try server.setupServer("127.0.0.1", 4221);

    try server.router.registerRoute(.Get, "/", homePageEndpoint);
    try server.router.registerRoute(.Get, "/index.html", homePageEndpoint);
    try server.router.registerRoute(.Get, "/echo/{echoStr}", echoPageEndpoint);
    try server.router.registerRoute(.Get, "/user-agent", userAgentEndpoint);
    try server.router.registerRoute(.Get, "/files/{filename}", serveFileEndpoint);
    try server.router.registerRoute(.Post, "/files/{filename}", updateFileEndpoint);

    try server.runServer();
}

fn homePageEndpoint(request: HttpRequest, builder: *ResponseAllocator) EndpointResponse {
    _ = request;
    _ = builder;

    return .{
        .body = null,
    };
}

fn echoPageEndpoint(request: HttpRequest, builder: *ResponseAllocator) EndpointResponse {
    _ = builder;

    return .{
        .body = request.pathVariables.get("echoStr"),
    };
}

fn userAgentEndpoint(request: HttpRequest, builder: *ResponseAllocator) EndpointResponse {
    _ = builder;

    const userAgent =
        request.headers.getHeaderEntry(HttpHeaders.HEADER_USER_AGENT) catch null;

    if (userAgent) |entry| {
        return .{ .body = entry.rawHeaderValue };
    } else {
        return .{ .body = "No user agent provided by client" };
    }
}

fn serveFileEndpoint(request: HttpRequest, builder: *ResponseAllocator) EndpointResponse {
    const genericBasePath = argParams.get(DIRECTORY_ARG) orelse "./";
    const absoluteBasePath = std.fs.cwd().realpathAlloc(
        builder.allocator,
        genericBasePath,
    ) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error while getting the full path",
        };
    };
    const filename = request.pathVariables.get("filename").?;

    const fullFilePath = std.fs.path.join(
        builder.allocator,
        &[_][]const u8{ absoluteBasePath, filename },
    ) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error",
        };
    };
    builder.deferMemoryToFree(fullFilePath);

    if (std.mem.startsWith(u8, fullFilePath, absoluteBasePath) == false) {
        return .{
            .statusCode = .Unauthorized,
            .body = "Unauthorized to access directory above the base",
        };
    }

    const file = std.fs.cwd().openFile(fullFilePath, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => .{ .statusCode = .NotFound },
            else => .{ .statusCode = .ServerError },
        };
    };
    const fileData = file.readToEndAlloc(
        builder.allocator,
        10 * 1024 * 1024,
    ) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error when reading the file",
        };
    };
    builder.deferMemoryToFree(fileData);

    return .{
        .contentType = "application/octet-stream",
        .body = fileData,
    };
}

fn updateFileEndpoint(request: HttpRequest, builder: *ResponseAllocator) EndpointResponse {
    const genericBasePath = argParams.get(DIRECTORY_ARG) orelse "./";
    const absoluteBasePath = std.fs.cwd().realpathAlloc(
        builder.allocator,
        genericBasePath,
    ) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error",
        };
    };
    const filename = request.pathVariables.get("filename").?;

    const fullFilePath = std.fs.path.join(
        builder.allocator,
        &[_][]const u8{ absoluteBasePath, filename },
    ) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error",
        };
    };
    builder.deferMemoryToFree(fullFilePath);

    if (request.body == null) {
        return .{ .statusCode = .NotFound };
    }

    const file = std.fs.cwd().createFile(fullFilePath, .{}) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error",
        };
    };
    defer file.close();

    file.writeAll(request.body.?) catch {
        return .{
            .statusCode = .ServerError,
            .body = "Error",
        };
    };

    return .{
        .statusCode = .Created,
    };
}

test {
    std.testing.refAllDecls(@This());
}
