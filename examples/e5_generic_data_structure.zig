const std = @import("std");
const builtin = @import("builtin");
const dbc = @import("dbc");

pub fn DynamicArray(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        len: usize,
        capacity: usize,
        allocator: std.mem.Allocator,

        fn invariant(self: Self) void {
            dbc.require(.{ self.len <= self.capacity, "Length cannot exceed capacity" });
            dbc.requireCtx(self.items.len == self.capacity, "self.items.len == self.capacity");
        }

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            dbc.require(.{ initial_capacity > 0, "Initial capacity must be positive" });

            const items = try allocator.alloc(T, initial_capacity);
            return Self{
                .items = items,
                .len = 0,
                .capacity = initial_capacity,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
            self.* = undefined;
        }

        pub fn append(self: *Self, item: T) !void {
            const old = .{ .len = self.len, .capacity = self.capacity, .item = item };

            return dbc.contract(self, old, struct {
                fn run(ctx: @TypeOf(old), s: *Self) !void {
                    // Resize if needed
                    if (s.len >= s.capacity) {
                        const new_capacity = s.capacity * 2;
                        const new_items = try s.allocator.realloc(s.items, new_capacity);
                        s.items = new_items;
                        s.capacity = new_capacity;
                    }

                    s.items[s.len] = ctx.item;
                    s.len += 1;

                    dbc.ensure(.{ s.len == ctx.len + 1, "Length should increment by 1" });
                    dbc.ensureCtx(s.len <= s.capacity, "s.len <= s.capacity");
                }
            }.run);
        }

        pub fn get(self: *Self, index: usize) T {
            const old = .{ .index = index };

            return dbc.contract(self, old, struct {
                fn run(ctx: @TypeOf(old), s: *Self) T {
                    dbc.require(.{ ctx.index < s.len, "Index out of bounds" });
                    return s.items[ctx.index];
                }
            }.run);
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;

            const old = .{ .len = self.len };
            return dbc.contract(self, old, struct {
                fn run(ctx: @TypeOf(old), s: *Self) T {
                    dbc.require(.{ s.len > 0, "Cannot pop from empty array" });

                    s.len -= 1;
                    const item = s.items[s.len];

                    dbc.ensure(.{ s.len == ctx.len - 1, "Length should decrement by 1" });
                    return item;
                }
            }.run);
        }
    };
}

// Validator examples
const PositiveValidator = struct {
    pub fn run(_: @This(), num: i32) bool {
        return num > 0;
    }
};

const RangeValidator = struct {
    min: i32,
    max: i32,

    pub fn run(self: @This(), value: i32) bool {
        return value >= self.min and value <= self.max;
    }
};

pub fn validateNumber(num: i32) i32 {
    const validator = PositiveValidator{};
    dbc.require(.{ validator, num, "Number must be positive" });

    const result = num * 2;
    const range_validator = RangeValidator{ .min = 2, .max = 200 };
    dbc.ensure(.{ range_validator, result, "Result must be in range [2, 200]" });

    return result;
}

pub fn main() !void {
    std.debug.print("Generic Data Structure Example (contracts active: {})\n", .{builtin.mode != .ReleaseFast});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var array = try DynamicArray(i32).init(gpa.allocator(), 2);
    defer array.deinit();

    try array.append(10);
    try array.append(20);
    try array.append(30); // This will trigger resize

    std.debug.print("Array length: {d}, capacity: {d}\n", .{ array.len, array.capacity });
    std.debug.print("Element at index 1: {d}\n", .{array.get(1)});

    if (array.pop()) |value| {
        std.debug.print("Popped value: {d}\n", .{value});
    }

    // Validator example
    const validated_result = validateNumber(42);
    std.debug.print("Validated and processed number: {d}\n", .{validated_result});
}
