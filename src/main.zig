const std = @import("std");
const net = std.net;

const HttpServer = @import("http/server.zig");
const HttpRequest = @import("http/request.zig");
const HttpResponse = @import("http/response.zig");

const DirectoryArg = "directory";

var args: std.StringHashMap([]const u8) = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    args = std.StringHashMap([]const u8).init(allocator);
    defer args.deinit();

    var argsIt = std.process.args();
    while (argsIt.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--") == false) {
            continue;
        }

        const name = arg[2..];
        const value = argsIt.next();

        if (value == null) {
            std.process.exit(1);
        }
        try args.put(name, value.?);
    }

    var server = HttpServer.init(allocator);
    defer server.deinit();

    try server.configure(.{
        .ipAddress = "127.0.0.1",
        .port = 4221,

        .maxThreadsCount = 10,
    });

    try server.router.registerRoute(.Get, "/", homePageEndpoint);
    try server.router.registerRoute(.Get, "/index.html", homePageEndpoint);
    try server.router.registerRoute(.Get, "/echo/{str}", echoPageEndpoint);
    try server.router.registerRoute(.Get, "/user-agent", userAgentEndpoint);
    try server.router.registerRoute(.Get, "/files/{filename}", getFileEndpoint);

    try server.run();
}

fn homePageEndpoint(request: HttpRequest) !HttpResponse {
    return try HttpResponse.initPlain(request.allocator, .Ok, "");
}

fn echoPageEndpoint(request: HttpRequest) !HttpResponse {
    const echoValue = request.uri.pathParams.getEntry("str").?.value_ptr.*;
    return try HttpResponse.initPlain(request.allocator, .Ok, echoValue);
}

fn userAgentEndpoint(request: HttpRequest) !HttpResponse {
    return if (request.headers.get("User-Agent")) |userAgent|
        try HttpResponse.initPlain(request.allocator, .Ok, userAgent.value)
    else
        try HttpResponse.initPlain(
            request.allocator,
            .NotFound,
            "Missing user agent in request",
        );
}

fn getFileEndpoint(request: HttpRequest) !HttpResponse {
    const absoluteBasePath = try std.fs.cwd().realpathAlloc(
        request.allocator,
        args.get(DirectoryArg) orelse "./",
    );
    defer request.allocator.free(absoluteBasePath);

    const fileAbsolutePath = try std.fs.path.join(
        request.allocator,
        &[_][]const u8{
            absoluteBasePath,
            request.uri.pathParams.get("filename").?,
        },
    );
    defer request.allocator.free(fileAbsolutePath);

    if (std.mem.startsWith(u8, fileAbsolutePath, absoluteBasePath) == false) {
        return try HttpResponse.initPlain(
            request.allocator,
            .Unauthorized,
            "Unauthorized to access directory above the base",
        );
    }

    const file = std.fs.cwd().openFile(fileAbsolutePath, .{}) catch |err| switch (err) {
        error.FileNotFound => return try HttpResponse.initPlain(
            request.allocator,
            .NotFound,
            "File does not exist",
        ),
        else => return err,
    };
    return try HttpResponse.initAsFileStream(request.allocator, file);
}

test {
    std.testing.refAllDecls(@This());
}
