const std = @import("std");

pub const HeaderItem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    value: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        value: []const u8,
    ) !HeaderItem.Self {
        return .{
            .allocator = allocator,

            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, value),
        };
    }

    pub fn deinit(self: *HeaderItem.Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.value);

        self.* = undefined;
    }

    pub fn updateValue(self: *HeaderItem.Self, value: []const u8) !void {
        self.allocator.free(self.value);
        self.value = try self.allocator.dupe(u8, value);
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
        try item.updateValue(value);
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
