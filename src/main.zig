const std = @import("std");
const net = std.net;

const HttpServer = @import("http/server.zig");
const HttpRequest = @import("http/request.zig");
const HttpResponse = @import("http/response.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = HttpServer.init(allocator);
    defer server.deinit();

    try server.configure(.{ .ipAddress = "127.0.0.1", .port = 4221 });

    try server.router.registerRoute(.Get, "/", homePageEndpoint);
    try server.router.registerRoute(.Get, "/index.html", homePageEndpoint);
    try server.router.registerRoute(.Get, "/echo/{str}", echoPageEndpoint);
    try server.router.registerRoute(.Get, "/user-agent", userAgentEndpoint);

    try server.run();
}

fn homePageEndpoint(request: HttpRequest) !HttpResponse {
    var response = HttpResponse.init(request.allocator);
    errdefer response.deinit();

    response.statusCode = .Ok;

    return response;
}

fn echoPageEndpoint(request: HttpRequest) !HttpResponse {
    var response = HttpResponse.init(request.allocator);
    errdefer response.deinit();

    try response.body.appendSlice(request.uri.pathParams.getEntry("str").?.value_ptr.*);
    response.statusCode = .Ok;

    return response;
}

fn userAgentEndpoint(request: HttpRequest) !HttpResponse {
    var response = HttpResponse.init(request.allocator);
    errdefer response.deinit();

    if (request.headers.get("User-Agent")) |userAgent| {
        try response.body.appendSlice(userAgent.value);
    } else {
        response.statusCode = .NotFound;
    }

    return response;
}

test {
    std.testing.refAllDecls(@This());
}
