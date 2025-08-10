//! Zig-DbC -- A Design by Contract Library for Zig
//!
//! This library provides a set of functions to use design by contract (DbC) principles in
//! Zig programs.
//! DbC is a software engineering methodology that allows developers to specify
//! and verify program correctness through:
//!
//! - **Preconditions**: Conditions that must be true when a function is called
//! - **Postconditions**: Conditions that must be true when a function returns
//! - **Class Invariants**: Conditions that must hold for object instances all the time
//!
//! Zig-DbC is inspired by DbC concepts from languages like Eiffel and Ada,
//! and aims to provide a simple and idiomatic way to implement these principles in Zig.

const dbc = @import("dbc.zig");

pub const require = dbc.require;
pub const ensure = dbc.ensure;
pub const contract = dbc.contract;
pub const contractWithErrorTolerance = dbc.contractWithErrorTolerance;
