const std = @import("std");
const dbc = @import("dbc");

pub fn BoundedQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        // An invariant is a condition that must hold true before and after every method call.
        // This invariant checks that the queue's state is valid.
        fn invariant(self: Self) void {
            dbc.require(self.count <= capacity, "Queue count exceeds capacity");
        }

        pub fn enqueue(self: *Self, item: T) void {
            // The `old` struct captures the state of the object before the method runs.
            const old = .{ .count = self.count, .item = item };
            return dbc.contract(self, old, struct {
                // Preconditions are checked at the start of a function.
                fn run(ctx: @TypeOf(old), s: *Self) void {
                    dbc.require(s.count < capacity, "Cannot enqueue to a full queue");

                    // Core method logic
                    s.items[s.tail] = ctx.item;
                    s.tail = (s.tail + 1) % capacity;
                    s.count += 1;

                    // Postconditions are checked at the end of a function.
                    dbc.ensure(s.count == ctx.count + 1, "Enqueue failed to increment count");
                }
            }.run);
        }

        pub fn dequeue(self: *Self) T {
            const old = .{ .count = self.count };
            return dbc.contract(self, old, struct {
                fn run(ctx: @TypeOf(old), s: *Self) T {
                    dbc.require(s.count > 0, "Cannot dequeue from an empty queue");

                    const dequeued_item = s.items[s.head];
                    s.head = (s.head + 1) % capacity;
                    s.count -= 1;

                    dbc.ensure(s.count == ctx.count - 1, "Dequeue failed to decrement count");
                    return dequeued_item;
                }
            }.run);
        }
    };
}

pub fn main() !void {
    const builtin = @import("builtin");
    const MyQueue = BoundedQueue(u32, 3);
    var q = MyQueue{};

    std.debug.print("Contracts are active in this build mode: {}\n", .{builtin.mode != .ReleaseFast});

    q.enqueue(10);
    q.enqueue(20);
    std.debug.print("Dequeued: {}\n", .{q.dequeue()});
    std.debug.print("Dequeued: {}\n", .{q.dequeue()});
}
