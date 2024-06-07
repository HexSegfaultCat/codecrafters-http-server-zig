pub const HTTP_VERSION = "1.1";

const HttpStatusPair = struct {
    code: comptime_int,
    name: []const u8,
};

pub const HttpStatus = enum(comptime_int) {
    Ok = 200,

    pub fn statusName(status: HttpStatus) []const u8 {
        return switch (status) {
            HttpStatus.Ok => "OK",
        };
    }
};
