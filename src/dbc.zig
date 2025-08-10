//! ## Zig-DbC -- A Design by Contract Library for Zig
//!
//! This module provides a set of functions to use design by contract (DbC) principles in Zig programs.
//!
//! ### Features
//!
//! - **Preconditions**: Assert conditions that must be true when entering a function (at call time)
//! - **Postconditions**: Assert conditions that must be true when exiting a function (at return time)
//! - **Class invariants**: Assert structural consistency of objects before and after method calls
//! - **Zero-cost abstractions**: All contract checks are compiled out in `ReleaseFast` mode
//! - **Error tolerance**: Optional mode to preserve partial state changes when errors occur
//!
//! ### Usage
//!
//! #### Basic Assertions
//!
//! ```zig
//! const dbc = @import("dbc.zig");
//!
//! fn divide(a: f32, b: f32) f32 {
//!     dbc.require(b != 0.0, "Division by zero");
//!     const result = a / b;
//!     dbc.ensure(!std.math.isNan(result), "Result must be a valid number");
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
//!     // Class invariant - checked before and after each contract
//!     fn invariant(self: BankAccount) void {
//!         dbc.require(if (!self.is_open) self.balance == 0 else true,
//!                    "Closed accounts must have zero balance");
//!     }
//!
//!     pub fn withdraw(self: *BankAccount, amount: u64) !void {
//!         const old_state = .{ .balance = self.balance };
//!         return dbc.contract(self, old_state, struct {
//!             fn run(ctx: @TypeOf(old_state), account: *BankAccount) !void {
//!                 // Preconditions
//!                 dbc.require(account.is_open, "Account must be open");
//!                 dbc.require(amount <= account.balance, "Insufficient funds");
//!
//!                 // Business logic
//!                 account.balance -= amount;
//!
//!                 // Postconditions
//!                 dbc.ensure(account.balance == ctx.balance - amount,
//!                           "Balance must decrease by withdrawal amount");
//!             }
//!         }.run);
//!     }
//! };
//! ```
//!
//! ### Build Mode Behavior
//!
//! - In `Debug`, `ReleaseSafe`, and `ReleaseSmall` modes, all contracts are active and will panic on violation.
//! - In `ReleaseFast` mode, all contract checks are compiled out for maximum performance.
//!
//! ### Error Handling
//!
//! The library supports two modes of contract enforcement:
//! - `contract()`: `Strict mode` - invariants are checked even if the body returns an error
//! - `contractWithErrorTolerance()`: `Tolerant mode` - allows partial state changes when errors occur

const std = @import("std");
const builtin = @import("builtin");

/// Assert a precondition that must be true at function entry.
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// ### Parameters
/// - `condition`: Boolean expression that must evaluate to true
/// - `msg`: Compile-time error message displayed on assertion failure
///
/// ### Panics
/// Panics with the provided message if condition is false in `Debug`, `ReleaseSafe`, and `ReleaseSmall` build modes.
///
/// ### Example
/// ```zig
/// fn sqrt(x: f64) f64 {
///     require(x >= 0.0, "Square root requires non-negative input");
///     return std.math.sqrt(x);
/// }
/// ```
pub inline fn require(condition: bool, comptime msg: []const u8) void {
    if (builtin.mode != .ReleaseFast) {
        if (!condition) @panic(msg);
    }
}

