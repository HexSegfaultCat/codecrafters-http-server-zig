const std = @import("std");

const HttpRequest = @import("./request.zig").HttpRequest;
const HttpResponse = @import("./response.zig").HttpResponse;

pub fn printRawRequest(rawRequest: std.ArrayList(u8)) void {
    std.debug.print("[RAW REQUEST] Received {d} bytes\n", .{
        rawRequest.items.len,
    });
    std.debug.print("---START---\n{s}\n---END---\n", .{
        rawRequest.items,
    });
    std.debug.print("[/RAW REQUEST]\n", .{});
}

pub fn printParsedRequest(request: HttpRequest) void {
    std.debug.print("[PARSED REQUEST]\n---START-STATUS---\nMethod={any}\nPath={s}\nProtocol={s}\n---END-STATUS---\n", .{
        request.method,
        request.path,
        request.protocol,
    });

    std.debug.print("---START-HEADERS---\n", .{});
    var tmpIterator = request.headers.iterator();
    while (tmpIterator.next()) |entry| {
        std.debug.print("Name={s}; Value={s}\n", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
        });
    }
    std.debug.print("---END-HEADERS---\n", .{});

    std.debug.print("---START-BODY---\n{?s}\n---END-BODY---\n", .{
        request.body,
    });
    std.debug.print("[/PARSED REQUEST]\n", .{});
}

pub fn printParsedResponse(response: HttpResponse) void {
    std.debug.print("[PARSED RESPONSE]\n---START-STATUS---\nStatus={any}\nProtocol={s}\n---END-STATUS---\n", .{
        response.statusCode,
        response.protocolVersion,
    });

    std.debug.print("---START-HEADERS---\n", .{});
    var tmpIterator = response.headers.iterator();
    while (tmpIterator.next()) |entry| {
        std.debug.print("Name={s}; Value={s}\n", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
        });
    }
    std.debug.print("---END-HEADERS---\n", .{});

    std.debug.print("---START-BODY---\n{?s}\n---END-BODY---\n", .{
        response.body,
    });
    std.debug.print("[/PARSED RESPONSE]\n", .{});
}
