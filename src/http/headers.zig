const std = @import("std");

pub const HEADER_CONTENT_TYPE = "Content-Type";
pub const HEADER_CONTENT_LENGTH = "Content-Length";
pub const HEADER_USER_AGENT = "User-Agent";
pub const HEADER_ACCEPT_ENCODING = "Accept-Encoding";
pub const HEADER_CONTENT_ENCODING = "Content-Encoding";

pub const HeaderEntry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    headerValues: [][]const u8,
    rawHeaderValue: []const u8,

    pub fn init(allocator: std.mem.Allocator) HeaderEntry.Self {
        return .{
            .allocator = allocator,

            .headerValues = &[0][]const u8{},
            .rawHeaderValue = "",
        };
    }

    pub fn deinit(self: *HeaderEntry.Self) void {
        for (self.headerValues) |value| {
            self.allocator.free(value);
        }
        self.allocator.free(self.headerValues);
        self.allocator.free(self.rawHeaderValue);

        self.* = undefined;
    }

    pub fn append(self: *HeaderEntry.Self, value: []const u8) !void {
        var newHeaderValues = try self.allocator.alloc(
            []const u8,
            self.headerValues.len + 1,
        );
        @memcpy(newHeaderValues[0..self.headerValues.len], self.headerValues);
        newHeaderValues[self.headerValues.len] = try self.allocator.dupe(u8, value);

        self.allocator.free(self.headerValues);
        self.headerValues = newHeaderValues;

        const newRawValue = try std.mem.join(
            self.allocator,
            ",",
            self.headerValues,
        );
        self.allocator.free(self.rawHeaderValue);
        self.rawHeaderValue = newRawValue;
    }
};

const Self = @This();

allocator: std.mem.Allocator,

headersMap: std.StringHashMap(HeaderEntry),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .headersMap = std.StringHashMap(HeaderEntry).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var headerEntryIterator = self.headersMap.iterator();
    while (headerEntryIterator.next()) |headerEntry| {
        self.allocator.free(headerEntry.key_ptr.*);
        headerEntry.value_ptr.*.deinit();
    }
    self.headersMap.deinit();

    self.* = undefined;
}

pub fn addOrReplaceValue(self: *Self, headerName: []const u8, headerValue: []const u8) !void {
    const normalizedHeaderName = try allocNormalizedHeaderName(
        self.allocator,
        headerName,
    );

    const mapEntry = self.headersMap.getEntry(normalizedHeaderName);
    if (mapEntry) |existingEntry| {
        self.allocator.free(existingEntry.key_ptr.*);
        existingEntry.value_ptr.*.deinit();

        _ = self.headersMap.removeByPtr(existingEntry.key_ptr);
    }

    var headerValueEntry = HeaderEntry.init(self.allocator);

    var headerValueIterator = std.mem.splitScalar(u8, headerValue, ',');
    while (headerValueIterator.next()) |headerValuePart| {
        try headerValueEntry.append(headerValuePart);
    }

    try self.headersMap.put(normalizedHeaderName, headerValueEntry);
}

pub fn addOrAppendValue(self: *Self, headerName: []const u8, headerValue: []const u8) !void {
    const normalizedHeaderName = try allocNormalizedHeaderName(
        self.allocator,
        headerName,
    );
    defer self.allocator.free(normalizedHeaderName);

    var headerValueIterator = std.mem.splitScalar(u8, headerValue, ',');

    var mapValue = self.headersMap.get(normalizedHeaderName);
    if (mapValue) |*existingMapValue| {
        while (headerValueIterator.next()) |headerValuePart| {
            const partCopy = try self.allocator.dupe(u8, headerValuePart);
            try existingMapValue.append(partCopy);
        }
    } else {
        var headerValueEntry = HeaderEntry.init(self.allocator);

        while (headerValueIterator.next()) |headerValuePart| {
            const partCopy = try self.allocator.dupe(u8, headerValuePart);
            try headerValueEntry.append(partCopy);
        }

        const headerNameCopy = try self.allocator.dupe(u8, normalizedHeaderName);
        try self.headersMap.put(headerNameCopy, headerValueEntry);
    }
}