/// Assert a postcondition that must be true at function exit.
/// Only active in `Debug`, `ReleaseSafe`, and `ReleaseSmall` builds.
///
/// ### Parameters
/// - `condition`: Boolean expression that must evaluate to true
/// - `msg`: Compile-time error message displayed on assertion failure
///
/// ### Panics
/// Panics with the provided message if condition is false in `Debug`, `ReleaseSafe`, and `ReleaseSmall` build modes.
///
/// ### Example
/// ```zig
/// fn abs(x: i32) i32 {
///     const result = if (x < 0) -x else x;
///     ensure(result >= 0, "Absolute value must be non-negative");
///     return result;
/// }
/// ```
pub inline fn ensure(condition: bool, comptime msg: []const u8) void {
    if (builtin.mode != .ReleaseFast) {
        if (!condition) @panic(msg);
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
/// Automatically checks class invariants before and after the method execution.
/// If the method returns an error, invariants are still validated.
///
/// ### Parameters
/// - `self`: Pointer to the object whose method is being executed
/// - `context`: Historical state or context for postcondition verification
/// - `body`: Compile-time struct with a `run` function containing the method logic
///
/// ### Returns
/// The return value of the body's run function
///
/// ### Class Invariants
/// If the object type defines an `invariant(self: Self) void` function, it will be
/// called before method entry and after method exit (including error cases).
///
/// ### Example
/// ```zig
/// pub fn transfer(self: *Account, to: *Account, amount: u64) !void {
///     const old_state = .{ .balance = self.balance, .to_balance = to.balance };
///     return contract(self, old_state, struct {
///         fn run(ctx: @TypeOf(old_state), from: *Account) !void {
///             require(from.balance >= amount, "Insufficient funds");
///             from.balance -= amount;
///             to.balance += amount;
///             ensure(from.balance + to.balance == ctx.balance + ctx.to_balance,
///                   "Total balance must be preserved");
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
/// Class invariants are only checked if the method completes successfully.
///
/// ### Parameters
/// - `self`: Pointer to the object whose method is being executed
/// - `context`: Historical state or context for postcondition verification
/// - `body`: Compile-time struct with a `run` function containing the method logic
///
/// ### Returns
/// The return value of the body's run function
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

/// Example implementation demonstrating DbC principles.
/// This Account struct showcases preconditions, postconditions, and class invariants.
const Account = struct {
    balance: u32,
    is_active: bool,

    /// Class invariant: inactive accounts must have zero balance.
    /// This is automatically checked before and after each contracted method.
    fn invariant(self: Account) void {
        if (!self.is_active) {
            require(self.balance == 0, "Inactive account must have zero balance");
        }
    }

    /// Deposit money into the account.
    /// Demonstrates preconditions and postconditions within a contract.
    pub fn deposit(self: *Account, amount: u32) void {
        const old = .{ .balance = self.balance };
        return contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Account) void {
                // Preconditions
                require(s.is_active, "Account is not active");
                require(amount > 0, "Deposit amount must be positive");

                // Business logic
                s.balance += amount;

                // Postconditions
                ensure(s.balance == ctx.balance + amount, "Balance did not increase correctly");
            }
        }.run);
    }

    /// Withdraw money from the account.
    /// Demonstrates error handling within contracts.
    pub fn withdraw(self: *Account, amount: u32) !void {
        const old = .{ .balance = self.balance };
        return contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Account) !void {
                // Preconditions
                require(s.is_active, "Account is not active");
                require(amount <= s.balance, "Insufficient funds");

                // Business logic
                s.balance -= amount;

                // Postconditions
                ensure(s.balance == ctx.balance - amount, "Balance did not decrease correctly");
            }
        }.run);
    }

    /// Close the account.
    /// Demonstrates contracts without historical context.
    pub fn close(self: *Account) void {
        return contract(self, null, struct {
            fn run(_: ?*anyopaque, s: *Account) void {
                require(s.balance == 0, "Can only close an account with zero balance");
                s.is_active = false;
                ensure(!s.is_active, "Account failed to close");
            }
        }.run);
    }
};

// Comprehensive test suite demonstrating various contract scenarios
test "successful deposit and withdraw" {
    if (builtin.mode == .ReleaseFast) return;

    var acc = Account{ .balance = 100, .is_active = true };
    acc.deposit(50);
    try testing.expectEqual(@as(u32, 150), acc.balance);

    try acc.withdraw(20);
    try testing.expectEqual(@as(u32, 130), acc.balance);
}

