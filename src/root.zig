//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const MoveGen = @import("move_gen.zig");
pub const BB = @import("bitboard.zig");

test {
    _ = MoveGen;
}

pub fn make_move(bb: *BB.BitBoard, move: MoveGen.Move) !void {
    _ = bb;
    _ = move;
}
