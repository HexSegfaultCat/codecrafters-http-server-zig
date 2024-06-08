const httpUtils = @import("./http_utils.zig");

pub const StatusLine = struct {
    method: httpUtils.HttpMethod,
    path: []const u8,
    protocol: []const u8,
};
