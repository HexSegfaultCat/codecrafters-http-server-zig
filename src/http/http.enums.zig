const std = @import("std");

pub const HttpStatus = enum(u16) {
    Ok = 200,
    NotFound = 404,

    pub fn statusName(status: HttpStatus) []const u8 {
        return switch (status) {
            HttpStatus.Ok => "OK",
            HttpStatus.NotFound => "Not Found",
        };
    }
};

const MethodError = error{
    MissingHttpMethod,
    MalformedHttpMethod,
};
pub const HttpMethod = enum {
    Get,
    Post,

    pub fn fromString(status: ?[]const u8) MethodError!HttpMethod {
        if (status == null) {
            return MethodError.MissingHttpMethod;
        }

        var upperCaseStatus: [10]u8 = undefined;
        _ = std.ascii.upperString(
            &upperCaseStatus,
            status.?,
        );

        if (std.mem.eql(u8, upperCaseStatus[0..3], "GET")) {
            return HttpMethod.Get;
        } else if (std.mem.eql(u8, upperCaseStatus[0..4], "POST")) {
            return HttpMethod.Post;
        } else {
            return MethodError.MalformedHttpMethod;
        }
    }
};
