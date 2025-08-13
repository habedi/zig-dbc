const std = @import("std");
const builtin = @import("builtin");
const dbc = @import("dbc");

const Allocator = std.mem.Allocator;

const Node = struct {
    data: u32,
    next: ?*Node,
};

const SinglyLinkedList = struct {
    const Self = @This();
    allocator: Allocator,
    head: ?*Node,
    count: usize,

    // The invariant checks that the manually maintained `count`
    // matches the actual number of nodes in the linked list.
    fn invariant(self: Self) void {
        var actual_count: usize = 0;
        var current = self.head;
        // This loop iterates through all nodes, counting them.
        while (current) |node| {
            actual_count += 1;
            current = node.next;
        }
        dbc.require(.{ self.count == actual_count, "List count is inconsistent with node count." });
    }

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .head = null,
            .count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        var current = self.head;
        while (current) |node| {
            const next = node.next;
            self.allocator.destroy(node);
            current = next;
        }
        self.head = null;
        self.count = 0;
    }

    pub fn push_front(self: *Self, value: u32) !void {
        const old = .{ .count = self.count, .value = value };
        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Self) !void {
                const new_node = try s.allocator.create(Node);
                new_node.data = ctx.value;
                new_node.next = s.head;
                s.head = new_node;
                s.count += 1;

                // The postcondition verifies that the count was correctly incremented.
                dbc.ensure(.{ s.count == ctx.count + 1, "Push_front failed to decrement count." });
            }
        }.run);
    }

    pub fn pop_front(self: *Self) ?u32 {
        if (self.head == null) return null;

        const old = .{ .count = self.count };
        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Self) u32 {
                dbc.require(.{ s.head != null, "Cannot pop from an empty list." });

                const head_node = s.head.?;
                const value = head_node.data;
                s.head = head_node.next;
                s.allocator.destroy(head_node);
                s.count -= 1;

                // The postcondition verifies that the count was correctly decremented.
                dbc.ensure(.{ s.count == ctx.count - 1, "Pop_front failed to decrement count." });

                return value;
            }
        }.run);
    }
};

pub fn main() !void {
    std.debug.print("Contracts are active in this build mode: {}\n", .{builtin.mode != .ReleaseFast});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var list = SinglyLinkedList.init(gpa.allocator());
    defer list.deinit();

    try list.push_front(10);
    try list.push_front(20);
    try list.push_front(30);

    std.debug.print("List size: {d}\n", .{list.count});

    if (list.pop_front()) |value| {
        std.debug.print("Popped value: {d}\n", .{value});
    }

    if (list.pop_front()) |value| {
        std.debug.print("Popped value: {d}\n", .{value});
    }

    std.debug.print("List size: {d}\n", .{list.count});
}
