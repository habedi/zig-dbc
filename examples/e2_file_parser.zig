const std = @import("std");
const dbc = @import("dbc");

const Allocator = std.mem.Allocator;

const FileParser = struct {
    const Self = @This();
    allocator: Allocator,
    lines: std.ArrayList([]const u8),
    file_path: ?[]const u8,
    is_parsed: bool,

    // The invariant checks that if the parser is in a 'parsed' state,
    // a file path must exist. This helps maintain data integrity.
    fn invariant(self: Self) void {
        if (self.is_parsed) {
            dbc.require(.{ self.file_path != null, "Parsed file must have a path" });
        }
    }

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .file_path = null,
            .is_parsed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    pub fn reset(self: *Self) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearAndFree();
        if (self.file_path) |path| {
            self.allocator.free(path);
            self.file_path = null;
        }
        self.is_parsed = false;
    }

    pub fn parseFile(self: *Self, path: []const u8) !void {
        const old = .{ .old_lines_count = self.lines.items.len, .path = path };

        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Self) !void {
                // A precondition to ensure the parser is not already in a parsed state.
                // This prevents re-parsing without calling `reset`.
                dbc.require(.{ !s.is_parsed, "Parser is already in a parsed state. Call reset first." });

                const file = try std.fs.cwd().openFile(ctx.path, .{});
                defer file.close();

                var buffered_reader = std.io.bufferedReader(file.reader());
                var line_reader = buffered_reader.reader();

                while (try line_reader.readUntilDelimiterOrEofAlloc(s.allocator, '\n', 4096)) |line| {
                    try s.lines.append(line);
                }

                if (s.file_path) |old_path| s.allocator.free(old_path);
                s.file_path = try s.allocator.dupe(u8, ctx.path);

                s.is_parsed = true;

                // A postcondition to verify that new lines were read successfully.
                dbc.ensure(.{ s.lines.items.len > ctx.old_lines_count, "Parsing failed to read any new lines." });
            }
        }.run);
    }
};

pub fn main() !void {
    const builtin = @import("builtin");
    std.debug.print("Contracts are active in this build mode: {}\n", .{builtin.mode != .ReleaseFast});

    const temp_dir_path = "temp";

    std.fs.cwd().makeDir(temp_dir_path) catch |err| if (err != error.PathAlreadyExists) return err;

    var temp_dir = try std.fs.cwd().openDir(temp_dir_path, .{});
    defer temp_dir.close();

    const temp_file_name = "test.txt";
    const temp_file = try temp_dir.createFile(temp_file_name, .{});
    defer temp_file.close();

    try temp_file.writeAll(
        \\line 1
        \\line 2
        \\line 3
        \\
    );

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var parser = FileParser.init(gpa.allocator());
    defer parser.deinit();

    const file_path_in_temp = try std.fmt.allocPrint(gpa.allocator(), "{s}/{s}", .{ temp_dir_path, temp_file_name });
    defer gpa.allocator().free(file_path_in_temp);

    parser.parseFile(file_path_in_temp) catch |err| {
        std.debug.print("Parse error: {s}\n", .{@errorName(err)});
    };

    std.debug.print("Successfully parsed file with {} lines.\n", .{parser.lines.items.len});

    if (builtin.mode != .ReleaseFast) {
        std.debug.print("Attempting to re-parse file (will panic in debug modes).\n", .{});
        parser.reset();
        parser.parseFile(file_path_in_temp) catch |err| {
            std.debug.print("Parse error on retry: {s}\n", .{@errorName(err)});
        };
        std.debug.print("Successfully re-parsed file with {} lines.\n", .{parser.lines.items.len});
    }
}
