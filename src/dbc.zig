//! ## Zig-DbC -- A Design by Contract Library for Zig
//!
//! This module provides a set of functions to use design by contract (DbC) principles in Zig programs.
//!
//! ### Features
//!
//! - **Preconditions**: Assert conditions that must be true when entering a function (at call time)
//! - **Postconditions**: Assert conditions that must be true when exiting a function (at return time)
//! - **Invariants**: Assert structural consistency of objects before and after method calls
//! - **Zero-cost abstractions**: All contract checks are compiled out in `ReleaseFast` mode
//! - **Error tolerance**: Optional mode to preserve partial state changes when errors occur
//! - **Formatted messages**: Compile-time formatted assertion messages with automatic context capture
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
//!         dbc.require(.{if (!self.is_open) self.balance == 0 else true,
//!                    "Closed accounts must have zero balance"});
//!     }
//!
//!     pub fn withdraw(self: *BankAccount, amount: u64) !void {
//!         const old_state = .{ .balance = self.balance };
//!         return dbc.contract(self, old_state, struct {
//!             fn run(ctx: @TypeOf(old_state), account: *BankAccount) !void {
//!                 // Enhanced preconditions with context
//!                 dbc.requiref(account.is_open, "Account must be open");
//!                 dbc.requiref(amount <= account.balance,
//!                             "Insufficient funds: requested {d}, available {d}",
//!                             .{amount, account.balance});
//!
//!                 // Business logic
//!                 account.balance -= amount;
//!
//!                 // Enhanced postconditions
//!                 dbc.ensuref(account.balance == ctx.balance - amount,
//!                           "Balance mismatch: expected {d}, got {d}",
//!                           .{ctx.balance - amount, account.balance});
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
/// A validator can be a function pointer or a struct with a `run` method that
/// accepts `value` and returns a boolean.
///
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// ### Panics
/// Panics with the provided message if the condition is false or the validator returns false.
///
/// ### Example
/// ```zig
/// // With a boolean condition
/// fn sqrt(x: f64) f64 {
///     require(.{x >= 0.0, "Square root requires non-negative input"});
///     return std.math.sqrt(x);
/// }
///
/// // With a reusable validator
/// const isPositive = fn(n: i32) bool { return n > 0; };
///
/// fn doSomething(val: i32) void {
///     require(.{isPositive, val, "Value must be positive"});
/// }
/// ```
pub inline fn require(args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    comptime {
        const info = @typeInfo(@TypeOf(args));
        if (info != .@"struct") {
            @compileError("arguments to require must be a tuple, e.g. require(.{condition, msg})");
        }
        if (info.@"struct".is_tuple == false) {
            @compileError("arguments to require must be a tuple, e.g. require(.{condition, msg})");
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

            if (@typeInfo(ValidatorType) == .Fn) {
                break :blk validator(value);
            } else if (@typeInfo(ValidatorType) == .Struct and @hasDecl(ValidatorType, "run")) {
                break :blk validator.run(value);
            } else {
                @compileError("Validator must be a function or a struct with a 'run' method.");
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
///
/// ### Parameters
/// - `condition`: Boolean expression to check
/// - `fmt`: Compile-time format string
/// - `args`: Tuple of arguments for formatting
///
/// ### Example
/// ```zig
/// fn divide(a: f32, b: f32) f32 {
///     requiref(b != 0.0, "Cannot divide {d} by zero", .{a});
///     return a / b;
/// }
/// ```
pub inline fn requiref(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint(fmt, args);
        @panic(msg);
    }
}

/// Assert a precondition with automatic context capture.
///
/// Automatically captures the expression text for better error messages.
/// Useful when you want detailed failure context without manual formatting.
///
/// ### Parameters
/// - `condition`: Boolean expression to check
/// - `expr_str`: String representation of the condition expression
///
/// ### Example
/// ```zig
/// fn withdraw(account: *Account, amount: u64) void {
///     requireCtx(amount <= account.balance, "amount <= account.balance");
/// }
/// ```
pub inline fn requireCtx(condition: bool, comptime expr_str: []const u8) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint("Precondition failed: {s}", .{expr_str});
        @panic(msg);
    }
}

/// Assert a postcondition that must be true at function exit.
///
/// Can be called in two ways:
/// 1. With a boolean condition: `ensure(.{condition, "error message"})`
/// 2. With a reusable validator: `ensure(.{validator, value, "error message"})`
///
/// A validator can be a function pointer or a struct with a `run` method that
/// accepts `value` and returns a boolean.
///
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// ### Panics
/// Panics with the provided message if the condition is false or the validator returns false.
///
/// ### Example
/// ```zig
/// // With a boolean condition
/// fn abs(x: i32) i32 {
///     const result = if (x < 0) -x else x;
///     ensure(.{result >= 0, "Absolute value must be non-negative"});
///     return result;
/// }
///
/// // With a reusable validator
/// const isPositive = fn(n: i32) bool { return n > 0; };
///
/// fn doSomething(val: i32) i32 {
///     const result = val + 1;
///     ensure(.{isPositive, result, "Result must be positive"});
///     return result;
/// }
/// ```
pub inline fn ensure(args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    comptime {
        const info = @typeInfo(@TypeOf(args));
        if (info != .@"struct") {
            @compileError("arguments to ensure must be a tuple, e.g. ensure(.{condition, msg})");
        }
        if (info.@"struct".is_tuple == false) {
            @compileError("arguments to ensure must be a tuple, e.g. ensure(.{condition, msg})");
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

            if (@typeInfo(ValidatorType) == .Fn) {
                break :blk validator(value);
            } else if (@typeInfo(ValidatorType) == .Struct and @hasDecl(ValidatorType, "run")) {
                break :blk validator.run(value);
            } else {
                @compileError("Validator must be a function or a struct with a 'run' method.");
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
///
/// ### Parameters
/// - `condition`: Boolean expression to check
/// - `fmt`: Compile-time format string
/// - `args`: Tuple of arguments for formatting
///
/// ### Example
/// ```zig
/// fn multiply(a: i32, b: i32) i32 {
///     const result = a * b;
///     ensuref(result / a == b, "Multiplication overflow: {d} * {d} = {d}", .{a, b, result});
///     return result;
/// }
/// ```
pub inline fn ensuref(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint(fmt, args);
        @panic(msg);
    }
}

/// Assert a postcondition with automatic context capture.
///
/// Automatically captures the expression text for better error messages.
/// Useful when you want detailed failure context without manual formatting.
///
/// ### Parameters
/// - `condition`: Boolean expression to check
/// - `expr_str`: String representation of the condition expression
///
/// ### Example
/// ```zig
/// fn increment(x: *i32) void {
///     const old_value = x.*;
///     x.* += 1;
///     ensureCtx(x.* == old_value + 1, "x.* == old_value + 1");
/// }
/// ```
pub inline fn ensureCtx(condition: bool, comptime expr_str: []const u8) void {
    if (builtin.mode == .ReleaseFast) return;

    if (!condition) {
        const msg = std.fmt.comptimePrint("Postcondition failed: {s}", .{expr_str});
        @panic(msg);
    }
}

/// Defines how contracts handle errors and invariant checking.
const ContractMode = enum {
    /// Strict mode: invariants are checked even when the contract body returns an error.
    /// If an error occurs, invariants are still validated before propagating the error.
    strict,

    /// Error-tolerant mode: allows partial state changes when errors occur.
    /// Invariants are only checked if the contract body completes successfully.
    error_tolerant,
};

/// Internal function implementing contract behavior for both strict and error-tolerant modes.
///
/// ### Parameters
/// - `self`: Pointer to the object whose method is being contracted
/// - `context`: Historical state or additional context for postcondition checking
/// - `body`: Compile-time function containing the method implementation
/// - `mode`: Contract enforcement mode (strict or error_tolerant)
///
/// ### Returns
/// The return value of the body function
inline fn contractWithMode(
    self: anytype,
    context: anytype,
    comptime body: anytype,
    comptime mode: ContractMode,
) @TypeOf(body(context, self)) {
    // In ReleaseFast mode, contracts are completely eliminated
    if (builtin.mode == .ReleaseFast) {
        return body(context, self);
    }

    const self_type = @TypeOf(self.*);
    const has_invariant = @hasDecl(self_type, "invariant");

    // Check invariant at method entry
    if (has_invariant) {
        self.invariant();
    }

    switch (mode) {
        .strict => {
            // Ensure invariant is checked at method exit, even on error
            defer if (has_invariant) {
                self.invariant();
            };
            return body(context, self);
        },
        .error_tolerant => {
            // Only check invariant if method completes successfully
            const result = body(context, self) catch |err| {
                return err;
            };

            if (has_invariant) {
                self.invariant();
            }

            return result;
        },
    }
}

/// Execute a method body with strict DbC enforcement.
///
/// Automatically checks invariants before and after the method execution.
/// If the method returns an error, invariants are still validated.
///
/// ### Parameters
/// - `self`: Pointer to the object whose method is being executed
/// - `context`: Historical state or context for postcondition verification
/// - `body`: Compile-time struct with a `run` function containing the method logic
///
/// ### Returns
/// The return value of the body's `run` function
///
/// ### Invariants
/// If the object type defines an `invariant(self: Self) void` function, it will be
/// called before method entry and after method exit (including error cases).
///
/// ### Example
/// ```zig
/// pub fn transfer(self: *Account, to: *Account, amount: u64) !void {
///     const old_state = .{ .balance = self.balance, .to_balance = to.balance };
///     return contract(self, old_state, struct {
///         fn run(ctx: @TypeOf(old_state), from: *Account) !void {
///             requiref(from.balance >= amount, "Insufficient funds: need {d}, have {d}",
///                     .{amount, from.balance});
///             from.balance -= amount;
///             to.balance += amount;
///             ensuref(from.balance + to.balance == ctx.balance + ctx.to_balance,
///                   "Balance conservation failed: before={d}, after={d}",
///                   .{ctx.balance + ctx.to_balance, from.balance + to.balance});
///         }
///     }.run);
/// }
/// ```
pub inline fn contract(
    self: anytype,
    context: anytype,
    comptime body: anytype,
) @TypeOf(body(context, self)) {
    return contractWithMode(self, context, body, .strict);
}

/// Execute a method body with error-tolerant DbC enforcement.
///
/// Similar to `contract()` but allows partial state changes when errors occur.
/// Invariants are only checked if the method completes successfully.
///
/// ### Parameters
/// - `self`: Pointer to the object whose method is being executed
/// - `context`: Historical state or context for postcondition verification
/// - `body`: Compile-time struct with a `run` function containing the method logic
///
/// ### Returns
/// The return value of the body's `run` function
///
/// ### Use Cases
/// Use this when you need to allow partial state modifications during error conditions,
/// or when invariant checking after errors would be inappropriate for your use case.
///
/// ### Example
/// ```zig
/// pub fn bulkUpdate(self: *Database, updates: []Update) !void {
///     return contractWithErrorTolerance(self, null, struct {
///         fn run(_: ?*anyopaque, db: *Database) !void {
///             for (updates) |update| {
///                 try db.applyUpdate(update); // May fail partway through
///             }
///         }
///     }.run);
/// }
/// ```
pub inline fn contractWithErrorTolerance(
    self: anytype,
    context: anytype,
    comptime body: anytype,
) @TypeOf(body(context, self)) {
    return contractWithMode(self, context, body, .error_tolerant);
}

// Test imports and examples
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
                requiref(s.is_active, "Cannot deposit to inactive account");
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
                requiref(s.is_active, "Cannot withdraw from inactive account");
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
            fn run(_: ?*anyopaque, s: *Account) void {
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
    requiref(false, "This should not panic in ReleaseFast mode");
    ensuref(false, "This should also not panic in ReleaseFast mode");
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
