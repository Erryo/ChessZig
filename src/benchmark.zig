const zbench = @import("zbench");
const std = @import("std");
const BB = @import("bitboard.zig");
const MoveGen = @import("moveGen.zig");
const Engine = @import("engine.zig");
const Allocator = std.mem.Allocator;

fn benchmark_make_unmake(allocator: std.mem.Allocator) void {
    _ = allocator;
    var bb = BB.BitBoard.from_fen(BB.Starting_FEN) catch unreachable;

    var move = MoveGen.Move{
        .undo = null,
        .flag = .double_pawn_push,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = .{ .x = 4, .y = 6 },
        .dst = .{ .x = 4, .y = 4 },
    };

    Engine.make_move(&bb, &move);
    Engine.unmake_move(&bb, &move);
}

fn benchmark_full_check(allocator: std.mem.Allocator) void {
    var bb = BB.BitBoard.from_fen(BB.Starting_FEN) catch unreachable;

    var move = MoveGen.Move{
        .undo = null,
        .flag = .double_pawn_push,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = .{ .x = 4, .y = 6 },
        .dst = .{ .x = 4, .y = 4 },
    };

    _ = Engine.full_check(&bb, &move, allocator) catch unreachable;
}

fn benchmark_pseudo_check(allocator: Allocator) void {
    var bb = BB.BitBoard.from_fen(BB.Starting_FEN) catch unreachable;

    var move = MoveGen.Move{
        .undo = null,
        .flag = .double_pawn_push,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = .{ .x = 4, .y = 6 },
        .dst = .{ .x = 4, .y = 4 },
    };

    _ = Engine.pseudo_check(&bb, &move, allocator) catch unreachable;
}

fn benchmark_board_from_fen(allocator: Allocator) void {
    _ = allocator;
    const bb = BB.BitBoard.from_fen(BB.Starting_FEN) catch unreachable;
    _ = bb;
}

fn benchmark_move_gen_1st(allocator: Allocator) void {
    var bb = BB.BitBoard.from_fen(BB.Starting_FEN) catch unreachable;
    const moves = Engine.generate_all_moves(&bb, allocator) catch unreachable;
    allocator.free(moves);
}

fn benchmark_generate_move_gen_complex(allocator: Allocator) void {
    var bb = BB.BitBoard.from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") catch unreachable;
    const moves = Engine.generate_all_moves(&bb, allocator) catch unreachable;
    allocator.free(moves);
}

test "benchmark test" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var buffer = std.mem.zeroes([1024]u8);
    var stdout = std.fs.File.stderr().writer(&buffer);
    const writer = &stdout.interface;

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();
    try bench.add("Booard from fen", benchmark_board_from_fen, .{});
    try bench.add("Make and Unmakae", benchmark_make_unmake, .{});
    try bench.add("Full Check", benchmark_full_check, .{});
    try bench.add("Pseudo Check", benchmark_pseudo_check, .{});
    try bench.add("Move Gen 1st", benchmark_move_gen_1st, .{});
    try bench.run(writer);
    try writer.flush();
}
