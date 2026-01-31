//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const BB = @import("bitboard.zig");
const expect = std.testing.expect;

const STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub fn make_move(bitboard: *BB.BitBoard) void {
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

    var bb = try BB.BitBoard.from_fen(STARTING_FEN);
    try bb.print_ansi(stdout);

    std.debug.print("generated FEN:{s}_EOL\n", .{try bb.to_FEN()});
    try expect(bb.active_color == BB.Color.white);
    try expect(bb.half_move == 0);
    try expect(bb.full_move == 1);
    //castling
    try expect(bb.castling_rights[0] == 1);
    try expect(bb.castling_rights[1] == 1);
    try expect(bb.castling_rights[2] == 1);
    try expect(bb.castling_rights[3] == 1);
    try expect(bb.en_passant.x == 0);
    try expect(bb.en_passant.y == 0);
}

test "fuzz fen to board" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
