const std = @import("std");
const MoveGen = @import("moveGen.zig");
const BB = @import("bitboard.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const MakeUnmakeError = error{
    UndoIsNull,
};

pub fn make_move_position(bb: *BB.BitBoard, move: *const MoveGen.Move) void {
    bb.en_passant = .{ .x = 0, .y = 0 };
    switch (move.piece.kind) {
        .knight, .bishop, .queen => {
            bb.storeGeneral(move.dst, move.piece);
            bb.removeGeneral(move.src);
        },
        .pawn => {
            bb.storePiece(&bb.pawns, move.dst, move.piece);
            bb.removeGeneral(move.src);
            switch (move.flag) {
                .en_passant_capture => {
                    const coord_y, const overflowed = if (bb.active_color == .white)
                        @addWithOverflow(move.dst.y, 1)
                    else
                        @subWithOverflow(move.dst.y, 1);

                    if (overflowed == 1) {
                        std.debug.panic("en passant captures overflowed, move not properly sanatized\n", .{});
                    }
                    bb.removeGeneral(.{ .x = move.dst.x, .y = coord_y });
                },
                .double_pawn_push => {
                    const coord_y, const overflowed = if (bb.active_color == .white)
                        @addWithOverflow(move.dst.y, 1)
                    else
                        @subWithOverflow(move.dst.y, 1);

                    if (overflowed == 1) {
                        std.debug.panic("double_pawn_push overflowed, move not properly sanatized\n", .{});
                    }

                    bb.en_passant = .{ .x = move.src.x, .y = coord_y };
                },
                .bishop_promotion, .knight_promotion, .rook_promotion, .queen_promotion => {
                    bb.removeGeneral(move.src);
                    bb.storeGeneral(move.dst, move.flag.to_promotion_piece(bb.active_color));
                },
                else => {},
            }
        },
        .king => {
            switch (move.flag) {
                .quiet, .capture => {
                    bb.storePiece(&bb.kings, move.dst, move.piece);
                    bb.removeGeneral(move.src);
                },
                .king_castle => {
                    bb.storePiece(&bb.kings, .{ .x = 6, .y = move.src.y }, move.piece);
                    bb.removeGeneral(move.src);

                    const rookPiece = bb.getPiece(.{ .x = 7, .y = move.src.y }, .{ .kind = .rook, .color = bb.active_color });
                    bb.storePiece(&bb.rooks, .{ .x = 5, .y = move.src.y }, rookPiece);
                    bb.removeGeneral(.{ .x = 7, .y = move.src.y });
                },
                .queen_castle => {
                    bb.storePiece(&bb.kings, .{ .x = 2, .y = move.src.y }, move.piece);
                    bb.removeGeneral(move.src);

                    const rookPiece = bb.getPiece(.{ .x = 0, .y = move.src.y }, .{ .kind = .rook, .color = bb.active_color });
                    bb.storePiece(&bb.rooks, .{ .x = 3, .y = move.src.y }, rookPiece);
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
        .rook => {
            bb.storePiece(&bb.rooks, move.dst, move.piece);
            bb.removeGeneral(move.src);

            if (bb.active_color == .white) {
                if (move.src.x == 0) {
                    bb.castling_rights[BB.castle_white_queen] = false;
                } else {
                    bb.castling_rights[BB.castle_white_king] = false;
                }
            }
            if (bb.active_color == .black) {
                if (move.src.x == 0) {
                    bb.castling_rights[BB.castle_black_queen] = false;
                } else {
                    bb.castling_rights[BB.castle_black_king] = false;
                }
            }
        },
    }
}

pub fn make_move(bb: *BB.BitBoard, move: *MoveGen.Move) void {
    const undo = MoveGen.Undo{
        .castling_rights = bb.castling_rights,
        .en_passant = bb.en_passant,
        .full_move = bb.full_move,
        .half_move = bb.half_move,
        .active_color = bb.active_color,
        .captured_piece = if (bb.isEmptyGeneral(move.dst)) null else bb.getGeneral(move.dst),
    };
    move.undo = undo;

    make_move_position(bb, move);

    //  if active_color.no_legal_moves == 0

    bb.half_move += 1;
    if (move.flag == .capture or move.piece.kind == .pawn) {
        bb.half_move = 0;
    }

    if (bb.active_color == .black) {
        bb.full_move += 1;
    }

    if (bb.half_move >= 100) {
        bb.game_state = .draw;
    }

    // three fold rep

    // eval

    bb.active_color.toggle();
}

pub fn unmake_move(bb: *BB.BitBoard, move: *MoveGen.Move) void {
    if (move.undo) |undo| {
        unmake_move_position(bb, move);
        bb.game_state = .going_on;
        bb.active_color = undo.active_color;

        bb.castling_rights = undo.castling_rights;
        bb.en_passant = undo.en_passant;

        bb.half_move = undo.half_move;
        bb.full_move = undo.full_move;
    } else {
        @panic("recieved null undo\n");
    }
}

pub fn unmake_move_position(bb: *BB.BitBoard, move: *MoveGen.Move) void {
    if (move.undo == null) {
        @panic("received in unmake pos  null undo");
    }
    const undo = &move.undo.?;

    switch (move.piece.kind) {
        .knight, .bishop, .queen, .rook => {
            bb.storeGeneral(move.src, move.piece);
            if (undo.captured_piece) |piece| {
                bb.storeGeneral(move.dst, piece);
            } else {
                bb.removeGeneral(move.dst);
            }
        },
        .pawn => {
            if (move.flag == .en_passant_capture) {
                const coord_y, const overflowed = if (bb.active_color == .white)
                    @addWithOverflow(move.dst.y, 1)
                else
                    @subWithOverflow(move.dst.y, 1);

                if (overflowed == 1) {
                    std.debug.panic("en passant captures overflowed, move not properly sanatized\n", .{});
                }

                bb.storePiece(&bb.pawns, move.src, move.piece);
                bb.removeGeneral(move.dst);

                if (undo.captured_piece) |piece| {
                    bb.storeGeneral(.{ .x = move.dst.x, .y = coord_y }, piece);
                } else {
                    @panic("got empty piece for undoing en_passant_capture\n");
                }
            } else {
                bb.storePiece(&bb.pawns, move.src, move.piece);
                if (undo.captured_piece) |piece| {
                    bb.storeGeneral(move.dst, piece);
                } else {
                    bb.removeGeneral(move.dst);
                }
            }
        },
        .king => {
            switch (move.flag) {
                .quiet, .capture => {
                    bb.storePiece(&bb.kings, move.src, move.piece);
                    if (undo.captured_piece) |piece| {
                        bb.storeGeneral(move.dst, piece);
                    } else {
                        bb.removeGeneral(move.dst);
                    }
                },
                .king_castle => {
                    bb.removeGeneral(.{ .x = 6, .y = move.src.y }); // clear king
                    bb.removeGeneral(.{ .x = 5, .y = move.src.y }); // clear rook

                    bb.storePiece(&bb.kings, move.src, move.piece);

                    if (undo.captured_piece) |piece| {
                        bb.storeGeneral(.{ .x = 7, .y = move.src.y }, piece);
                    } else {
                        @panic("got empty piece");
                    }
                },
                .queen_castle => {
                    bb.removeGeneral(.{ .x = 2, .y = move.src.y }); // clear king
                    bb.removeGeneral(.{ .x = 3, .y = move.src.y }); // clear rook

                    bb.storePiece(&bb.kings, move.src, move.piece);

                    if (undo.captured_piece) |piece| {
                        bb.storeGeneral(.{ .x = 0, .y = move.src.y }, piece);
                    } else {
                        @panic("got empty piece");
                    }
                },
                else => {},
            }
        },
    }
}

pub fn pseudo_check(bb: *BB.BitBoard, move: MoveGen.Move, allocator: Allocator) !bool {
    var moveFn: *const fn (*const BB.BitBoard, BB.Coord2d, ?Allocator) MoveGen.GenerationError!MoveGen.MoveList = undefined;
    switch (move.piece.kind) {
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
        .undo = null,
        .flag = .quiet,
        .piece = .{ .kind = .knight, .color = .white },
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
        .undo = null,
        .flag = .quiet,
        .piece = .{ .kind = .knight, .color = .white },
        .src = BB.Coord2d{ .x = 1, .y = 7 },
        .dst = BB.Coord2d{ .x = 3, .y = 7 },
    };

    const m2 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .kind = .bishop, .color = .white },
        .src = BB.Coord2d{ .x = 2, .y = 7 },
        .dst = BB.Coord2d{ .x = 3, .y = 7 },
        .undo = null,
    };
    const m3 = MoveGen.Move{
        .flag = .quiet,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = BB.Coord2d{ .x = 0, .y = 5 },
        .dst = BB.Coord2d{ .x = 0, .y = 6 },
        .undo = null,
    };
    const m4 = MoveGen.Move{
        .undo = null,
        .flag = .quiet,
        .piece = .{ .kind = .king, .color = .black },
        .src = BB.Coord2d{ .x = 4, .y = 0 },
        .dst = BB.Coord2d{ .x = 4, .y = 1 },
    };

    const move_list = [_]MoveGen.Move{ m1, m2, m3, m4 };

    for (move_list) |move| {
        bb.active_color = move.piece.color;

        const result = try pseudo_check(&bb, move, allocator);
        std.testing.expect(result == false) catch |err| {
            bb.print_ansi_debug();
            std.debug.print("move X{d} Y{d} passed  pseudo_check move: {s}{s}\n", .{ move.dst.x, move.dst.y, move.src.to_algebraic(), move.dst.to_algebraic() });

            return err;
        };
    }
    std.debug.print("===Passed test:pseudo_check illegal moves\n", .{});
}

test "make move e2e4" {
    std.debug.print("Started test: make_move e2e4\n", .{});

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    var move = MoveGen.Move{
        .undo = null,
        .flag = .double_pawn_push,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = .{ .x = 4, .y = 6 },
        .dst = .{ .x = 4, .y = 4 },
    };

    make_move(&bb, &move);

    std.testing.expect(!bb.isEmptyGeneral(.{ .x = 4, .y = 4 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(bb.isEmptyGeneral(.{ .x = 4, .y = 6 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(bb.en_passant.x == 4 and bb.en_passant.y == 5) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.debug.print("===Passed test: make_move e2e4\n", .{});
}
test "make unmake e2e4" {
    std.debug.print("Started test: make unmake e2e4\n", .{});

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    var move = MoveGen.Move{
        .undo = null,
        .flag = .double_pawn_push,
        .piece = .{ .kind = .pawn, .color = .white },
        .src = .{ .x = 4, .y = 6 },
        .dst = .{ .x = 4, .y = 4 },
    };

    make_move(&bb, &move);
    unmake_move(&bb, &move);

    std.testing.expect(!bb.isEmptyGeneral(.{ .x = 4, .y = 6 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(bb.isEmptyGeneral(.{ .x = 4, .y = 4 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(bb.en_passant.x == 0 and bb.en_passant.y == 0) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.debug.print("===Passed test: make unmake e2e4\n", .{});
}

test "unmake capture pawn" {
    std.debug.print("Started test: unmake capture pawn\n", .{});

    var bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/4P3/8/8/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");

    var move = MoveGen.Move{
        .undo = null,
        .flag = .capture,
        .piece = .{ .kind = .pawn, .color = .black },
        .src = .{ .x = 5, .y = 1 },
        .dst = .{ .x = 4, .y = 2 },
    };

    make_move(&bb, &move);
    const piece = bb.getGeneral(.{ .x = 4, .y = 2 });

    std.testing.expect(piece.color == .black) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    unmake_move(&bb, &move);

    std.testing.expect(!bb.isEmptyGeneral(.{ .x = 5, .y = 1 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };
    std.testing.expect(!bb.isEmptyGeneral(.{ .x = 4, .y = 2 })) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    std.debug.print("===Passed test: unmake capture pawn\n", .{});
}
