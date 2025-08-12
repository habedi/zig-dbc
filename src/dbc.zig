//! ## Zig-DbC -- A Design by Contract Library for Zig
//!
//! This module provides a set of functions to use design by contract (DbC) principles in Zig programs.
//!
//! ### Features
//!
//! - Preconditions: Assert conditions that must be true when entering a function (at call time)
//! - Postconditions: Assert conditions that must be true when exiting a function (at return time)
//! - Invariants: Assert structural consistency of objects before and after method calls
//! - Zero-cost abstractions: All contract checks are compiled out in `ReleaseFast` mode
//! - Error tolerance: Optional mode to preserve partial state changes when errors occur
//! - Formatted messages: Compile-time formatted assertion messages with automatic context capture
//!
//! ### Usage
//!
//! #### Basic Assertions
//!
//! ```zig
//! const dbc = @import("dbc.zig");
//!
//! fn divide(a: f32, b: f32) f32 {
//!     dbc.require(.{b != 0.0, "Division by zero"});
//!     const result = a / b;
//!     dbc.ensure(.{!std.math.isNan(result), "Result must be a valid number"});
//!     return result;
//! }
//! ```
//!
//! #### Formatted Assertions
//!
//! ```zig
//! fn sqrt(x: f64) f64 {
//!     dbc.requiref(x >= 0.0, "Square root requires non-negative input, got {d}", .{x});
//!     const result = std.math.sqrt(x);
//!     dbc.ensuref(!std.math.isNan(result), "Expected valid result, got {d}", .{result});
//!     return result;
//! }
//! ```
//!
//! #### Contract-based Methods
//!
//! ```zig
//! const BankAccount = struct {
//!     balance: u64,
//!     is_open: bool,
//!
//!     // Invariant - checked before and after each contract
//!     fn invariant(self: BankAccount) void {
//!         dbc.require(.{ if (!self.is_open) self.balance == 0 else true,
//!                         "Closed accounts must have zero balance" });
//!     }
//!
//!     pub fn withdraw(self: *BankAccount, amount: u64) !void {
//!         const old_state = .{ .balance = self.balance };
//!         return dbc.contract(self, old_state, struct {
//!             fn run(ctx: @TypeOf(old_state), account: *BankAccount) !void {
//!                 // Enhanced preconditions with context
//!                 dbc.requiref(account.is_open, "Account must be open", .{});
//!                 dbc.requiref(amount <= account.balance,
//!                               "Insufficient funds: requested {d}, available {d}",
//!                               .{amount, account.balance});
//!
//!                 // Business logic
//!                 account.balance -= amount;
//!
//!                 // Enhanced postconditions
//!                 dbc.ensuref(account.balance == ctx.balance - amount,
//!                             "Balance mismatch: expected {d}, got {d}",
//!                             .{ctx.balance - amount, account.balance});
//!             }
//!         }.run);
//!     }
//! };
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Assert a precondition that must be true at function entry.
///
/// Can be called in two ways:
/// 1. With a boolean condition: `require(.{condition, "error message"})`
/// 2. With a reusable validator: `require(.{validator, value, "error message"})`
///
/// A validator can be a function pointer or a struct with a public `run` method that
/// accepts `value` and returns a boolean.
///
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// Panics with the provided message if the condition is false or the validator returns false.
pub inline fn require(args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    comptime {
        const info = @typeInfo(@TypeOf(args));
        if (info != .@"struct" or info.@"struct".is_tuple == false) {
            @compileError("arguments to require must be a tuple, like require(.{condition, msg})");
        }
    }

    const condition = blk: {
        if (args.len == 2) {
            if (@TypeOf(args[0]) != bool) @compileError("Expected a boolean condition for 2-argument require");
            break :blk args[0];
        } else if (args.len == 3) {
            const validator = args[0];
            const value = args[1];
            const ValidatorType = @TypeOf(validator);

            switch (@typeInfo(ValidatorType)) {
                .@"fn" => break :blk validator(value),
                .@"struct" => {
                    if (@hasDecl(ValidatorType, "run")) {
                        break :blk validator.run(value);
                    } else {
                        @compileError("Validator struct must have a public 'run' method");
                    }
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"fn") {
                        break :blk validator(value);
                    } else {
                        @compileError("Validator must be a function or a struct with a public 'run' method");
                    }
                },
                else => @compileError("Validator must be a function or a struct with a public 'run' method"),
            }
        } else {
            @compileError("require expects a tuple with 2 or 3 arguments");
        }
    };

    const msg = comptime blk: {
        if (args.len == 2) {
            break :blk args[1];
        } else {
            break :blk args[2];
        }
    };

    if (!condition) @panic(msg);
}

