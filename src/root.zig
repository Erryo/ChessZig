//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const MoveGen = @import("moveGen.zig");
pub const BB = @import("bitboard.zig");
pub const Engine = @import("engine.zig");
pub const Benchmark = @import("benchmark.zig");

test {
    _ = MoveGen;
}

test {
    _ = Engine;
}

test {
    _ = Benchmark;
}

test {
    _ = BB;
}
