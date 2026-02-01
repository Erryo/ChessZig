const BB = @import("bitboard.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert();

const SpecialsArray = std.ArrayList(SpecialMove);

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

const KingDeltas = [8][2]i2{
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

pub const GenerationError = error{
    NoAllocatorAvailable,
    AllocationFailed,
};

pub const Move: type = struct {
    src: BB.Coord2d,
    dst: BB.Coord2d,
};

pub const MoveList: type = struct {
    quiets: u64,
    captures: u64,
    src: BB.Coord2d,
    specials: ?SpecialsArray,
};

pub const SpecialMove: type = struct {
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
    std.debug.print("Starting test:rook moves\n", .{});
    // gen a fen where rook can move
    // gen his move
    // check if they are not zero
    var bb = try BB.BitBoard.from_fen("8/8/8/3r4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = axis_aligned_ray_move(&bb, src);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:rook moves\n", .{});
}
// rook has a enemy piece in one direction
// and own piece in other dir
test "rook moves blocked" {
    std.debug.print("Starting test:rook moves blocked\n", .{});
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3r2p1/3P4/8/8/2q w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = axis_aligned_ray_move(&bb, src);

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:rook moves blocked\n", .{});
}

pub fn generate_rook_moves(
    bb: *const BB.BitBoard,
    src: BB.Coord2d,
    _: ?Allocator,
) GenerationError!MoveList {
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
                std.debug.print("overflowed x:{d} with res:{d}\n", .{ currentPosition.x, res_x });
                break;
            }
            if (y_overflow == 1) {
                std.debug.print("overflowed y:{d} with res:{d}\n", .{ currentPosition.x, res_y });
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

pub fn generate_bishop_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator) GenerationError!MoveList {
    const quiets, const captures = diagonal_moves(bb, src);
    return MoveList{ .src = src, .captures = captures, .quiets = quiets, .specials = null };
}

test "diagonal_moves" {
    std.debug.print("Starting test:diagonal_moves\n", .{});
    var bb = try BB.BitBoard.from_fen("8/8/8/3b4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = diagonal_moves(&bb, src);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:diagonal_moves\n", .{});
}

test "diagonal_moves blocked" {
    std.debug.print("Starting test:diagonal_moves blocked\n", .{});
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3b2p1/3P4/8/8/2q b - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = diagonal_moves(&bb, src);

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:diagonal_moves blocked\n", .{});
}

pub fn generate_queen_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator) GenerationError!MoveList {
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
    std.debug.print("Starting test:queen movement \n", .{});
    var bb = try BB.BitBoard.from_fen("8/8/8/3q4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_queen_moves(
        &bb,
        src,
        null,
    );

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:queen movement \n", .{});
}

test "queen moves block" {
    std.debug.print("Started test:queen movement blocked\n", .{});
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/8/3q2p1/3P4/8/8/2r w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_queen_moves(
        &bb,
        src,
        null,
    );

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("Blocked test:queen movement blocked\n", .{});
}

pub fn generate_knight_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator) GenerationError!MoveList {
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
    std.debug.print("Started test:knight movement \n", .{});
    var bb = try BB.BitBoard.from_fen("8/8/8/3N4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_knight_moves(&bb, src, null);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.debug.print("===Passed test:knight movement \n", .{});
}

test "test knight move blocked enemy and own" {
    std.debug.print("Started test:knight movement blocked\n", .{});
    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    var bb = try BB.BitBoard.from_fen("K7/8/5Pp1/3n2p1/1P6/8/8/2q b - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_knight_moves(&bb, src, null);

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:knight movement blocked\n", .{});
}

pub fn generate_king_moves(bb: *const BB.BitBoard, src: BB.Coord2d, allocator: ?Allocator) GenerationError!MoveList {
    if (allocator == null) {
        return GenerationError.NoAllocatorAvailable;
    }
    var quiets: u64 = 0;
    var captures: u64 = 0;
    var specials: SpecialsArray = SpecialsArray.initCapacity(allocator.?, 3) catch return GenerationError.AllocationFailed;

    for (KingDeltas) |delta| {
        var currentPosition = src;
        const x_res, const x_overflow = if (delta[0] >= 0) @addWithOverflow(src.x, @as(u3, @intCast(delta[0]))) else @subWithOverflow(src.x, @as(u3, @intCast(-delta[0])));
        const y_res, const y_overflow = if (delta[1] >= 0) @addWithOverflow(src.y, @as(u3, @intCast(delta[1]))) else @subWithOverflow(src.y, @as(u3, @intCast(-delta[1])));

        if (x_overflow == 1) {
            std.debug.print("overflowed x: delta x:{d} delta y:{d}\n", .{ delta[0], delta[1] });
            continue;
        }
        if (y_overflow == 1) {
            std.debug.print("overflowed y: delta x:{d} delta y:{d}\n", .{ delta[0], delta[1] });
            continue;
        }
        currentPosition.x = x_res;
        currentPosition.y = y_res;

        if (bb.isEmptyGeneral(currentPosition)) {
            quiets = quiets | currentPosition.to_mask();
            continue;
        }

        if (bb.isEnemy(currentPosition)) {
            captures |= currentPosition.to_mask();
        }
        continue;
    }

    switch (bb.active_color) {
        .black => {
            std.debug.print("matched color for castling black\n", .{});
            if (bb.castling_rights[BB.castle_black_king]) {
                const targetSquare = BB.Coord2d{ .x = 7, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .rook = bb.active_color })) {
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 6, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 5, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.king_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                        std.debug.print("black king side castle has bees aproved", .{});
                    }
                }
            }
            if (bb.castling_rights[BB.castle_black_queen]) {
                const targetSquare = BB.Coord2d{ .x = 0, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .rook = bb.active_color })) {
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 3, .y = src.y }) and
                        bb.isEmptyGeneral(.{ .x = 2, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 1, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.queen_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                        std.debug.print("black queeen side castle has bees aproved", .{});
                    }
                }
            }
        },
        .white => {
            std.debug.print("matched color for castling white\n", .{});
            if (bb.castling_rights[BB.castle_white_king]) {
                const targetSquare = BB.Coord2d{ .x = 7, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .rook = bb.active_color })) {
                    std.debug.print("passed rook presence check\n", .{});

                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 6, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 5, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.king_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                        std.debug.print("white king side castle has bees aproved", .{});
                    }
                }
            }
            if (bb.castling_rights[BB.castle_white_queen]) {
                const targetSquare = BB.Coord2d{ .x = 0, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .rook = bb.active_color })) {
                    std.debug.print("passed rook presence check\n", .{});
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 3, .y = src.y }) and
                        bb.isEmptyGeneral(.{ .x = 2, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 1, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.queen_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                        std.debug.print("white queeen side castle has bees aproved", .{});
                    }
                }
            }
        },
    }

    return MoveList{
        .src = src,
        .quiets = quiets,
        .captures = captures,
        .specials = specials,
    };
}

