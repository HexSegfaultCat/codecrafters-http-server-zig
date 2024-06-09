const std = @import("std");

const httpConsts = @import("./consts.zig");
const httpEnums = @import("./enums.zig");
const httpUtils = @import("./utils.zig");

pub const HttpRequest = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    method: httpEnums.HttpMethod,
    path: []const u8,
    protocol: []const u8,
    headers: std.StringHashMap([]const u8),

    body: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,

            .method = undefined,
            .path = undefined,
            .protocol = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator),

            .body = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var headerValueIterator = self.headers.iterator();
        while (headerValueIterator.next()) |headerEntry| {
            self.allocator.free(headerEntry.key_ptr.*);
            self.allocator.free(headerEntry.value_ptr.*);
        }
        self.headers.deinit();
        if (self.body != null) {
            self.allocator.free(self.body.?);
        }
    }
};

pub fn readStreamData(allocator: std.mem.Allocator, stream: std.net.Stream) !std.ArrayList(u8) {
    var outputData = std.ArrayList(u8).init(allocator);

    const buffer = try allocator.alloc(u8, httpConsts.BUFFER_SIZE);
    defer allocator.free(buffer);
    @memset(buffer, 0);

    var fds =
        [_]std.posix.pollfd{.{
        .fd = stream.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    while (stream.read(buffer)) |bytesRead| {
        try outputData.appendSlice(buffer[0..bytesRead]);

        // INFO: Handle edgecase where socket waits for data if `bytesRead == buffer.len`
        const dataAvailable = try std.posix.poll(&fds, 0);
        if (bytesRead < buffer.len or dataAvailable == 0) {
            break;
        }
    } else |err| {
        return err;
    }

    return outputData;
}

const ParseRequestError = error{
    MissingEndOfHeaderSection,
    MalformedHeader,
};
pub fn parseUpdateRequest(rawRequestData: std.ArrayList(u8), request: *HttpRequest) !void {
    var requestIterator = std.mem.splitSequence(
        u8,
        rawRequestData.items,
        "\r\n",
    );
    requestIterator.reset();

    var statusLine = std.mem.splitScalar(
        u8,
        requestIterator.first(),
        ' ',
    );
    request.method = try httpEnums.HttpMethod.fromString(statusLine.next());
    request.path = try httpUtils.validatedPath(statusLine.next());
    request.protocol = try httpUtils.validatedProtocol(statusLine.next());

    while (requestIterator.next()) |headerLine| {
        // INFO: Empty line ends headers section
        if (headerLine.len == 0) {
            break;
        }

        const separatorIndex = std.mem.indexOf(u8, headerLine, ":") orelse {
            return ParseRequestError.MalformedHeader;
        };

        const headerName = try std.ascii.allocUpperString(
            request.allocator,
            headerLine[0..separatorIndex],
        );
        const headerValue = try request.allocator.dupe(
            u8,
            std.mem.trimLeft(
                u8,
                headerLine[(separatorIndex + 1)..],
                " ",
            ),
        );

        try request.headers.put(headerName, headerValue);
    } else {
        return ParseRequestError.MissingEndOfHeaderSection;
    }
}
