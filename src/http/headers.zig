const std = @import("std");

pub const HeaderItem = struct {
    allocator: std.mem.Allocator,

    name: []const u8,
    value: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        value: []const u8,
    ) !HeaderItem {
        return .{
            .allocator = allocator,

            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, value),
        };
    }

    pub fn deinit(self: *HeaderItem) void {
        self.allocator.free(self.name);
        self.allocator.free(self.value);

        self.* = undefined;
    }

    pub fn updateValueRealloc(self: *HeaderItem, value: []const u8) !void {
        self.allocator.free(self.value);
        self.value = try self.allocator.dupe(u8, value);
    }

    pub fn separatedValuesAlloc(self: HeaderItem) !std.ArrayList([]const u8) {
        var values = std.ArrayList([]const u8).init(self.allocator);

        var valuesIt = std.mem.splitScalar(u8, self.value, ',');
        while (valuesIt.next()) |value| {
            const firstNonSpaceIndex = std.mem.indexOfNone(u8, value, " ") orelse 0;
            try values.append(value[firstNonSpaceIndex..]);
        }

        return values;
    }
};

const Self = @This();

allocator: std.mem.Allocator,

headers: std.ArrayList(HeaderItem),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .headers = std.ArrayList(HeaderItem).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.headers.items) |*item| {
        item.deinit();
    }
    self.headers.deinit();

    self.* = undefined;
}

pub fn get(self: Self, key: []const u8) ?HeaderItem {
    for (self.headers.items) |header| {
        if (std.ascii.eqlIgnoreCase(key, header.name)) {
            return header;
        }
    }

    return null;
}

pub fn addOrUpdate(self: *Self, name: []const u8, value: []const u8) !void {
    var existingEntry = self.get(name);
    if (existingEntry) |*item| {
        try item.updateValueRealloc(value);
    } else {
        const item = try HeaderItem.init(self.allocator, name, value);
        try self.headers.append(item);
    }
}

test "add and retrieve header with the same casing" {
    const allocator = std.testing.allocator;

    var headers = Self.init(allocator);
    defer headers.deinit();

    const expectedHeaderName = "Content-Length";
    const expectedHeaderValue = "100";

    try headers.addOrUpdate(expectedHeaderName, expectedHeaderValue);

    const contentLength = headers.get(expectedHeaderName).?;

    try std.testing.expectEqualStrings(expectedHeaderName, contentLength.name);
    try std.testing.expectEqualStrings(expectedHeaderValue, contentLength.value);
}

test "add and retrieve header with different casing" {
    const allocator = std.testing.allocator;

    var headers = Self.init(allocator);
    defer headers.deinit();

    const expectedHeaderName = "CoNtEnT-LeNgTh";
    const expectedHeaderValue = "100";

    try headers.addOrUpdate(expectedHeaderName, expectedHeaderValue);

    const lowerHeaderName = try std.ascii.allocLowerString(
        allocator,
        expectedHeaderName,
    );
    defer allocator.free(lowerHeaderName);

    const contentLength = headers.get(lowerHeaderName).?;

    try std.testing.expectEqualStrings(expectedHeaderName, contentLength.name);
    try std.testing.expectEqualStrings(expectedHeaderValue, contentLength.value);
}

test "add and retrieve multi value header" {
    const allocator = std.testing.allocator;

    var headers = Self.init(allocator);
    defer headers.deinit();

    const expectedValue1 = "abc";
    const expectedValue2 = "def";
    const expectedValue3 = "foo";

    const headerName = "Some-Header";
    const fullValue = std.fmt.comptimePrint("   {s},  {s},{s}", .{
        expectedValue1,
        expectedValue2,
        expectedValue3,
    });
    try headers.addOrUpdate(headerName, fullValue);

    const values = try headers.get(headerName).?.separatedValuesAlloc();
    defer values.deinit();

    try std.testing.expectEqual(3, values.items.len);
    try std.testing.expectEqualStrings(expectedValue1, values.items[0]);
    try std.testing.expectEqualStrings(expectedValue2, values.items[1]);
    try std.testing.expectEqualStrings(expectedValue3, values.items[2]);
}
