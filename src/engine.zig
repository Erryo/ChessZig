const std = @import("std");
const MoveGen = @import("moveGen.zig");
const BB = @import("bitboard.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn make_move_position(bb: *BB.BitBoard, move: *const MoveGen.Move) void {
    bb.en_passant = .{ .x = 0, .y = 0 };
    switch (move.piece) {
        .knight, .bishop, .queen => {
            bb.storeGeneral(move.dst, move.piece);
            bb.removeGeneral(move.src);
        },
        .pawn => {
            bb.storePiece(bb.pawns, move.dst, move.piece);
            bb.removeGeneral(move.src);
            switch (move.flag) {
                .en_passant_capture => {
                    const coord_y, const overflowed = if (bb.active_color == .white) @addWithOverflow(move.dst.y, 1) else @subWithOverflow(move.dst.y, 1);
                    if (overflowed) {
                        std.debug.panic("en passant captures overflowed, move not properly sanatized\n", .{});
                    }
                    bb.removeGeneral(.{ move.dst.x, coord_y });
                },
                .double_pawn_push => {
                    const coord_y, const overflowed = if (bb.active_color == .white) @addWithOverflow(move.dst.y, 1) else @subWithOverflow(move.dst.y, 1);
                    if (overflowed) {
                        std.debug.panic("double_pawn_push overflowed, move not properly sanatized\n", .{});
                    }

                    bb.en_passant = .{ .x = move.src.x, .y = coord_y };
                },
                .bishop_promo_capture, .knight_promo_capture, .rook_promo_capture, .queen_promo_capture, .bishop_promotion, .knight_promotion, .rook_promotion, .queen_promotion => {
                    bb.removeGeneral(move.src);
                    bb.storeGeneral(move.dst, move.flag.flag_to_promotion(bb.active_color));
                },
                else => {},
            }
        },
        .king => {
            switch (move.flag) {
                .quiet, .capture => {
                    bb.storePiece(bb.kings, move.dst, move.piece);
                    bb.removeGeneral(move.src);
                },
                .king_castle => {
                    bb.storePiece(bb.kings, .{ .x = 6, .y = move.src.y }, move.piece);
                    bb.removeGeneral(move.src);

                    const rookPiece = bb.getPiece(.{ .x = 7, .y = move.src.y }, .{ .rook = bb.active_color });
                    bb.storePiece(bb.rooks, .{ .x = 5, .y = move.src.y }, rookPiece);
                    bb.removeGeneral(.{ .x = 7, .y = move.src.y });
                },
                .queen_castle => {
                    bb.storePiece(bb.kings, .{ .x = 2, .y = move.src.y }, move.piece);
                    bb.removeGeneral(move.src);

                    const rookPiece = bb.getPiece(.{ .x = 0, .y = move.src.y }, .{ .rook = bb.active_color });
                    bb.storePiece(bb.rooks, .{ .x = 3, .y = move.src.y }, rookPiece);
                    bb.removeGeneral(.{ .x = 0, .y = move.src.y });
                },
                else => {},
            }
            if (bb.active_color == .white) {
                bb.castling_rights[BB.castle_white_king] = false;
                bb.castling_rights[BB.castle_white_queen] = false;
            } else {
                bb.castling_rights[BB.castle_black_king] = false;
                bb.castling_rights[BB.castle_black_queen] = false;
            }
        },
        .rook => |rook| {
            bb.storePiece(bb.rooks, move.dst, move.piece);
            bb.removeGeneral(move.src);

            if (rook == .white) {
                if (move.src.x == 0) {
                    bb.castling_rights[BB.castle_white_queen] = false;
                } else {
                    bb.castling_rights[BB.castle_white_king] = false;
                }
            }
            if (rook == .black) {
                if (move.src.x == 0) {
                    bb.castling_rights[BB.castle_black_queen] = false;
                } else {
                    bb.castling_rights[BB.castle_black_king] = false;
                }
            }
        },
    }
}

