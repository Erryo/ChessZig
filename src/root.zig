//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const BB = @import("bitboard.zig");
const MoveGen = @import("move_gen.zig");
const zbench = @import("zbench");

const STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub fn make_move(bitboard: *BB.BitBoard) void {
    _ = bitboard;
}
test {
    const res: zbench.Result = undefined;
    _ = res;
    _ = MoveGen;
}

test {
    _ = BB;
}
