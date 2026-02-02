const BB = @import("bitboard.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert();

pub const SpecialsArray = std.ArrayList(SpecialMove);

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

pub const ParsingError = error{
    InvalidLength,
    InvalidCoordinate,
    InvalidCharacter,
};

pub const moveGenFn = *const fn (*const BB.BitBoard, BB.Coord2d, ?Allocator, ?SpecialsArray) GenerationError!MoveList;

pub const Move: type = struct {
    src: BB.Coord2d,
    dst: BB.Coord2d,
    piece: BB.Piece,
    flag: SpecialFlag,
    undo: ?Undo,

    pub fn from_UCI(bb: *const BB.BitBoard, uci: []const u8) ParsingError!Move {
        if (uci.len != 5 and uci.len != 4)
            return ParsingError.InvalidLength;

        if (!(uci[1] >= '1' and uci[1] <= '8'))
            return ParsingError.InvalidCoordinate;

        if (!(uci[3] >= '1' and uci[3] <= '8'))
            return ParsingError.InvalidCoordinate;

        if (!(uci[0] >= 'a' and uci[0] <= 'h'))
            return ParsingError.InvalidCoordinate;

        if (!(uci[2] >= 'a' and uci[2] <= 'h'))
            return ParsingError.InvalidCoordinate;

        const src: BB.Coord2d = .{ .x = @intCast(uci[0] - 'a'), .y = 7 - @as(u3, @intCast(uci[1] - '1')) };
        const dst: BB.Coord2d = .{ .x = @intCast(uci[2] - 'a'), .y = 7 - @as(u3, @intCast(uci[3] - '1')) };

        if (bb.isEmptyGeneral(src)) return ParsingError.InvalidCoordinate;

        const piece: BB.Piece = bb.getGeneral(src);
        const flag: SpecialFlag = try Move.generate_flag(bb, src, dst, piece, uci);

        return .{
            .src = src,
            .dst = dst,
            .piece = piece,
            .flag = flag,
            .undo = null,
        };
    }

    fn generate_flag(bb: *const BB.BitBoard, src: BB.Coord2d, dst: BB.Coord2d, piece: BB.Piece, uci: []const u8) ParsingError!SpecialFlag {
        if (uci.len == 5) {
            if (!bb.isEmptyGeneral(dst)) {
                switch (uci[4]) {
                    'r', 'R' => return SpecialFlag.rook_capture_promotion,
                    'b', 'B' => return SpecialFlag.bishop_capture_promotion,
                    'n', 'N' => return SpecialFlag.knight_capture_promotion,

                    'q',
                    'Q',
                    => return SpecialFlag.queen_capture_promotion,
                    else => return ParsingError.InvalidCharacter,
                }
            }
            switch (uci[4]) {
                'r', 'R' => return SpecialFlag.rook_promotion,
                'b', 'B' => return SpecialFlag.bishop_promotion,
                'n', 'N' => return SpecialFlag.knight_promotion,

                'q',
                'Q',
                => return SpecialFlag.queen_promotion,
                else => return ParsingError.InvalidCharacter,
            }
        }

        if (piece.kind == .king and bb.isPieceAndOwn(dst, .{ .color = piece.color, .kind = .rook })) {
            if (src.y != dst.y) return ParsingError.InvalidCoordinate;

            if (dst.x == 0) {
                return SpecialFlag.queen_castle;
            } else if (dst.x == 7) {
                return SpecialFlag.king_castle;
            } else return ParsingError.InvalidCoordinate;
        }

        if (piece.kind == .pawn) {
            const home_row: u3 = if (piece.color == .white) 6 else 1;
            const going_down: bool = if (piece.color == .white) false else true;

            // double_pawn_push
            if (src.y == home_row) {
                const doublePushY, const overflow = if (going_down) @addWithOverflow(src.y, 2) else @subWithOverflow(src.y, 2);
                if (overflow == 1) return ParsingError.InvalidCoordinate;

                if (doublePushY == dst.x) return SpecialFlag.double_pawn_push;
            }

            if (bb.isEmptyGeneral(dst)) {
                const ep_capture_y, const overflow_y = if (going_down) @addWithOverflow(src.y, 1) else @subWithOverflow(src.y, 1);
                //if (overflow_y) return ParsingError.InvalidCoordinate;
                if (overflow_y == 0) {
                    // left
                    const x_left, const overflow_left = @subWithOverflow(src.x, 1);
                    if (overflow_left == 0) {
                        if (dst.x == x_left and dst.y == ep_capture_y) {
                            if (bb.isEnemy(.{ .x = dst.x, .y = src.y })) {
                                return SpecialFlag.en_passant_capture;
                            }
                        }
                    }

                    // right
                    const x_right, const overflow_right = @addWithOverflow(src.x, 1);
                    if (overflow_right == 0) {
                        if (dst.x == x_right and dst.y == ep_capture_y) {
                            if (bb.isEnemy(.{ .x = dst.x, .y = src.y })) {
                                return SpecialFlag.en_passant_capture;
                            }
                        }
                    }
                }
            }
        }

        if (!bb.isEmptyGeneral(dst)) return SpecialFlag.capture;

        return SpecialFlag.quiet;
    }
};

pub const Undo = struct {
    active_color: BB.Color,
    captured_piece: ?BB.Piece,

    en_passant: BB.Coord2d,
    castling_rights: [4]bool,

    half_move: u16,
    full_move: u16,
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
    quiet,
    double_pawn_push,
    king_castle,
    queen_castle,
    capture,
    en_passant_capture,

    knight_promotion,
    bishop_promotion,
    rook_promotion,
    queen_promotion,

    knight_capture_promotion,
    bishop_capture_promotion,
    rook_capture_promotion,
    queen_capture_promotion,

    pub fn to_promotion_piece(flag: *const SpecialFlag, color: BB.Color) BB.Piece {
        switch (flag.*) {
            .knight_promotion, .knight_capture_promotion => return .{ .kind = .knight, .color = color },
            .bishop_promotion, .bishop_capture_promotion => return .{ .kind = .bishop, .color = color },
            .rook_promotion, .rook_capture_promotion => return .{ .kind = .rook, .color = color },
            .queen_promotion, .queen_capture_promotion => return .{ .kind = .queen, .color = color },
            else => unreachable,
        }
    }
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
    var bb = try BB.BitBoard.from_fen("8/8/8/3r4/8/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 3, .y = 3 };
    const moves = axis_aligned_ray_move(&bb, src);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
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
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:rook moves blocked\n", .{});
}

pub fn generate_rook_moves(
    bb: *const BB.BitBoard,
    src: BB.Coord2d,
    _: ?Allocator,
    _: ?SpecialsArray,
) GenerationError!MoveList {
    const moves = axis_aligned_ray_move(bb, src);
    return MoveList{
        .src = src,
        .captures = moves.captures,
        .quiets = moves.quiets,
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
            const res_x, const x_overflow = if (DiagonalDeltas[idx][0] == true)
                @addWithOverflow(currentPosition.x, 1)
            else
                @subWithOverflow(currentPosition.x, 1);

            if (x_overflow == 1) {
                //std.debug.print("overflowed x:{d} with res:{d}\n", .{ currentPosition.x, res_x });
                break;
            }

            const res_y, const y_overflow = if (DiagonalDeltas[idx][1] == true)
                @addWithOverflow(currentPosition.y, 1)
            else
                @subWithOverflow(currentPosition.y, 1);

            if (y_overflow == 1) {
                //std.debug.print("overflowed y:{d} with res:{d}\n", .{ currentPosition.x, res_y });
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

pub fn generate_bishop_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator, _: ?SpecialsArray) GenerationError!MoveList {
    const moves = diagonal_moves(bb, src);
    return MoveList{ .src = src, .captures = moves.captures, .quiets = moves.quiets, .specials = null };
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
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
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
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:diagonal_moves blocked\n", .{});
}

pub fn generate_queen_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator, _: ?SpecialsArray) GenerationError!MoveList {
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
        null,
    );

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
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
        null,
    );

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
        return err;
    };
    std.debug.print("Blocked test:queen movement blocked\n", .{});
}