/// Assert a precondition with formatted message support.
///
/// Provides compile-time formatted messages for better debugging experience.
/// All formatting is done at compile-time and completely eliminated in ReleaseFast.
pub inline fn requiref(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = comptime std.fmt.comptimePrint(fmt, args);
        @panic(msg);
    }
}

/// Assert a precondition with contextual information captured in the message.
///
/// Automatically includes a context string in the panic message.
/// Pass a comptime string (typically a literal) to avoid allocations.
pub inline fn requireCtx(condition: bool, comptime context: []const u8) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint("Precondition failed: {s}", .{context});
        @panic(msg);
    }
}

/// Assert a postcondition that must be true at function exit.
///
/// Can be called in two ways:
/// 1. With a boolean condition: `ensure(.{condition, "error message"})`
/// 2. With a reusable validator: `ensure(.{validator, value, "error message"})`
///
/// A validator can be a function pointer or a struct with a public `run` method that
/// accepts `value` and returns a boolean.
///
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// Panics with the provided message if the condition is false or the validator returns false.
pub inline fn ensure(args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    comptime {
        const info = @typeInfo(@TypeOf(args));
        if (info != .@"struct" or info.@"struct".is_tuple == false) {
            @compileError("arguments to ensure must be a tuple, like ensure(.{condition, msg})");
        }
    }

    const condition = blk: {
        if (args.len == 2) {
            if (@TypeOf(args[0]) != bool) @compileError("Expected a boolean condition for 2-argument ensure");
            break :blk args[0];
        } else if (args.len == 3) {
            const validator = args[0];
            const value = args[1];
            const ValidatorType = @TypeOf(validator);

            switch (@typeInfo(ValidatorType)) {
                .@"fn" => break :blk validator(value),
                .@"struct" => {
                    if (@hasDecl(ValidatorType, "run")) {
                        break :blk validator.run(value);
                    } else {
                        @compileError("Validator struct must have a public 'run' method");
                    }
                },
                .pointer => |ptr_info| {
                    if (@typeInfo(ptr_info.child) == .@"fn") {
                        break :blk validator(value);
                    } else {
                        @compileError("Validator must be a function or a struct with a public 'run' method");
                    }
                },
                else => @compileError("Validator must be a function or a struct with a public 'run' method"),
            }
        } else {
            @compileError("ensure expects a tuple with 2 or 3 arguments");
        }
    };

    const msg = comptime blk: {
        if (args.len == 2) {
            break :blk args[1];
        } else {
            break :blk args[2];
        }
    };

    if (!condition) @panic(msg);
}

/// Assert a postcondition with formatted message support.
///
/// Provides compile-time formatted messages for better debugging experience.
/// All formatting is done at compile-time and completely eliminated in ReleaseFast.
pub inline fn ensuref(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = comptime std.fmt.comptimePrint(fmt, args);
        @panic(msg);
    }
}

/// Assert a postcondition with contextual information captured in the message.
///
/// Automatically includes a context string in the panic message.
/// Pass a comptime string (typically a literal) to avoid allocations.
pub inline fn ensureCtx(condition: bool, comptime context: []const u8) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint("Postcondition failed: {s}", .{context});
        @panic(msg);
    }
}

/// Execute a function with design by contract semantics.
///
/// This function provides:
/// - Automatic invariant checking (if the object has an `invariant` method)
/// - Captured pre-state for postconditions
/// - Error handling that preserves invariants
///
/// Parameters:
/// - `self`: Object instance (must be a pointer type for mutation)
/// - `old_state`: Captured state before the operation
/// - `operation`: Function to execute with signature `fn(old_state, self) ReturnType`
pub inline fn contract(self: anytype, old_state: anytype, operation: anytype) @typeInfo(@TypeOf(operation)).@"fn".return_type.? {
    if (builtin.mode == .ReleaseFast) {
        return operation(old_state, self);
    }

    // Check pre-invariant if available
    if (@hasDecl(@TypeOf(self.*), "invariant")) {
        self.invariant();
    }

    // Execute the operation
    const result = operation(old_state, self);

    // Check post-invariant if available
    if (@hasDecl(@TypeOf(self.*), "invariant")) {
        self.invariant();
    }

    return result;
}

