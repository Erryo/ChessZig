const BB = @import("bitboard.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const SpeicalArray = std.ArrayList(SpecialMoves);

pub const Move: type = struct {
    src: BB.Coord2D,
    dst: BB.Coord2d,
};

pub const MoveList: type = struct {
    quiets: u64,
    captures: u64,
    src: BB.Coord2d,
    specials: []SpecialMoves,
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
    BB.print_board_debug(bb.occupancyBoard);
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
    try bb.print(stdout);
    BB.print_board_debug(moves.quiets);

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

    try bb.print(stdout);
    BB.print_board_debug(moves.quiets);
    BB.print_board_debug(moves.captures);
    try std.testing.expect(moves.quiets != 0);
    try std.testing.expect(moves.captures != 0);
}

//pub fn generateRookMoves(
//    bb: *const BB.BitBoard,
//    src: BB.Coord2d,
//    allocator: *Allocator,
//) MoveList {}
