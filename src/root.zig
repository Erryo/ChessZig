//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const board = @import("bitboard.zig");
const expect = std.testing.expect;

const STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub fn make_move(bitboard: *board.BitBoard) void {
    _ = bitboard;
}

test "make form fen" {
    //    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    //    defer arena.deinit();
    //    var allocator = arena.allocator();
    //
    var buf: [512]u8 = undefined;
    var w = std.fs.File.stdout().writer(&buf);
    const stdout = &w.interface;

    var bb = try board.BitBoard.from_fen(STARTING_FEN);
    try bb.print(stdout);

    std.debug.print("generated FEN:{s}_EOL\n", .{bb.to_FEN()});
}