test "precondition failure: deposit to inactive account" {
    if (builtin.mode == .ReleaseFast) return;

    const TestStruct = struct {
        fn testPanic() void {
            var acc = Account{ .balance = 0, .is_active = false };
            acc.deposit(100);
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "postcondition failure: simulated bug in withdraw" {
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
                    ensure(s.balance == ctx.balance - amount, "Balance did not decrease correctly");
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

test "invariant failure on entry" {
    if (builtin.mode == .ReleaseFast) return;

    const TestStruct = struct {
        fn testPanic() void {
            var acc = Account{ .balance = 10, .is_active = false }; // Invalid state
            acc.deposit(100);
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "invariant failure on exit" {
    if (builtin.mode == .ReleaseFast) return;

    const BadCloser = struct {
        balance: u32,
        is_active: bool,
        fn invariant(self: @This()) void {
            if (!self.is_active) {
                require(self.balance == 0, "Inactive account must have zero balance");
            }
        }
        pub fn badClose(self: *@This()) void {
            return contract(self, null, struct {
                fn run(ctx: ?*anyopaque, s: *@This()) void {
                    _ = ctx;
                    s.is_active = false; // Violates invariant - balance is non-zero
                }
            }.run);
        }
    };

    const TestStruct = struct {
        fn testPanic() void {
            var acc = BadCloser{ .balance = 100, .is_active = true };
            acc.badClose();
        }
    };

    try std.testing.expectPanic(TestStruct.testPanic);
}

test "contract with no class invariant" {
    if (builtin.mode == .ReleaseFast) return;

    const NoInvariant = struct {
        x: i32,
        pub fn set(self: *@This(), val: i32) void {
            return contract(self, null, struct {
                fn run(_: ?*anyopaque, s: *@This()) void {
                    require(val > 0, "Value must be positive");
                    s.x = val;
                    ensure(s.x == val, "Value was not set");
                }
            }.run);
        }
    };
    var obj = NoInvariant{ .x = 0 };
    obj.set(42);
    try testing.expectEqual(42, obj.x);
}

test "error return preserves invariant check" {
    if (builtin.mode == .ReleaseFast) return;

    const BadWithdrawer = struct {
        balance: u32,
        is_active: bool,
        fn invariant(self: @This()) void {
            if (!self.is_active) {
                require(self.balance == 0, "Invariant failure");
            }
        }
        pub fn withdraw(self: *@This()) !void {
            return contract(self, null, struct {
                fn run(_: ?*anyopaque, s: *@This()) !void {
                    _ = s;
                    return error.SomethingWentWrong;
                }
            }.run);
        }
    };

    var acc = BadWithdrawer{ .balance = 100, .is_active = true };
    const err = acc.withdraw() catch |e| e;
    try testing.expectEqual(error.SomethingWentWrong, err);
    try testing.expectEqual(@as(u32, 100), acc.balance);
    try testing.expect(acc.is_active);
}

test "contracts are disabled in ReleaseFast" {
    if (builtin.mode != .ReleaseFast) return;

    var acc = Account{ .balance = 0, .is_active = false };
    acc.deposit(100); // Would normally violate precondition

    try testing.expectEqual(@as(u32, 100), acc.balance);
}

test "error tolerant contract allows partial state changes on error" {
    if (builtin.mode == .ReleaseFast) return;

    const ProblematicStruct = struct {
        field1: u32,
        field2: u32,

        fn invariant(self: @This()) void {
            require((self.field1 % 2) == (self.field2 % 2), "Fields must have same parity");
        }

        pub fn problematicMethodStrict(self: *@This()) !void {
            return contract(self, null, struct {
                fn run(_: ?*anyopaque, s: *@This()) !void {
                    s.field1 = 3; // This would violate invariant
                    return error.SomethingWentWrong;
                }
            }.run);
        }

        pub fn problematicMethodTolerant(self: *@This()) !void {
            return contractWithErrorTolerance(self, null, struct {
                fn run(_: ?*anyopaque, s: *@This()) !void {
                    s.field1 = 3; // Partial state change preserved
                    return error.SomethingWentWrong;
                }
            }.run);
        }
    };

    const TestStrictPanic = struct {
        fn testPanic() void {
            var obj = ProblematicStruct{ .field1 = 2, .field2 = 4 };
            _ = obj.problematicMethodStrict() catch {};
        }
    };
    try std.testing.expectPanic(TestStrictPanic.testPanic);

    var obj2 = ProblematicStruct{ .field1 = 2, .field2 = 4 };
    const err = obj2.problematicMethodTolerant() catch |e| e;
    try testing.expectEqual(error.SomethingWentWrong, err);
    try testing.expectEqual(@as(u32, 3), obj2.field1);
    try testing.expectEqual(@as(u32, 4), obj2.field2);
}
