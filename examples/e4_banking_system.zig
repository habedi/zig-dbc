const std = @import("std");
const dbc = @import("dbc");

const BankAccount = struct {
    const Self = @This();

    balance: u64,
    account_number: u32,
    is_active: bool,
    transaction_count: u32,

    fn invariant(self: Self) void {
        // Simple API for basic conditions
        dbc.require(.{ self.account_number > 0, "Account number must be positive" });

        // Context capture for simple expressions
        dbc.requireCtx(self.balance >= 0 or !self.is_active, "self.balance >= 0 or !self.is_active");
    }

    pub fn init(account_number: u32) Self {
        dbc.require(.{ account_number > 0, "Account number must be positive" });

        return Self{
            .balance = 0,
            .account_number = account_number,
            .is_active = true,
            .transaction_count = 0,
        };
    }

    pub fn deposit(self: *Self, amount: u64) void {
        const old = .{ .balance = self.balance, .tx_count = self.transaction_count, .amount = amount };

        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Self) void {
                // Mixed API usage showing different styles
                dbc.require(.{ s.is_active, "Account must be active for deposits" });
                dbc.require(.{ ctx.amount > 0, "Deposit amount must be positive" });
                dbc.requireCtx(ctx.amount <= 1_000_000, "ctx.amount <= 1_000_000");

                // Business logic
                s.balance += ctx.amount;
                s.transaction_count += 1;

                // Postconditions using different API styles
                dbc.ensure(.{ s.balance == ctx.balance + ctx.amount, "Balance calculation error" });
                dbc.ensureCtx(s.transaction_count == ctx.tx_count + 1, "s.transaction_count == ctx.tx_count + 1");
            }
        }.run);
    }

    pub fn withdraw(self: *Self, amount: u64) !void {
        const old = .{ .balance = self.balance, .tx_count = self.transaction_count, .amount = amount };

        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), s: *Self) !void {
                // Preconditions
                dbc.require(.{ s.is_active, "Cannot withdraw from inactive account" });
                dbc.require(.{ ctx.amount > 0, "Withdrawal amount must be positive" });
                dbc.require(.{ ctx.amount <= s.balance, "Insufficient funds" });

                // Simulate potential error
                if (ctx.amount > 50_000) return error.DailyLimitExceeded;

                // Business logic
                s.balance -= ctx.amount;
                s.transaction_count += 1;

                // Postconditions
                dbc.ensure(.{ s.balance == ctx.balance - ctx.amount, "Withdrawal calculation error" });
                dbc.ensure(.{ s.transaction_count == ctx.tx_count + 1, "Transaction count should increment" });
            }
        }.run);
    }

    pub fn transfer(self: *Self, to: *Self, amount: u64) !void {
        const old = .{ .from_balance = self.balance, .to_balance = to.balance, .from_tx = self.transaction_count, .to_tx = to.transaction_count, .amount = amount, .to_ptr = to };

        return dbc.contract(self, old, struct {
            fn run(ctx: @TypeOf(old), from: *Self) !void {
                dbc.require(.{ from.is_active, "Sender account must be active" });
                dbc.require(.{ ctx.to_ptr.is_active, "Recipient account must be active" });
                dbc.require(.{ from.balance >= ctx.amount, "Insufficient funds for transfer" });

                // Business logic - both accounts updated within contract
                from.balance -= ctx.amount;
                from.transaction_count += 1;
                ctx.to_ptr.balance += ctx.amount;
                ctx.to_ptr.transaction_count += 1;

                // Postconditions
                dbc.ensure(.{ from.balance == ctx.from_balance - ctx.amount, "Transfer amount calculation error" });
                dbc.ensureCtx(from.transaction_count == ctx.from_tx + 1, "from.transaction_count == ctx.from_tx + 1");
                dbc.ensure(.{ ctx.to_ptr.balance == ctx.to_balance + ctx.amount, "Recipient balance calculation error" });
                dbc.ensureCtx(ctx.to_ptr.transaction_count == ctx.to_tx + 1, "ctx.to_ptr.transaction_count == ctx.to_tx + 1");
            }
        }.run);
    }
};

pub fn main() !void {
    const builtin = @import("builtin");
    std.debug.print("Banking Systsem Example (contracts active: {})\n", .{builtin.mode != .ReleaseFast});

    var account1 = BankAccount.init(12345);
    var account2 = BankAccount.init(67890);

    account1.deposit(1000);
    account2.deposit(500);

    std.debug.print("Account 1 balance: {d}\n", .{account1.balance});
    std.debug.print("Account 2 balance: {d}\n", .{account2.balance});

    try account1.transfer(&account2, 250);

    std.debug.print("After transfer - Account 1: {d}, Account 2: {d}\n", .{ account1.balance, account2.balance });

    try account1.withdraw(100);
    std.debug.print("After withdrawal - Account 1: {d}\n", .{account1.balance});
}