pub fn generate_knight_moves(bb: *const BB.BitBoard, src: BB.Coord2d, _: ?Allocator, _: ?SpecialsArray) GenerationError!MoveList {
    var quiets: u64 = 0;
    var captures: u64 = 0;

    for (KnightDeltas) |delta| {
        var currentPosition = src;
        const x_res, const x_overflow = if (delta[0] > 0)
            @addWithOverflow(src.x, @as(u3, @intCast(delta[0])))
        else
            @subWithOverflow(src.x, @as(u3, @intCast(-delta[0])));

        if (x_overflow == 1) {
            continue;
        }

        const y_res, const y_overflow = if (delta[1] > 0)
            @addWithOverflow(src.y, @as(u3, @intCast(delta[1])))
        else
            @subWithOverflow(src.y, @as(u3, @intCast(-delta[1])));

        if (y_overflow == 2) {
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
    const moves = try generate_knight_moves(&bb, src, null, null);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
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
    const moves = try generate_knight_moves(&bb, src, null, null);

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
        return err;
    };
    std.debug.print("===Passed test:knight movement blocked\n", .{});
}

pub fn generate_king_moves(bb: *const BB.BitBoard, src: BB.Coord2d, allocator: ?Allocator, specials_array: ?SpecialsArray) GenerationError!MoveList {
    if (allocator == null or specials_array == null) {
        return GenerationError.NoAllocatorAvailable;
    }
    var quiets: u64 = 0;
    var captures: u64 = 0;
    var specials: SpecialsArray = specials_array.?;

    for (KingDeltas) |delta| {
        var currentPosition = src;
        const x_res, const x_overflow = if (delta[0] >= 0)
            @addWithOverflow(src.x, @as(u3, @intCast(delta[0])))
        else
            @subWithOverflow(src.x, @as(u3, @intCast(-delta[0])));

        if (x_overflow == 1) {
            //std.debug.print("overflowed x: delta x:{d} delta y:{d}\n", .{ delta[0], delta[1] });
            continue;
        }

        const y_res, const y_overflow = if (delta[1] >= 0)
            @addWithOverflow(src.y, @as(u3, @intCast(delta[1])))
        else
            @subWithOverflow(src.y, @as(u3, @intCast(-delta[1])));

        if (y_overflow == 1) {
            //std.debug.print("overflowed y: delta x:{d} delta y:{d}\n", .{ delta[0], delta[1] });
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
            if (bb.castling_rights[BB.castle_black_king]) {
                const targetSquare = BB.Coord2d{ .x = 7, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .kind = .rook, .color = bb.active_color })) {
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 6, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 5, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.king_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                    }
                }
            }
            if (bb.castling_rights[BB.castle_black_queen]) {
                const targetSquare = BB.Coord2d{ .x = 0, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .kind = .rook, .color = bb.active_color })) {
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 3, .y = src.y }) and
                        bb.isEmptyGeneral(.{ .x = 2, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 1, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.queen_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                    }
                }
            }
        },
        .white => {
            if (bb.castling_rights[BB.castle_white_king]) {
                const targetSquare = BB.Coord2d{ .x = 7, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .kind = .rook, .color = bb.active_color })) {
                    const clearWay: bool = bb.isEmptyGeneral(.{ .x = 6, .y = src.y }) and bb.isEmptyGeneral(.{ .x = 5, .y = src.y });

                    if (clearWay) {
                        const special_move = SpecialMove{ .dst = targetSquare, .flag = SpecialFlag.king_castle };
                        specials.append(allocator.?, special_move) catch return GenerationError.AllocationFailed;
                    }
                }
            }
            if (bb.castling_rights[BB.castle_white_queen]) {
                const targetSquare = BB.Coord2d{ .x = 0, .y = src.y };
                if (bb.isPieceAndOwn(targetSquare, .{ .kind = .rook, .color = bb.active_color })) {
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
    var specials = try SpecialsArray.initCapacity(allocator, 1);
    defer specials.deinit(allocator);
    const moves = try generate_king_moves(&bb, src, allocator, specials);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures == 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
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
    var specials = try SpecialsArray.initCapacity(allocator, 1);
    defer specials.deinit(allocator);
    const moves = try generate_king_moves(&bb, src, allocator, specials);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    const specis = moves.specials.?;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(specis.items.len == 2) catch |err| {
        bb.print_ansi(stdout) catch {};
        std.debug.print("specials len:{d} for  {any}\n", .{ moves.specials.?.items.len, moves.specials.?.items });
        return err;
    };
    std.debug.print("===Passed test:king castle \n", .{});
}

pub fn generate_pawn_moves(bb: *const BB.BitBoard, src: BB.Coord2d, allocator: ?Allocator, special_array: ?SpecialsArray) GenerationError!MoveList {
    if (allocator == null or special_array == null) {
        return GenerationError.NoAllocatorAvailable;
    }

    var quiets: u64 = 0;
    var captures: u64 = 0;

    const direction_down: bool = (bb.active_color == BB.Color.black);
    const home_row: u3 = if (bb.active_color == BB.Color.black) 1 else 6;

    var specials = special_array.?;

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
                //         BB.print_ansi_debug(bb.pawns.black | BB.coord_to_mask(targetSquare.x, src.y));
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
                const promCapQueen = SpecialMove{ .dst = targetSquare, .flag = .queen_capture_promotion };
                const promCapRook = SpecialMove{ .dst = targetSquare, .flag = .rook_capture_promotion };
                const promCapBishop = SpecialMove{ .dst = targetSquare, .flag = .bishop_capture_promotion };
                const promCapKnight = SpecialMove{ .dst = targetSquare, .flag = .knight_capture_promotion };
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
                const promCapQueen = SpecialMove{ .dst = targetSquare, .flag = .queen_capture_promotion };
                const promCapRook = SpecialMove{ .dst = targetSquare, .flag = .rook_capture_promotion };
                const promCapBishop = SpecialMove{ .dst = targetSquare, .flag = .bishop_capture_promotion };
                const promCapKnight = SpecialMove{ .dst = targetSquare, .flag = .knight_capture_promotion };
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
            if (bb.isEmptyGeneral(douplePushSquare)) {
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

pub fn generate_piece_all_moves(bb: *const BB.BitBoard, piece: BB.Piece, allocator: Allocator) GenerationError!MoveList {
    var all_moves: MoveList = .{ .specials = null, .captures = 0, .quiets = 0, .src = .{ .x = 0, .y = 0 } };
    var moveFn: moveGenFn = undefined;
    var board: u64 = undefined;

    var all_specials = SpecialsArray.initCapacity(allocator, 1) catch return GenerationError.AllocationFailed;
    switch (piece.kind) {
        .pawn => {
            moveFn = generate_pawn_moves;
            if (bb.active_color == .white) board = bb.pawns.white else board = bb.pawns.black;
        },
        .knight => {
            moveFn = generate_knight_moves;
            if (bb.active_color == .white) board = bb.knights.white else board = bb.knights.black;
        },
        .bishop => {
            moveFn = generate_bishop_moves;
            if (bb.active_color == .white) board = bb.bishops.white else board = bb.bishops.black;
        },
        .rook => {
            moveFn = generate_rook_moves;
            if (bb.active_color == .white) board = bb.rooks.white else board = bb.rooks.black;
        },
        .queen => {
            moveFn = generate_queen_moves;
            if (bb.active_color == .white) board = bb.queens.white else board = bb.queens.black;
        },
        .king => {
            moveFn = generate_king_moves;
            if (bb.active_color == .white) board = bb.kings.white else board = bb.kings.black;
        },
    }
    //for (specials.items) |sp_move| {
    //    switch (sp_move.flag) {
    //        .knight_capture_promotion, .bishop_capture_promotion, .queen_capture_promotion, .rook_capture_promotion, .capture, .en_passant_capture => {
    //            all_moves.captures |= sp_move.dst.to_mask();
    //        },
    //        else => {
    //            all_moves.quiets |= sp_move.dst.to_mask();
    //        },
    //    }
    //    //                TODO: Bring back promotion capture
    //}

    while (board != 0) {
        const src = BB.Coord2d.pop_and_get_lsb(&board);
        const moves = try moveFn(bb, src, allocator, all_specials);
        all_moves.quiets |= moves.quiets;
        all_moves.captures |= moves.captures;
    }

    if (all_specials.items.len == 0) {
        all_specials.deinit(allocator);
        all_moves.specials = null;
    } else {
        all_moves.specials = all_specials;
    }

    return all_moves;
}

test "generate piece all moves" {
    std.debug.print("Started test:generate piece all moves \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/3p4/2P5/8/8/8 w - - 0 1");

    var moves: MoveList = try generate_piece_all_moves(&bb, .{ .kind = .pawn, .color = bb.active_color }, allocator);
    BB.print_board_debug(moves.quiets);
    BB.print_board_debug(moves.captures);
    if (moves.specials) |*spcs| {
        spcs.deinit(allocator);
    }

    std.debug.print("===Passed test:generate piece all moves \n", .{});
}

test "pawn moves single push and capture" {
    std.debug.print("Started test:pawn single and catpure \n", .{});
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/3p4/2P5/8/8/8 w - - 0 1");
    const src = BB.Coord2d{ .x = 2, .y = 4 };
    var specials = try SpecialsArray.initCapacity(allocator, 1);
    defer specials.deinit(allocator);
    const moves = try generate_pawn_moves(&bb, src, allocator, specials);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.captures != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.captures);
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
    var specials = try SpecialsArray.initCapacity(allocator, 1);
    defer specials.deinit(allocator);
    const moves = try generate_pawn_moves(&bb, src, allocator, specials);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
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
    var specials = try SpecialsArray.initCapacity(allocator, 1);
    defer specials.deinit(allocator);
    const moves = try generate_pawn_moves(&bb, src, allocator, specials);

    var writer = std.fs.File.stdout().writer(&.{});
    const stdout = &writer.interface;

    std.testing.expect(moves.quiets != 0) catch |err| {
        bb.print_ansi(stdout) catch {};
        BB.print_board_debug(moves.quiets);
        return err;
    };
    std.testing.expect(moves.specials.?.items.len == 1) catch |err| {
        bb.print_ansi(stdout) catch {};
        std.debug.print("special moves:{any}\n", .{moves.specials.?});
        return err;
    };
    std.debug.print("===Passed test:pawn en_passant \n", .{});
}

test "uci to move: e2e4" {
    std.debug.print("Started test:uci to move e2e4 \n", .{});
    //    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    //    defer arena.deinit();
    //    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/8/8/8/PPPPPPPP/8 w - - 0 1");

    const move = try Move.from_UCI(&bb, "e2e4");

    std.testing.expect(move.src.x == 4 and move.src.y == 6) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(move.flag == SpecialFlag.double_pawn_push) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move e2e4 \n", .{});
}

test "uci capture" {
    std.debug.print("Started test:uci to move capture \n", .{});
    //    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    //    defer arena.deinit();
    //    const allocator = arena.allocator();

    var bb = try BB.BitBoard.from_fen("8/8/8/8/8/3p4/PPPPPPPP/8 w - - 0 1");

    const move = try Move.from_UCI(&bb, "e2d3");

    std.testing.expect(move.src.x == 4 and move.src.y == 6) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.testing.expect(move.flag == SpecialFlag.capture) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move capture \n", .{});
}

test "uci to move en passant capture" {
    std.debug.print("Started test:uci to move en passant \n", .{});

    var bb = try BB.BitBoard.from_fen("8/8/8/3Pp3/8/8/8/8 w - e6 0 1");

    const move = try Move.from_UCI(&bb, "d5e6");

    std.testing.expect(move.src.x == 3 and move.src.y == 3) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.testing.expect(move.flag == SpecialFlag.en_passant_capture) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move en passant \n", .{});
}

test "uci to move castle king" {
    std.debug.print("Started test:uci to move castle king \n", .{});

    var bb = try BB.BitBoard.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");

    const move = try Move.from_UCI(&bb, "e1h1");

    std.testing.expect(move.src.x == 4 and move.src.y == 7) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.testing.expect(move.flag == SpecialFlag.king_castle) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move castle king \n", .{});
}
test "uci to move castle queen" {
    std.debug.print("Started test:uci to move castle queen \n", .{});

    var bb = try BB.BitBoard.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");

    const move = try Move.from_UCI(&bb, "e1a1");

    std.testing.expect(move.src.x == 4 and move.src.y == 7) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.testing.expect(move.flag == SpecialFlag.queen_castle) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move castle queen \n", .{});
}

test "uci to move: promote" {
    std.debug.print("Started test:uci to move promote \n", .{});

    var bb = try BB.BitBoard.from_fen("8/8/8/8/8/8/p7/8 b - - 0 1");

    const move = try Move.from_UCI(&bb, "a2a1q");

    std.testing.expect(move.src.x == 0 and move.src.y == 6) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(move.flag == SpecialFlag.queen_promotion) catch |err| {
        std.debug.print("flag is {s}\n", .{@tagName(move.flag)});
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:uci to move promote \n", .{});
}
