const std = @import("std");
const chess = @import("chessZig");
const Allocator = std.mem.Allocator;

const GameError = error{
    InvalidMove,
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("memory leaked");
    }

    var stdout_buffer: [1024]u8 = std.mem.zeroes([1024]u8);
    var w = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &w.interface;
    defer writer.flush() catch {
        std.debug.print("failde to flush buffer at the end of the program\n", .{});
    };

    var stdin_buffer: [1024]u8 = std.mem.zeroes([1024]u8);
    var r = std.fs.File.stdin().reader(&stdin_buffer);
    const reader = &r.interface;

    try writer.print("starting chess engine: CLI-UCI version\n", .{});

    var bitboard = try chess.BB.BitBoard.from_fen(chess.BB.Starting_FEN);

    var game_manager: GameManager = .{ .bitboard = &bitboard, .stdout = writer, .allocator = allocator };

    //var timer = try std.time.Timer.start();
    const player_color: chess.BB.Color = .white;

    var sleep_s: u64 = 0;
    var sleep_ns: u64 = 0;
    while (true) {
        defer {
            writer.flush() catch {};
            std.posix.nanosleep(sleep_s, sleep_ns);
            sleep_ns = 0;
            sleep_s = 0;
        }
        try writer.print("\x1b[2J\x1b[H", .{}); // clear the screen

        const fen = try game_manager.bitboard.to_FEN();
        try writer.print("FEN:{s}\n", .{fen});

        try game_manager.bitboard.print_ansi(writer);

        try writer.print("\nYour Move in UCI>>>", .{});
        try writer.flush();

        if (game_manager.bitboard.active_color != player_color) {
            try game_manager.bot_move();
            continue;
        }
        const input_line = reader.takeDelimiter('\n') catch |err| {
            try writer.print("the program failed to process your move because of an error:{s}\nPlease try again!\n", .{@errorName(err)});
            sleep_s = 3;
            continue;
        };

        var uci: []u8 = undefined;

        if (input_line) |line| {
            if (line.len > 5) {
                try writer.print("the program received a move that exceeds the limit of 5 characters. Please try again!\n", .{});
                sleep_s = 3;
                continue;
            }
            uci = line;
        } else {
            try writer.print("the program received an empty move. Please try again!\n", .{});
            sleep_s = 3;
            continue;
        }

        const processed_sucsesfully = try game_manager.processMove(uci);

        if (!processed_sucsesfully) {
            sleep_s = 3;
            continue;
        }
    }
}

const GameManager = struct {
    stdout: *std.Io.Writer,
    allocator: Allocator,
    bitboard: *chess.BB.BitBoard,

    fn processMove(gm: *GameManager, uci: []const u8) !bool {
        var move = chess.MoveGen.Move.from_UCI(gm.bitboard, uci) catch |err| {
            try gm.stdout.print("the program failed to process your move because of an error:{s}\nPlease try again!\n", .{@errorName(err)});
            return false;
        };

        const full_check_passed = try chess.Engine.full_check(gm.bitboard, &move, gm.allocator);
        if (!full_check_passed) {
            try gm.stdout.print("the program received an illegal move.Please try again!\n", .{});
            return false;
        }
        chess.Engine.make_move(gm.bitboard, &move);
        return true;
    }

    fn bot_move(gm: *GameManager) !void {
        var best_move = try chess.Engine.get_best_move(gm.bitboard, &gm.allocator);
        chess.Engine.make_move(
            gm.bitboard,
            &best_move.move,
        );
        return;
    }
};
