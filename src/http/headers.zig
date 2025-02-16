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

headersList: std.ArrayList(HeaderItem),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .headersList = std.ArrayList(HeaderItem).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.headersList.items) |*item| {
        item.deinit();
    }
    self.headersList.deinit();

    self.* = undefined;
}

pub fn get(self: *Self, key: []const u8) ?HeaderItem {
    for (self.headersList.items) |header| {
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
        try self.headersList.append(item);
    }
}