/// Execute a function with design by contract semantics and error tolerance.
///
/// Similar to `contract` but if an error occurs during the operation, the invariant
/// is still checked to guarantee the object remains in a valid state.
///
/// Parameters:
/// - `self`: Object instance (must be a pointer type for mutation)
/// - `old_state`: Captured state before the operation
/// - `operation`: Function to execute with signature `fn(old_state, self) ReturnType`
pub inline fn contractWithErrorTolerance(self: anytype, old_state: anytype, operation: anytype) @typeInfo(@TypeOf(operation)).@"fn".return_type.? {
    if (builtin.mode == .ReleaseFast) {
        return operation(old_state, self);
    }

    // Check pre-invariant if available
    if (@hasDecl(@TypeOf(self.*), "invariant")) {
        self.invariant();
    }

    // Execute the operation with error handling
    const result = operation(old_state, self) catch |err| {
        // Even on error, ensure invariant is maintained
        if (@hasDecl(@TypeOf(self.*), "invariant")) {
            self.invariant();
        }
        return err;
    };

    // Check post-invariant if available
    if (@hasDecl(@TypeOf(self.*), "invariant")) {
        self.invariant();
    }

    return result;
}

// Tests for `dbc` module

const testing = std.testing;

/// Example implementation demonstrating DbC principles with formatted messages.
/// This Account struct showcases preconditions, postconditions, and invariants.
const Account = struct {
    balance: u32,
    is_active: bool,

    /// Invariant: inactive accounts must have zero balance.
    /// This is automatically checked before and after each contracted method.
    fn invariant(self: Account) void {
        if (!self.is_active) {
            requiref(self.balance == 0, "Inactive account has non-zero balance: {d}", .{self.balance});
        }
    }

    /// Deposit money into the account.
    /// Demonstrates preconditions and postconditions with formatted messages.
    pub fn deposit(self: *Account, amount: u32) void {
        const old = .{ .balance = self.balance };
        return contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Account) void {
                // Enhanced preconditions with context
                requiref(s.is_active, "Cannot deposit to inactive account", .{});
                requiref(amount > 0, "Deposit amount must be positive, got {d}", .{amount});

                // Business logic
                s.balance += amount;

                // Enhanced postconditions with before/after context
                ensuref(s.balance == ctx.balance + amount, "Balance mismatch: expected {d}, got {d}", .{ ctx.balance + amount, s.balance });
            }
        }.run);
    }

    /// Withdraw money from the account.
    /// Demonstrates error handling with enhanced error messages.
    pub fn withdraw(self: *Account, amount: u32) !void {
        const old = .{ .balance = self.balance };
        return contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Account) !void {
                // Enhanced preconditions with detailed context
                requiref(s.is_active, "Cannot withdraw from inactive account", .{});
                requiref(amount <= s.balance, "Insufficient funds: requested {d}, available {d}", .{ amount, s.balance });

                // Business logic
                s.balance -= amount;

                // Enhanced postconditions
                ensuref(s.balance == ctx.balance - amount, "Withdrawal calculation error: expected {d}, got {d}", .{ ctx.balance - amount, s.balance });
            }
        }.run);
    }

    /// Close the account.
    /// Demonstrates context capture for clear error messages.
    pub fn close(self: *Account) void {
        return contract(self, null, struct {
            fn run(_: @TypeOf(null), s: *Account) void {
                requireCtx(s.balance == 0, "s.balance == 0");
                s.is_active = false;
                ensureCtx(!s.is_active, "!s.is_active");
            }
        }.run);
    }
};

// Comprehensive test suite demonstrating various contract scenarios
test "successful deposit and withdraw with formatted messages" {
    if (builtin.mode == .ReleaseFast) return;

    var acc = Account{ .balance = 100, .is_active = true };
    acc.deposit(50);
    try testing.expectEqual(@as(u32, 150), acc.balance);

    try acc.withdraw(20);
    try testing.expectEqual(@as(u32, 130), acc.balance);
}

