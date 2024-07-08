const std = @import("std");

pub const CompressionScheme = enum {
    None,
    Gzip,

    pub fn fromString(compressionName: ?[]const u8) CompressionScheme {
        if (compressionName == null) {
            return .None;
        }

        if (std.mem.eql(u8, compressionName.?, "gzip")) {
            return .Gzip;
        } else {
            return .None;
        }
    }

    pub fn toString(scheme: CompressionScheme) []const u8 {
        return switch (scheme) {
            .Gzip => "gzip",
            else => "",
        };
    }
};
