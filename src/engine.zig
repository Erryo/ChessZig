const std = @import("std");
const MoveGen = @import("moveGen.zig");
const BB = @import("bitboard.zig");
const Eval = @import("eval.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const zbench = @import("zbench");

const Def_Depth = 4;
pub const MakeUnmakeError = error{
    UndoIsNull,
};

pub fn get_best_move(bb: *BB.BitBoard, allocator: *Allocator) !struct { move: MoveGen.Move, score: f32 } {
    var best_move: MoveGen.Move = undefined;
    var best_score_found = -std.math.inf(f32);

    const allMoves = try generate_all_moves(bb, allocator.*);
    const depth = Def_Depth;
    defer allocator.free(allMoves);

    const alpha = -std.math.inf(f32);
    const beta = std.math.inf(f32);

    for (allMoves) |*move| {
        make_move(bb, move);
        defer unmake_move(bb, move);
        const move_score = -try nega_max_ab(bb, allocator, alpha, beta, depth - 1);
        if (move_score > best_score_found) {
            best_move = move.*;
            best_score_found = move_score;
        }
    }

    return .{ .move = best_move, .score = best_score_found };
}

test "get best move" {
    std.debug.print("Started test: get best move \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    var allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    const result = get_best_move(&bb, &allocator) catch |err| {
        std.debug.print("Function get best move failed with err:{s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("best move score:{d:.3}\n", .{result.score});

    std.debug.print("===Passed test: get best move \n", .{});
}

fn nega_max_ab(bb: *BB.BitBoard, allocator: *Allocator, alpha: f32, beta: f32, depth: u8) !f32 {
    if (depth <= 0) return Eval.claude_shanon(bb);
    const allMoves = try generate_all_moves(bb, allocator.*);
    defer allocator.free(allMoves);

    var local_alpha: f32 = alpha;
    if (allMoves.len == 0) {
        return 0.0;
    }

    var best_score_found: f32 = -std.math.inf(f32);
    for (allMoves) |*move| {
        make_move(bb, move);
        defer unmake_move(bb, move);
        const move_score = -try nega_max_ab(bb, allocator, -beta, -local_alpha, depth - 1);
        if (move_score > best_score_found) {
            best_score_found = move_score;
            if (move_score > local_alpha) {
                local_alpha = move_score;
            }
        }
        if (move_score >= beta) return best_score_found;
    }

    return best_score_found;
}

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
    var captured_piece: ?BB.Piece = null;
    if (move.flag == .en_passant_capture) {
        captured_piece = bb.getGeneral(.{ .x = move.dst.x, .y = move.src.y });
    } else {
        captured_piece = if (bb.isEmptyGeneral(move.dst)) null else bb.getGeneral(move.dst);
    }
    const undo = MoveGen.Undo{
        .castling_rights = bb.castling_rights,
        .en_passant = bb.en_passant,
        .full_move = bb.full_move,
        .half_move = bb.half_move,
        .active_color = bb.active_color,
        .captured_piece = captured_piece,
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

pub fn pseudo_check(bb: *const BB.BitBoard, move: *const MoveGen.Move, allocator: Allocator) MoveGen.GenerationError!bool {
    var moveFn: MoveGen.moveGenFn = undefined;
    switch (move.piece.kind) {
        .pawn => moveFn = MoveGen.generate_pawn_moves,
        .knight => moveFn = MoveGen.generate_knight_moves,
        .bishop => moveFn = MoveGen.generate_bishop_moves,
        .rook => moveFn = MoveGen.generate_rook_moves,
        .queen => moveFn = MoveGen.generate_queen_moves,
        .king => moveFn = MoveGen.generate_king_moves,
    }

    var special_moves = MoveGen.SpecialsArray.initCapacity(allocator, 0) catch return MoveGen.GenerationError.AllocationFailed;
    // var because deinit'ing specials
    const possibleMoves = moveFn(bb, move.src, allocator, &special_moves) catch return MoveGen.GenerationError.AllocationFailed;

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
    defer special_moves.deinit(allocator);

    for (possibleMoves.specials.?.items) |special| {
        if (special.dst.x == move.dst.x and special.dst.y == move.dst.y) {
            return true;
        }
    }

    return false;
}

pub fn full_check(bb: *BB.BitBoard, move: *MoveGen.Move, allocator: Allocator) MoveGen.GenerationError!bool {
    const pseudo_check_passed = (try pseudo_check(bb, move, allocator));
    if (!pseudo_check_passed) return false;

    make_move(bb, move);
    bb.active_color.toggle();
    defer unmake_move(bb, move);

    if (king_attacked(bb)) {
        return false;
    }

    return true;
}

pub fn generate_all_moves(bb: *BB.BitBoard, allocator: Allocator) ![]MoveGen.Move {
    const pawn_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .pawn }, allocator);
    defer allocator.free(pawn_moves);

    const bishop_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .bishop }, allocator);
    defer allocator.free(bishop_moves);

    const knight_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .knight }, allocator);
    defer allocator.free(knight_moves);

    const rook_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .rook }, allocator);
    defer allocator.free(rook_moves);

    const queen_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .queen }, allocator);
    defer allocator.free(queen_moves);

    const king_moves = try generate_piece_all_moves(bb, .{ .color = bb.active_color, .kind = .king }, allocator);
    defer allocator.free(king_moves);

    const num_moves: usize = pawn_moves.len +
        bishop_moves.len +
        knight_moves.len +
        rook_moves.len +
        queen_moves.len +
        king_moves.len;
    var all_moves = try MoveGen.MovesArray.initCapacity(allocator, num_moves);
    defer all_moves.deinit(allocator);

    try all_moves.appendSlice(allocator, pawn_moves);
    try all_moves.appendSlice(allocator, bishop_moves);
    try all_moves.appendSlice(allocator, knight_moves);
    try all_moves.appendSlice(allocator, rook_moves);
    try all_moves.appendSlice(allocator, queen_moves);
    try all_moves.appendSlice(allocator, king_moves);

    return try all_moves.toOwnedSlice(allocator);
}
test "test generate all moves" {
    std.debug.print("Started test: generate all moves \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    const moves = generate_all_moves(&bb, allocator) catch |err| {
        std.debug.print("Function generate all moves failed with err:{s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("len moves:{d}\n", .{moves.len});
    try std.testing.expect(moves.len == 20);
    allocator.free(moves);

    std.debug.print("===Passed test: generate all moves \n", .{});
}

test "test generate all moves comlicated" {
    std.debug.print("Started test: generate all moves complicated \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1");

    const moves = generate_all_moves(&bb, allocator) catch |err| {
        std.debug.print("Function generate all moves failed with err:{s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("len moves:{d}\n", .{moves.len});
    allocator.free(moves);

    std.debug.print("===Passed test: generate all moves complicated \n", .{});
}

pub fn generate_piece_all_moves(bb: *BB.BitBoard, piece: BB.Piece, allocator: Allocator) ![]MoveGen.Move {
    var moveFn: MoveGen.moveGenFn = undefined;
    var board: u64 = undefined;

    var all_moves = try MoveGen.MovesArray.initCapacity(allocator, 1);
    var all_specials = try MoveGen.SpecialsArray.initCapacity(allocator, 1);
    defer all_specials.deinit(allocator);
    defer all_moves.deinit(allocator);
    switch (piece.kind) {
        .pawn => {
            moveFn = MoveGen.generate_pawn_moves;
            if (bb.active_color == .white) board = bb.pawns.white else board = bb.pawns.black;
        },
        .knight => {
            moveFn = MoveGen.generate_knight_moves;
            if (bb.active_color == .white) board = bb.knights.white else board = bb.knights.black;
        },
        .bishop => {
            moveFn = MoveGen.generate_bishop_moves;
            if (bb.active_color == .white) board = bb.bishops.white else board = bb.bishops.black;
        },
        .rook => {
            moveFn = MoveGen.generate_rook_moves;
            if (bb.active_color == .white) board = bb.rooks.white else board = bb.rooks.black;
        },
        .queen => {
            moveFn = MoveGen.generate_queen_moves;
            if (bb.active_color == .white) board = bb.queens.white else board = bb.queens.black;
        },
        .king => {
            moveFn = MoveGen.generate_king_moves;
            if (bb.active_color == .white) board = bb.kings.white else board = bb.kings.black;
        },
    }

    while (board != 0) {
        const src = BB.Coord2d.pop_and_get_lsb(&board);
        var moves = try moveFn(bb, src, allocator, &all_specials);
        try validate_pseudo_move_list(bb, &moves, &all_moves, allocator);
        all_specials.clearRetainingCapacity();
    }

    const slicee = try all_moves.toOwnedSlice(allocator);
    return slicee;
}

// only validates if move does not result in king being in check
fn validate_pseudo_move_list(bb: *BB.BitBoard, list: *MoveGen.MoveList, slice: *MoveGen.MovesArray, allocator: Allocator) !void {
    while (list.quiets != 0) {
        const dst = BB.Coord2d.pop_and_get_lsb(&list.quiets);
        var move: MoveGen.Move = .{
            .dst = dst,
            .flag = .quiet,
            .src = list.src,
            .piece = list.piece,
            .undo = null,
        };
        // only check if king under attack
        make_move(bb, &move);
        bb.active_color.toggle();
        defer unmake_move(bb, &move);

        if (king_attacked(bb)) {
            continue;
        }

        try slice.append(allocator, move);
    }
    while (list.captures != 0) {
        const dst = BB.Coord2d.pop_and_get_lsb(&list.captures);
        var move: MoveGen.Move = .{
            .dst = dst,
            .flag = .capture,
            .src = list.src,
            .piece = list.piece,
            .undo = null,
        };
        // only check if king under attack
        make_move(bb, &move);
        bb.active_color.toggle();
        defer unmake_move(bb, &move);

        if (king_attacked(bb)) {
            continue;
        }

        try slice.append(allocator, move);
    }

    if (list.specials == null) return;
    for (list.specials.?.items) |special| {
        var move: MoveGen.Move = .{
            .dst = special.dst,
            .flag = special.flag,
            .src = list.src,
            .piece = list.piece,
            .undo = null,
        };
        // only check if king under attack
        make_move(bb, &move);
        bb.active_color.toggle();
        defer unmake_move(bb, &move);

        if (king_attacked(bb)) {
            continue;
        }

        try slice.append(allocator, move);
    }
}

pub fn king_attacked(bb: *const BB.BitBoard) bool {
    const src = BB.Coord2d.from_msb(if (bb.active_color == .white) bb.kings.white else bb.kings.black);

    { // limit scope of variables
        const opp_queen = if (bb.active_color == .white) bb.queens.black else bb.queens.white;

        const axis_moves = MoveGen.axis_aligned_ray_move(bb, src);
        const opp_rooks = if (bb.active_color == .white) bb.rooks.black else bb.rooks.white;
        if (axis_moves.captures & opp_rooks != 0 or axis_moves.captures & opp_queen != 0) {
            //            std.debug.print("king attacked by rook or queen\n", .{});
            return true;
        }

        const diagonal_moves = MoveGen.diagonal_moves(bb, src);
        const opp_bishop = if (bb.active_color == .white) bb.bishops.black else bb.bishops.white;
        if (diagonal_moves.captures & opp_bishop != 0 or diagonal_moves.captures & opp_queen != 0) {
            //           std.debug.print("king attacked by bishop or queen\n", .{});
            return true;
        }
    }

    {
        const knight_moves = MoveGen.generate_knight_moves(bb, src, null, null) catch unreachable;

        const opp_knight = if (bb.active_color == .white) bb.knights.black else bb.knights.white;

        if (knight_moves.captures & opp_knight != 0) {
            //          std.debug.print("king attacked by knight\n", .{});
            return true;
        }
    }

    {
        const king_moves = MoveGen.generate_king_moves(bb, src, null, null) catch unreachable;
        const opp_king = if (bb.active_color == .white) bb.kings.black else bb.kings.white;

        if (king_moves.captures & opp_king != 0) {
            //         std.debug.print("king attacked by king\n", .{});
            return true;
        }
    }

    {
        const opp_pawn = if (bb.active_color == .white) bb.pawns.black else bb.pawns.white;
        const opp_y, const overflowed = if (bb.active_color == .white) @subWithOverflow(src.y, 1) else @addWithOverflow(src.y, 1);
        if (overflowed == 1) return false;

        if (src.x >= 1) {
            if (BB.coord_to_mask(src.x - 1, opp_y) & opp_pawn != 0) {
                //            std.debug.print("king attacked by pawn -1\n", .{});
                return true;
            }
        }
        if (src.x <= 6) {
            if (BB.coord_to_mask(src.x + 1, opp_y) & opp_pawn != 0) {
                //           std.debug.print("king attacked by pawn +1\n", .{});
                return true;
            }
        }
    }
    return false;
}

test "king attacked" {
    std.debug.print("Started test: king_attacked \n", .{});

    var bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    const result1 = king_attacked(&bb);
    std.testing.expect(result1 == false) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1");

    const result2 = king_attacked(&bb);
    std.testing.expect(result2 == false) catch |err| {
        bb.print_ansi_debug();
        return err;
    };

    bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    bb.storeGeneral(.{ .x = 4, .y = 5 }, .{ .kind = .queen, .color = .black });
    bb.removeGeneral(.{ .x = 4, .y = 6 });

    const result3 = king_attacked(&bb);
    std.testing.expect(result3 == true) catch |err| {
        bb.print_ansi_debug();

        return err;
    };

    std.debug.print("===Passed test: king_attacked \n", .{});
}

test "generatee piece all moves: discovered attack" {
    std.debug.print("Started test:generate piece all moves: discovered attack \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen("rnbqkbnr/pppppppp/8/8/B7/8/PPPPPPPP/RNBQK1NR b KQkq - 0 1");

    const moves = try generate_piece_all_moves(&bb, .{ .kind = .pawn, .color = bb.active_color }, allocator);
    const illegal_dst: BB.Coord2d = .{ .x = 3, .y = 3 };
    for (moves) |m| {
        if (m.dst.y == illegal_dst.y and m.dst.x == illegal_dst.x) {
            try std.testing.expect(false);
        }
    }
    allocator.free(moves);

    std.debug.print("===Passed test:generate piece all moves: discovered attack \n", .{});
}

test "generate piece all moves" {
    std.debug.print("Started test:generate piece all moves \n", .{});
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var bb = try BB.BitBoard.from_fen(BB.Starting_FEN);

    const moves = try generate_piece_all_moves(&bb, .{ .kind = .pawn, .color = bb.active_color }, allocator);
    std.debug.print("len moves:{d}\n", .{moves.len});
    allocator.free(moves);

    std.debug.print("===Passed test:generate piece all moves \n", .{});
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

    const result = try pseudo_check(&bb, &move, allocator);
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

        const result = try pseudo_check(&bb, &move, allocator);
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
