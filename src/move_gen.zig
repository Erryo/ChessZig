const BB = @import("bitboard.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const SpecialsArray = std.ArrayList(SpecialMoves);

const KnightDeltas = [8][2]i3{
    [2]i3{ -2, -1 },
    [2]i3{ -1, -2 },
    [2]i3{ 1, -2 },
    [2]i3{ 2, -1 },
    [2]i3{ -2, 1 },
    [2]i3{ -1, 2 },
    [2]i3{ 1, 2 },
    [2]i3{ 2, 1 },
};

const KingDelats = [8][2]i2{
    [2]i2{ -1, -1 },
    [2]i2{ 0, -1 },
    [2]i2{ 1, -1 },
    [2]i2{ -1, 1 },
    [2]i2{ 0, 1 },
    [2]i2{ 1, 1 },
    [2]i2{ -1, 0 },
    [2]i2{ 1, 0 },
};

// true if going down
const DiagonalDeltas = [4][2]bool{
    [2]bool{ false, false },
    [2]bool{ true, false },
    [2]bool{ false, true },
    [2]bool{ true, true },
};

pub const Move: type = struct {
    src: BB.Coord2D,
    dst: BB.Coord2d,
};

pub const MoveList: type = struct {
    quiets: u64,
    captures: u64,
    src: BB.Coord2d,
    specials: ?SpecialsArray,
};

pub const SpecialMoves: type = struct {
    dst: BB.Coord2d,
    flag: SpecialFlag,
};

pub const SpecialFlag: type = enum(u4) {
    quiet = 0b0000,

    double_pawn_push = 0b0001,

    king_castle = 0b0010,
    queen_castle = 0b0011,

    capture = 0b0100,
    en_passant_capture = 0b0101,

    knight_promotion = 0b1000,
    bishop_promotion = 0b1001,
    rook_promotion = 0b1010,
    queen_promotion = 0b1011,

    knight_promo_capture = 0b1100,
    bishop_promo_capture = 0b1101,
    rook_promo_capture = 0b1110,
    queen_promo_capture = 0b1111,
};

pub fn axis_aligned_ray_move(bb: *const BB.BitBoard, src: BB.Coord2d) struct { quiets: u64, captures: u64 } {
    BB.print_board_ansi(bb.occupancyBoard);
    var quiets: u64 = 0;
    var captures: u64 = 0;
    var currentPos: BB.Coord2d = src;
    var decreasing: bool = false;
    for (0..2) |_| {
        while (currentPos.y < 8 and currentPos.y >= 0) {
            //           std.debug.print("Y dir, X:{d} Y:{d}\n", .{ currentPos.x, currentPos.y });
            var result: u3 = 0;
            var overflowed: u1 = 0;

            if (!decreasing) {
                result, overflowed = @addWithOverflow(currentPos.y, 1);
            } else {
                result, overflowed = @subWithOverflow(currentPos.y, 1);
            }
            if (overflowed == 1) {
                std.debug.print("overflowed in y direction while going:{s}. X:{d} Y:{d}\n", .{ if (decreasing) "up" else "down", currentPos.x, currentPos.y });
                break;
            }

            currentPos.y = result;
            //          std.debug.print(" After add Y dir, X:{d} Y:{d}\n", .{ currentPos.x, currentPos.y });

            if (bb.isEmptyGeneral(currentPos)) {
                quiets |= currentPos.to_mask();
                continue;
            }

            if (bb.isEnemy(currentPos)) {
                captures |= currentPos.to_mask();
            }
            std.debug.print("breaking bcz of blocked way\n", .{});
            // pice in way
            break;
        }
        decreasing = !decreasing;
        currentPos = src;
    }

    decreasing = false;
    for (0..2) |_| {
        while (currentPos.x < 8 and currentPos.x >= 0) {
            //            std.debug.print("X dir, X:{d} Y:{d}\n", .{ currentPos.x, currentPos.y });
            var result: u3 = 0;
            var overflowed: u1 = 0;

            if (!decreasing) {
                result, overflowed = @addWithOverflow(currentPos.x, 1);
            } else {
                result, overflowed = @subWithOverflow(currentPos.x, 1);
            }

            if (overflowed == 1) {
                std.debug.print("overflowed in y direction while going:{s}. X:{d} Y:{d}\n", .{ if (decreasing) "left" else "right", currentPos.x, currentPos.y });
                break;
            }

            currentPos.x = result;

            if (bb.isEmptyGeneral(currentPos)) {
                quiets |= currentPos.to_mask();
                continue;
            }

            if (bb.isEnemy(currentPos)) {
                captures |= currentPos.to_mask();
            }
            // pice in way
            break;
        }
        decreasing = !decreasing;
        currentPos = src;
    }

    return .{ .quiets = quiets, .captures = captures };
}

test "rook moves" {
    // gen a fen where rook can move
    // gen his move
    // check if they are not zero
    var bb = try BB.BitBoard.from_fen("8/8/8/3r4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = axis_aligned_ray_move(&bb, src);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;
    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);

    try std.testing.expect(moves.quiets != 0);
}
// rook has a enemy piece in one direction
// and own piece in other dir
test "rook moves blocked" {
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3r2p1/3P4/8/8/2q w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = axis_aligned_ray_move(&bb, src);

    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);
    BB.print_board_ansi(moves.captures);
    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures != 0);
}

