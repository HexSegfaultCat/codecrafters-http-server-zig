const std = @import("std");
const net = std.net;

const DIRECTORY_ARG = "directory";

const httpConsts = @import("./http/consts.zig");
const httpEnums = @import("./http/enums.zig");

const HttpRequest = @import("./http/request.zig").HttpRequest;
const HttpServer = @import("./http/server.zig").HttpServer;

const EndpointData = @import("./http/router.zig").HttpRouter.EndpointData;

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
    try server.setupServer("127.0.0.1", 4221);

    try server.router.registerRoute("/", homePageEndpoint);
    try server.router.registerRoute("/index.html", homePageEndpoint);
    try server.router.registerRoute("/echo/{echoStr}", echoPageEndpoint);
    try server.router.registerRoute("/user-agent", userAgentEndpoint);
    try server.router.registerRoute("/files/{filename}", serveFileEndpoint);

    try server.runServer();
}

fn homePageEndpoint(request: HttpRequest, data: *EndpointData) ?[]const u8 {
    _ = request;
    _ = data;

    return null;
}

fn echoPageEndpoint(request: HttpRequest, data: *EndpointData) ?[]const u8 {
    _ = request;

    return data.pathVariables.get("echoStr");
}

fn userAgentEndpoint(request: HttpRequest, data: *EndpointData) ?[]const u8 {
    _ = data;

    const userAgentHeaderUpper = std.ascii.allocUpperString(
        request.allocator,
        httpConsts.HEADER_USER_AGENT,
    ) catch {
        return "Server error";
    };
    defer request.allocator.free(userAgentHeaderUpper);

    return request.headers.get(userAgentHeaderUpper);
}

fn serveFileEndpoint(request: HttpRequest, data: *EndpointData) ?[]const u8 {
    _ = request;

    const genericBasePath = argParams.get(DIRECTORY_ARG) orelse "./";
    const absoluteBasePath = std.fs.cwd().realpathAlloc(
        data.allocator,
        genericBasePath,
    ) catch {
        return "Error while getting the full path";
    };
    const filename = data.pathVariables.get("filename").?;

    const fullFilePath = std.fs.path.join(
        data.allocator,
        &[_][]const u8{ absoluteBasePath, filename },
    ) catch {
        return "Error";
    };
    data.deferMemoryToFree(fullFilePath);

    if (std.mem.startsWith(u8, fullFilePath, absoluteBasePath) == false) {
        data.httpStatus = httpEnums.HttpStatus.NotFound;
        return "Unauthorized to access directory above the base";
    }

    const file = std.fs.cwd().openFile(fullFilePath, .{}) catch {
        data.httpStatus = httpEnums.HttpStatus.NotFound;
        return "Error when opening the file";
    };
    const fileData = file.readToEndAlloc(
        data.allocator,
        10 * 1024 * 1024,
    ) catch {
        data.httpStatus = httpEnums.HttpStatus.NotFound;
        return "Error when reading the file";
    };
    data.deferMemoryToFree(fileData);

    data.contentType = "application/octet-stream";
    return fileData;
}