test "king simple moves" {
    std.debug.print("Started test:king movement \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/3K4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_king_moves(&bb, src, allocator);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:king movement \n", .{});
}

test "test king castle " {
    std.debug.print("Started test:king castle \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    const src = BB.Coord2d{ .x = 4, .y = 7 };
    const moves = try generate_king_moves(&bb, src, allocator);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    const specis = moves.specials.?;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(specis.items.len == 2) catch |err| {
        bb.print_ansi(stdout) catch {};
        std.debug.print("specials len:{d} for  {any}\n", .{ moves.specials.?.items.len, moves.specials.?.items });
        return err;
    };
    std.debug.print("===Passed test:king castle \n", .{});
}

pub fn generate_pawn_moves(bb: *const BB.BitBoard, src: BB.Coord2d, allocator: ?Allocator) GenerationError!MoveList {
    if (allocator == null) {
        return GenerationError.NoAllocatorAvailable;
    }

    var quiets: u64 = 0;
    var captures: u64 = 0;

    const direction_down: bool = (bb.active_color == BB.Color.black);
    const home_row: u3 = if (bb.active_color == BB.Color.black) 1 else 6;

    const predicted_capacity: usize = if (src.y == 7 - home_row) 4 else 1;

    var specials = SpecialsArray.initCapacity(allocator.?, predicted_capacity) catch return GenerationError.AllocationFailed;

    var moves: MoveList = .{ .specials = specials, .src = src, .captures = captures, .quiets = quiets };

    if (direction_down and src.y == 7) return moves;
    if (!direction_down and src.y == 0) return moves;

    const single_push = if (direction_down) src.y + 1 else src.y - 1;
    if (src.x < 7) {
        const targetSquare = BB.Coord2d{ .x = src.x + 1, .y = single_push };
        if (bb.en_passant.x == targetSquare.x and bb.en_passant.y == targetSquare.y) {
            //            std.debug.print("passed target check\n", .{});
            if (bb.isEmptyGeneral(targetSquare)) {
                //std.debug.print("passed is empty; enemy {s} {s} at X{d} Y{d}\n", .{ if (bb.active_color == BB.Color.white) "black" else "white", if (bb.isEnemy(.{ .x = targetSquare.x, .y = src.y })) "is" else "is not", targetSquare.x, src.y });

                //std.debug.print("X:{c} Y:{c}\n", .{ @as(u8, targetSquare.x) + 97, @as(u8, 8) - src.y + 48 });
                //         BB.print_board_ansi(bb.pawns.black | BB.coord_to_mask(targetSquare.x, src.y));
                if (bb.isEnemy(.{ .x = targetSquare.x, .y = src.y })) {
                    //std.debug.print("passed is enemy\n", .{});
                    const specialMove = SpecialMove{
                        .dst = targetSquare,
                        .flag = SpecialFlag.en_passant_capture,
                    };
                    specials.append(allocator.?, specialMove) catch return GenerationError.AllocationFailed;
                }
            }
        }
    }
    if (src.x >= 1) {
        const targetSquare = BB.Coord2d{ .x = src.x - 1, .y = single_push };
        if (bb.en_passant.x == targetSquare.x and bb.en_passant.y == targetSquare.y) {
            //            std.debug.print("passed target check\n", .{});
            if (bb.isEmptyGeneral(targetSquare)) {
                //               std.debug.print("passed is empty; enemy at X{d} Y{d}\n", .{ targetSquare.x, src.y });
                // LOOK OUT: see commit 'fixed en pasant' in ChessWeb go version if
                // en passant doesnt work
                if (bb.isEnemy(.{ .x = targetSquare.x, .y = src.y })) {
                    //                   std.debug.print("passed is enemy\n", .{});
                    const specialMove = SpecialMove{
                        .dst = targetSquare,
                        .flag = SpecialFlag.en_passant_capture,
                    };
                    specials.append(allocator.?, specialMove) catch return GenerationError.AllocationFailed;
                }
            }
        }
    }

    // normal  taking

    if (src.x < 7) {
        const targetSquare = BB.Coord2d{ .x = src.x + 1, .y = single_push };
        if (!bb.isEmptyGeneral(targetSquare) and bb.isEnemy(targetSquare)) {
            // 7 - 6 = 1
            // 7 - 1 = 6
            if (src.y == 7 - home_row) {
                const promCapQueen = SpecialMove{ .dst = targetSquare, .flag = .queen_promo_capture };
                const promCapRook = SpecialMove{ .dst = targetSquare, .flag = .rook_promo_capture };
                const promCapBishop = SpecialMove{ .dst = targetSquare, .flag = .bishop_promo_capture };
                const promCapKnight = SpecialMove{ .dst = targetSquare, .flag = .knight_promo_capture };
                if (specials.capacity > specials.items.len + 4) {
                    specials.appendSlice(allocator.?, &[_]SpecialMove{ promCapQueen, promCapRook, promCapBishop, promCapKnight }) catch return GenerationError.AllocationFailed;
                }
            } else {
                captures |= targetSquare.to_mask();
            }
        }
    }
    if (src.x >= 1) {
        const targetSquare = BB.Coord2d{ .x = src.x - 1, .y = single_push };
        if (!bb.isEmptyGeneral(targetSquare) and bb.isEnemy(targetSquare)) {
            // 7 - 6 = 1
            // 7 - 1 = 6
            if (src.y == 7 - home_row) {
                const promCapQueen = SpecialMove{ .dst = targetSquare, .flag = .queen_promo_capture };
                const promCapRook = SpecialMove{ .dst = targetSquare, .flag = .rook_promo_capture };
                const promCapBishop = SpecialMove{ .dst = targetSquare, .flag = .bishop_promo_capture };
                const promCapKnight = SpecialMove{ .dst = targetSquare, .flag = .knight_promo_capture };
                specials.appendSlice(allocator.?, &[_]SpecialMove{ promCapQueen, promCapRook, promCapBishop, promCapKnight }) catch return GenerationError.AllocationFailed;
            } else {
                captures |= targetSquare.to_mask();
            }
        }
    }

    const singlePushSquare: BB.Coord2d = .{ .x = src.x, .y = single_push };
    if (!bb.isEmptyGeneral(singlePushSquare)) {
        moves.captures = captures;
        moves.specials = specials;
        return moves;
    }

    if (src.y == 7 - home_row) {
        const promCapQueen = SpecialMove{ .dst = singlePushSquare, .flag = .queen_promotion };
        const promCapRook = SpecialMove{ .dst = singlePushSquare, .flag = .rook_promotion };
        const promCapBishop = SpecialMove{ .dst = singlePushSquare, .flag = .bishop_promotion };
        const promCapKnight = SpecialMove{ .dst = singlePushSquare, .flag = .knight_promotion };
        specials.appendSlice(allocator.?, &[_]SpecialMove{ promCapQueen, promCapRook, promCapBishop, promCapKnight }) catch return GenerationError.AllocationFailed;
    } else {
        quiets |= singlePushSquare.to_mask();
    }

    if (src.y == home_row) {
        const double_push, const overflowed = if (direction_down) @addWithOverflow(src.y, 2) else @subWithOverflow(src.y, 2);
        if (overflowed == 0) {
            const douplePushSquare: BB.Coord2d = .{
                .x = src.x,
                .y = double_push,
            };
            std.debug.print("douplePushSquare is X:{d} Y{d}\n", .{ douplePushSquare.x, douplePushSquare.y });
            if (bb.isEmptyGeneral(douplePushSquare)) {
                std.debug.print("appening double_pawn_push\n", .{});
                const douplePushMove = SpecialMove{ .dst = douplePushSquare, .flag = .double_pawn_push };
                specials.append(allocator.?, douplePushMove) catch return GenerationError.AllocationFailed;
            }
        } else {
            @panic("double_pawn_push overflowed when it should not");
        }
    }
    moves.captures = captures;
    moves.specials = specials;
    moves.quiets = quiets;

    return moves;
}

test "pawn moves single push and capture" {
    std.debug.print("Started test:pawn single and catpure \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/3p4/2P5/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 2, .y = 4 };
    const moves = try generate_pawn_moves(&bb, src, allocator);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:pawn single and catpure \n", .{});
}

test "pawn double_pawn_push" {
    std.debug.print("Started test:pawn double_pawn_push \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/8/8/8/PP6/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 0, .y = 6 };
    const moves = try generate_pawn_moves(&bb, src, allocator);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.specials.?.items.len == 1) catch |err| {
        bb.print_ansi(stdout) catch {};
        std.debug.print("special moves:{any}\n", .{moves.specials.?});
        return err;
    };
    std.debug.print("===Passed test:pawn double_pawn_push \n", .{});
}

test "en passant capture" {
    std.debug.print("Started test:pawn en_passant \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/3Pp3/8/8/8/8 w - e6 0 1");

    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = try generate_pawn_moves(&bb, src, allocator);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_ansi(moves.quiets);
        return err;
    };
    std.testing.expect(moves.specials.?.items.len == 1) catch |err| {
        bb.print_ansi(stdout) catch {};
        std.debug.print("special moves:{any}\n", .{moves.specials.?});
        return err;
    };
    std.debug.print("===Passed test:pawn en_passant \n", .{});
}