pub fn generateRookMoves(
    bb: *const BB.BitBoard,
    src: BB.Coord2d,
    _: ?*Allocator,
) !MoveList {
    const quiets, const captures = axis_aligned_ray_move(bb, src);
    return MoveList{
        .src = src,
        .captures = captures,
        .quiets = quiets,
        .specials = null,
    };
}

pub fn diagonal_moves(bb: *const BB.BitBoard, src: BB.Coord2d) struct { quiets: u64, captures: u64 } {
    var quiets: u64 = 0;
    var captures: u64 = 0;

    var idx: u3 = 0;
    while (idx <= 3) : (idx += 1) {
        var currentPosition = src;
        while (currentPosition.x >= 0 and currentPosition.x <= 7 and currentPosition.y >= 0 and currentPosition.y <= 7) {
            const res_x, const x_overflow = if (DiagonalDeltas[idx][0] == true) @addWithOverflow(currentPosition.x, 1) else @subWithOverflow(currentPosition.x, 1);
            const res_y, const y_overflow = if (DiagonalDeltas[idx][1] == true) @addWithOverflow(currentPosition.y, 1) else @subWithOverflow(currentPosition.y, 1);

            if (x_overflow == 1) {
                std.debug.print("overflowed x:{d} with res:{d}", .{ currentPosition.x, res_x });
                break;
            }
            if (y_overflow == 1) {
                std.debug.print("overflowed y:{d} with res:{d}", .{ currentPosition.x, res_y });
                break;
            }

            currentPosition.x = res_x;
            currentPosition.y = res_y;

            if (bb.isEmptyGeneral(currentPosition)) {
                quiets |= currentPosition.to_mask();
                continue;
            }

            if (bb.isEnemy(currentPosition)) {
                captures |= currentPosition.to_mask();
            }

            break;
        }
    }
    return .{ .quiets = quiets, .captures = captures };
}

pub fn generate_bishop_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?*Allocator) !MoveList {
    const quiets, const captures = diagonal_moves(bb, src);
    return MoveList{ .src = src, .captures = captures, .quiets = quiets, .specials = null };
}

test "diagonal_moves" {
    var bb = try BB.BitBoard.from_fen("8/8/8/3b4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = diagonal_moves(&bb, src);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;
    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);

    try std.testing.expect(moves.quiets != 0);
}

test "diagonal_moves blocked" {
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3b2p1/3P4/8/8/2q w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = diagonal_moves(&bb, src);

    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);
    BB.print_board_ansi(moves.captures);
    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures != 0);
}

pub fn generate_queen_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?*Allocator) !MoveList {
    const diagonals = diagonal_moves(bb, src);
    const axis_aligned = axis_aligned_ray_move(bb, src);
    return MoveList{
        .src = src,
        .captures = (diagonals.captures | axis_aligned.captures),
        .quiets = (diagonals.quiets | axis_aligned.quiets),
        .specials = null,
    };
}

test "queen movement" {
    std.debug.print("starting queen movement test\n", .{});
    var bb = try BB.BitBoard.from_fen("8/8/8/3q4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_queen_moves(
        &bb,
        src,
        null,
    );

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;
    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);
    BB.print_board_ansi(moves.captures);

    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures == 0);
}

test "queen moves block" {
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3q2p1/3P4/8/8/2r w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_queen_moves(
        &bb,
        src,
        null,
    );

    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);
    BB.print_board_ansi(moves.captures);
    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures != 0);
}

pub fn generate_knight_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?*Allocator) MoveList {
    var quiets: u64 = 0;
    var captures: u64 = 0;

    for (KnightDeltas) |delta| {
        var currentPosition = src;
        const x_res, const x_overflow = if (delta[0] > 0) @addWithOverflow(src.x, @as(u3, @intCast(delta[0]))) else @subWithOverflow(src.x, @as(u3, @intCast(-delta[0])));
        const y_res, const y_overflow = if (delta[1] > 0) @addWithOverflow(src.y, @as(u3, @intCast(delta[1]))) else @subWithOverflow(src.y, @as(u3, @intCast(-delta[1])));

        if (x_overflow == 1) {
            continue;
        }
        if (y_overflow == 1) {
            continue;
        }
        currentPosition.x = x_res;
        currentPosition.y = y_res;

        if (bb.isEmptyGeneral(currentPosition)) {
            quiets |= currentPosition.to_mask();
            continue;
        }

        if (bb.isEnemy(currentPosition)) {
            captures |= currentPosition.to_mask();
        }
        continue;
    }
    return MoveList{
        .src = src,
        .quiets = quiets,
        .captures = captures,
        .specials = null,
    };
}

test "test knight moves" {
    var bb = try BB.BitBoard.from_fen("8/8/8/3N4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = generate_knight_moves(&bb, src, null);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;
    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);

    try std.testing.expect(moves.quiets != 0);
}

test "test knight move blocked enemy and own" {
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/5Pp1/3N2p1/1P6/8/8/2q w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = generate_knight_moves(&bb, src, null);

    try bb.print_ansi(stdout);
    BB.print_board_ansi(moves.quiets);
    BB.print_board_ansi(moves.captures);
    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures != 0);
}