test "formatted error messages in precondition failures" {
    if (builtin.mode == .ReleaseFast) return;

    const TestStruct = struct {
        fn testPanic() void {
            var acc = Account{ .balance = 0, .is_active = false };
            acc.deposit(100);
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "formatted error messages in postcondition failures" {
    if (builtin.mode == .ReleaseFast) return;

    const BuggyAccount = struct {
        balance: u32,
        is_active: bool,
        fn invariant(_: @This()) void {}
        pub fn withdraw(self: *@This(), amount: u32) void {
            const old = .{ .balance = self.balance };
            return contract(self, old, struct {
                fn run(ctx: @TypeOf(old), s: *@This()) void {
                    s.balance -= amount;
                    s.balance += 1; // Intentional bug
                    ensuref(s.balance == ctx.balance - amount, "Balance error: expected {d}, got {d}", .{ ctx.balance - amount, s.balance });
                }
            }.run);
        }
    };

    const TestStruct = struct {
        fn testPanic() void {
            var buggy_acc = BuggyAccount{ .balance = 100, .is_active = true };
            buggy_acc.withdraw(50);
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "context capture assertions" {
    if (builtin.mode == .ReleaseFast) return;

    const TestStruct = struct {
        fn testPanic() void {
            const x: i32 = 5;
            const y: i32 = 3;
            requireCtx(x < y, "x < y");
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "formatted require and ensure functions" {
    if (builtin.mode == .ReleaseFast) return;

    const x: f32 = 4.0;
    requiref(x >= 0.0, "Square root input must be non-negative, got {d}", .{x});

    const result = @sqrt(x);
    ensuref(result * result == x, "Square root verification failed: {d}^2 != {d}", .{ result, x });
}

test "formatted messages are eliminated in ReleaseFast" {
    if (builtin.mode != .ReleaseFast) return;

    // These would normally cause panics but should be completely compiled out
    requiref(false, "This should not panic in ReleaseFast mode", .{});
    ensuref(false, "This should also not panic in ReleaseFast mode", .{});
    requireCtx(false, "false");
    ensureCtx(false, "false");
}

test "reusable validators with enhanced error messages" {
    if (builtin.mode == .ReleaseFast) return;

    const isPositive = struct {
        fn check(n: i32) bool {
            return n > 0;
        }
    }.check;

    require(.{ isPositive, 10, "10 should be positive" });
    ensure(.{ isPositive, 1, "1 should be positive" });

    const IsLongerThan = struct {
        min_len: usize,
        fn run(self: @This(), s: []const u8) bool {
            return s.len > self.min_len;
        }
    };

    const longerThan5 = IsLongerThan{ .min_len = 5 };
    require(.{ longerThan5, "hello world", "string should be longer than 5" });
    ensure(.{ longerThan5, "a long string", "string should be longer than 5" });
}

test "requiref and ensuref with simple boolean conditions" {
    if (builtin.mode == .ReleaseFast) return;

    const x: f64 = 3.14159;
    const y: i32 = 42;

    require(.{ x > 0.0, "x must be positive" });
    require(.{ y >= 0, "y must be non-negative" });

    const result = x * 2;
    ensure(.{ result > x, "Result should be greater than input" });
}

test "context capture with complex expressions" {
    if (builtin.mode == .ReleaseFast) return;

    const a: f64 = 3.0;
    const b: f64 = 4.0;
    const c: f64 = 5.0;

    requireCtx(a * a + b * b == c * c, "a * a + b * b == c * c");

    const result = @sqrt(a * a + b * b);
    ensureCtx(@abs(result - c) < 0.0001, "@abs(result - c) < 0.0001");
}

test "reusable validators with all API variants" {
    if (builtin.mode == .ReleaseFast) return;

    const IsInRange = struct {
        min: i32,
        max: i32,
        fn run(self: @This(), value: i32) bool {
            return value >= self.min and value <= self.max;
        }
    };

    const range_validator = IsInRange{ .min = 10, .max = 50 };
    const test_value: i32 = 25;

    // Simple API
    require(.{ range_validator, test_value, "Value must be in range [10, 50]" });

    // Context API
    requireCtx(test_value % 5 == 0, "test_value % 5 == 0");

    const result = test_value * 2;
    ensure(.{ range_validator, result, "Result must be in range [10, 50]" });
    ensureCtx(result == test_value * 2, "result == test_value * 2");
}
