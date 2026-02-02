const std = @import("std");
const chess = @import("chessZig");

const GameError = error{
    InvalidMove,
};

pub fn main() !void {
    //    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    //    const alloator = arena.allocator();

    var stdout_buffer: [1024]u8 = std.mem.zeroes([1024]u8);
    var w = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &w.interface;
    defer writer.flush() catch {
        std.debug.print("failde to flush buffer at the end of the program\n", .{});
    };

    var stdin_buffer: [1024]u8 = std.mem.zeroes([1024]u8);
    var r = std.fs.File.stdin().reader(&stdin_buffer);
    const reader = &r.interface;

    //    var line_buffer: [512]u8 = std.mem.zeroes([512]u8);
    //    var line_writer: std.Io.Writer = .fixed(&line_buffer);

    try writer.print("starting chess engine: CLI-UCI version\n", .{});

    const bitboard = try chess.BB.BitBoard.from_fen(chess.BB.Starting_FEN);

    var game_manager: GameManager = .{ .bitboard = bitboard, .stdout = writer };

    //var timer = try std.time.Timer.start();

    while (true) {
        defer writer.flush() catch {};
        try writer.print("\x1b[2J\x1b[H", .{});

        try game_manager.bitboard.print_ansi(writer);
        try writer.print("\nYour Move in UCI>>>", .{});
        try writer.flush();

        //        const bytes_read: usize = reader.streamDelimiterLimit(&line_writer, '\n', .limited(6)) catch |err| {
        //            try writer.print("the program failed to process your move because of an error:{s}\nPlease try again!\n", .{@errorName(err)});
        //            continue;
        //        };
        const input_line = reader.takeDelimiter('\n') catch |err| {
            try writer.print("the program failed to process your move because of an error:{s}\nPlease try again!\n", .{@errorName(err)});
            continue;
        };

        var uci: []u8 = undefined;

        if (input_line) |line| {
            if (line.len > 5) {
                try writer.print("the program received a move that exceeds the limit of 5 characters. Please try again!\n", .{});
                continue;
            }
            uci = line;
        } else {
            try writer.print("the program received an empty move. Please try again!\n", .{});
            continue;
        }

        try writer.print("Your input was: {s} \n", .{uci});
        try game_manager.processMove(uci);
        try game_manager.bitboard.print_ansi(writer);

        std.posix.nanosleep(0, 5e8);
    }
}

const GameManager = struct {
    stdout: *std.Io.Writer,
    bitboard: chess.BB.BitBoard,

    fn processMove(gm: *GameManager, uci: []const u8) !void {
        var move = chess.MoveGen.Move.from_UCI(&gm.bitboard, uci) catch |err| {
            try gm.stdout.print("the program failed to process your move because of an error:{s}\nPlease try again!\n", .{@errorName(err)});
            return;
        };

        chess.Engine.make_move(&gm.bitboard, &move);
    }
};