pub fn make_move(bb: *BB.BitBoard, move: *const MoveGen.Move) !void {
    _ = bb;
    _ = move;
}

pub fn unmake_move(bb: *BB.BitBoard, move: *const MoveGen.Move) !void {
    _ = bb;
    _ = move;
}

pub fn pseudo_check(bb: *BB.BitBoard, move: MoveGen.Move, allocator: Allocator) !bool {
    var moveFn: *const fn (*const BB.BitBoard, BB.Coord2d, ?Allocator) MoveGen.GenerationError!MoveGen.MoveList = undefined;
    switch (move.piece) {
        .pawn => moveFn = MoveGen.generate_pawn_moves,
        .knight => moveFn = MoveGen.generate_knight_moves,
        .bishop => moveFn = MoveGen.generate_bishop_moves,
        .rook => moveFn = MoveGen.generate_rook_moves,
        .queen => moveFn = MoveGen.generate_queen_moves,
        .king => moveFn = MoveGen.generate_king_moves,
    }

    // var because deinit'ing specials
    var possibleMoves = try moveFn(bb, move.src, allocator);

    const dst_mask = move.dst.to_mask();
    if (possibleMoves.quiets & dst_mask != 0) {
        return true;
    }
    if (possibleMoves.captures & dst_mask != 0) {
        return true;
    }

    if (possibleMoves.specials == null) {
        return false;
    }
    defer possibleMoves.specials.?.deinit(allocator);

    for (possibleMoves.specials.?.items) |special| {
        if (special.dst.x == move.dst.x and special.dst.y == move.dst.y) {
            return true;
        }
    }

    return false;
}

pub fn full_check(bb: *BB.BitBoard, move: MoveGen.Move) bool {
    _ = bb;
    _ = move;
    return true;
}

test "pseudo_check " {
    std.debug.print("Started test:pseudo_check \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer std.testing.expect(gpa.deinit() == .ok) catch |err| {
        std.debug.print("failed to deinit gpa: {any}\n", .{err});
    };

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    const move = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .knight = .white },
        .src = .{ .x = 1, .y = 7 },
        .dst = .{ .x = 2, .y = 5 },
    };

    const result = try pseudo_check(&bb, move, allocator);
    std.testing.expect(result == true) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.debug.print("===Passed test:pseudo_check \n", .{});
}

test "pseudo_check illegal moves " {
    std.debug.print("Started test:pseudo_check illegal moves\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer std.testing.expect(gpa.deinit() == .ok) catch |err| {
        std.debug.print("failed to deinit gpa: {any}\n", .{err});
    };

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    const m1 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .knight = .white },
        .src = BB.Coord2d{ .x = 1, .y = 7 },
        .dst = BB.Coord2d{ .x = 3, .y = 7 },
    };

    const m2 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .bishop = .white },
        .src = BB.Coord2d{ .x = 2, .y = 7 },
        .dst = BB.Coord2d{ .x = 3, .y = 7 },
    };
    const m3 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .pawn = .white },
        .src = BB.Coord2d{ .x = 0, .y = 5 },
        .dst = BB.Coord2d{ .x = 0, .y = 6 },
    };
    const m4 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .king = .black },
        .src = BB.Coord2d{ .x = 4, .y = 0 },
        .dst = BB.Coord2d{ .x = 4, .y = 1 },
    };

    const move_list = [_]MoveGen.Move{ m1, m2, m3, m4 };

    for (move_list) |move| {
        bb.active_color = move.piece.getColor();

        const result = try pseudo_check(&bb, move, allocator);
        std.testing.expect(result == false) catch |err| {
            bb.print_ansi_debug();
            std.debug.print("move X{d} Y{d} passed  pseudo_check move: {s}{s}\n", .{ move.dst.x, move.dst.y, move.src.to_algebraic(), move.dst.to_algebraic() });

            return err;
        };
    }
    std.debug.print("===Passed test:pseudo_check illegal moves\n", .{});
}