pub fn getHeaderEntry(self: Self, headerName: []const u8) !?HeaderEntry {
    const normalizedHeaderName = try allocNormalizedHeaderName(
        self.allocator,
        headerName,
    );
    defer self.allocator.free(normalizedHeaderName);

    return self.headersMap.get(normalizedHeaderName);
}

pub fn getAcceptedCompression(self: Self) ?[][]const u8 {
    return if (self.headersMap.get(HEADER_ACCEPT_ENCODING)) |entry|
        entry.headerValues
    else
        null;
}

fn allocNormalizedHeaderName(
    allocator: std.mem.Allocator,
    headerName: []const u8,
) ![]const u8 {
    var normalizedHeaderName = try std.ascii.allocLowerString(
        allocator,
        headerName,
    );

    var nameIterator = std.mem.splitScalar(u8, normalizedHeaderName, '-');
    while (nameIterator.next()) |_| {
        const partFirstCharIndex = if (nameIterator.index == null)
            @as(usize, 0)
        else
            nameIterator.index.?;

        normalizedHeaderName[partFirstCharIndex] = std.ascii.toUpper(
            normalizedHeaderName[partFirstCharIndex],
        );
    }

    return normalizedHeaderName;
}

test "add normalized and get with lowercase" {
    // Setup
    var headers = Self.init(std.testing.allocator);
    defer headers.deinit();

    const headerNameNormalized = "Content-Type";
    const headerNameLowercase = "content-type";

    const headerValue = "application/json";

    try headers.addOrReplaceValue(headerNameNormalized, headerValue);

    // Verify
    const entry = try headers.getHeaderEntry(headerNameLowercase);

    try std.testing.expect(entry != null);
    try std.testing.expectEqual(1, entry.?.headerValues.len);
    try std.testing.expectEqualStrings(headerValue, entry.?.headerValues[0]);
    try std.testing.expectEqualStrings(headerValue, entry.?.rawHeaderValue);
}

test "add lowercase and get with uppercase" {
    // Setup
    var headers = Self.init(std.testing.allocator);
    defer headers.deinit();

    const headerNameUppercase = "CONTENT-TYPE";
    const headerNameLowercase = "content-type";

    const headerValue = "application/json";

    try headers.addOrReplaceValue(headerNameLowercase, headerValue);

    // Verify
    const entry = try headers.getHeaderEntry(headerNameUppercase);

    try std.testing.expect(entry != null);
    try std.testing.expectEqual(1, entry.?.headerValues.len);
    try std.testing.expectEqualStrings(headerValue, entry.?.headerValues[0]);
    try std.testing.expectEqualStrings(headerValue, entry.?.rawHeaderValue);
}

test "add same header with different casing and get with uppercase" {
    // Setup
    var headers = Self.init(std.testing.allocator);
    defer headers.deinit();

    const headerNameUppercase = "CONTENT-TYPE";
    const headerNameNormalized = "Content-Type";
    const headerNameLowercase = "content-type";

    const headerValue = "application/json";

    try headers.addOrReplaceValue(headerNameUppercase, headerValue);
    try headers.addOrReplaceValue(headerNameNormalized, headerValue);
    try headers.addOrReplaceValue(headerNameLowercase, headerValue);

    // Verify
    const entry = try headers.getHeaderEntry(headerNameUppercase);

    try std.testing.expect(entry != null);
    try std.testing.expectEqual(1, entry.?.headerValues.len);
    try std.testing.expectEqualStrings(headerValue, entry.?.headerValues[0]);
    try std.testing.expectEqualStrings(headerValue, entry.?.rawHeaderValue);
}
