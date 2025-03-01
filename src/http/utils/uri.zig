const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,

raw: []const u8,

url: []const u8 = undefined,
pathParams: std.StringHashMap([]const u8),
queryParams: std.StringHashMap([]const u8),

pub fn init(allocator: std.mem.Allocator, uri: []const u8) !Self {
    var self = Self{
        .allocator = allocator,

        .raw = try allocator.dupe(u8, uri),

        .pathParams = std.StringHashMap([]const u8).init(allocator),
        .queryParams = std.StringHashMap([]const u8).init(allocator),
    };

    if (std.mem.indexOfScalar(u8, self.raw, '?')) |separatorIndex| {
        self.url = self.raw[0..separatorIndex];
        if (self.raw.len > separatorIndex + 1) {
            try self.extractQueryParams(uri[(separatorIndex + 1)..]);
        }
    } else {
        self.url = self.raw;
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.raw);

    self.pathParams.deinit();
    self.queryParams.deinit();

    self.* = undefined;
}

fn extractQueryParams(self: *Self, params: []const u8) !void {
    var paramsIt = std.mem.splitScalar(u8, params, '&');
    while (paramsIt.next()) |param| {
        if (std.mem.indexOfScalar(u8, param, '=')) |paramSeparator| {
            const key = param[0..paramSeparator];
            const value = if (param.len > paramSeparator + 1)
                param[(paramSeparator + 1)..]
            else
                "";

            try self.queryParams.put(key, value);
        }
    }
}

// pub fn addPathParam(self: *Self) !void {
//     //
// }

test "parse url with path only" {
    const allocator = std.testing.allocator;

    const expectedUrl = "/some/path/example";

    var uri = try Self.init(allocator, expectedUrl);
    defer uri.deinit();

    try std.testing.expectEqualStrings(expectedUrl, uri.url);
}

test "parse url with path and separator without query params" {
    const allocator = std.testing.allocator;

    const expectedUrl = "/some/path/example";

    const fullRawUri = expectedUrl ++ "?";

    var uri = try Self.init(allocator, fullRawUri);
    defer uri.deinit();

    try std.testing.expectEqualStrings(expectedUrl, uri.url);
    try std.testing.expectEqual(0, uri.queryParams.count());
}

test "parse url with path and proper single query param" {
    const allocator = std.testing.allocator;

    const expectedUrl = "/some/path/example";

    const expectedParamKey = "someName";
    const expectedParamValue = "someValue";

    const fullRawUri =
        expectedUrl ++ "?" ++ expectedParamKey ++ "=" ++ expectedParamValue;

    var uri = try Self.init(allocator, fullRawUri);
    defer uri.deinit();

    try std.testing.expectEqualStrings(expectedUrl, uri.url);

    try std.testing.expectEqual(1, uri.queryParams.count());
    try std.testing.expectEqualStrings(expectedParamValue, uri.queryParams.get(expectedParamKey).?);
}

test "parse url with path and proper multiple query param" {
    const allocator = std.testing.allocator;

    const expectedUrl = "/some/path/example";

    const expectedParamKey1 = "someName";
    const expectedParamValue1 = "someValue";

    const expectedParamKey2 = "someOtherKey";
    const expectedParamValue2 = "someOtherValue";

    const rawParam1 = expectedParamKey1 ++ "=" ++ expectedParamValue1;
    const rawParam2 = expectedParamKey2 ++ "=" ++ expectedParamValue2;

    const fullRawUri = expectedUrl ++ "?" ++ rawParam1 ++ "&" ++ rawParam2;

    var uri = try Self.init(allocator, fullRawUri);
    defer uri.deinit();

    try std.testing.expectEqualStrings(expectedUrl, uri.url);

    try std.testing.expectEqual(2, uri.queryParams.count());
    try std.testing.expectEqualStrings(expectedParamValue1, uri.queryParams.get(expectedParamKey1).?);
    try std.testing.expectEqualStrings(expectedParamValue2, uri.queryParams.get(expectedParamKey2).?);
}

test "parse url with path and multiple params with missing value for the first param" {
    const allocator = std.testing.allocator;

    const expectedUrl = "/some/path/example";

    const expectedParamKey1 = "someName";
    const expectedParamValue1 = "";

    const expectedParamKey2 = "someOtherKey";
    const expectedParamValue2 = "someOtherValue";

    const rawParam1 = expectedParamKey1 ++ "=" ++ expectedParamValue1;
    const rawParam2 = expectedParamKey2 ++ "=" ++ expectedParamValue2;

    const fullRawUri = expectedUrl ++ "?" ++ rawParam1 ++ "&" ++ rawParam2;

    var uri = try Self.init(allocator, fullRawUri);
    defer uri.deinit();

    try std.testing.expectEqualStrings(expectedUrl, uri.url);

    try std.testing.expectEqual(2, uri.queryParams.count());
    try std.testing.expectEqualStrings(expectedParamValue1, uri.queryParams.get(expectedParamKey1).?);
    try std.testing.expectEqualStrings(expectedParamValue2, uri.queryParams.get(expectedParamKey2).?);
}
