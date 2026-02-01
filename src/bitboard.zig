const log = std.log;
const IO = std.Io;
const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

const PieceList = "prkqbn";

pub const ParseError = error{
    InvalidNumber,
    BufferTooSmall,
    FenIncomplete,
};

pub const castle_black_king: usize = 0;
pub const castle_black_queen: usize = 1;
pub const castle_white_king: usize = 2;
pub const castle_white_queen: usize = 3;
pub const Starting_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub const BitBoard: type = struct {
    pawns: BoardPair,
    rooks: BoardPair,
    knights: BoardPair,
    bishops: BoardPair,
    queens: BoardPair,
    kings: BoardPair,

    occupancyBoard: u64,
    attackBoard: u64,

    half_move: u16,
    full_move: u16,
    en_passant: Coord2d,

    castling_rights: [4]bool,

    active_color: Color,

    game_state: GameState,

    pub fn from_fen(fen: []const u8) !BitBoard {
        var bb: BitBoard = undefined;
        //        std.debug.print("making bitboard from fen: {s}\n", .{fen});

        bb.pawns = BoardPair{ .white = 0, .black = 0 };
        bb.rooks = BoardPair{ .white = 0, .black = 0 };
        bb.knights = BoardPair{ .white = 0, .black = 0 };
        bb.bishops = BoardPair{ .white = 0, .black = 0 };
        bb.queens = BoardPair{ .white = 0, .black = 0 };
        bb.kings = BoardPair{ .white = 0, .black = 0 };

        bb.occupancyBoard = 0;
        bb.attackBoard = 0;

        bb.half_move = 0;
        bb.full_move = 1;
        bb.castling_rights = std.mem.zeroes([4]bool);
        bb.en_passant = Coord2d{ .x = 0, .y = 0 };
        bb.active_color = .white;
        bb.game_state = .going_on;

        var x: u3 = 0;
        var y: u3 = 0;
        var current_idx = fen.len;
        var last_char: bool = false;
        for (fen, 0..) |char, i| {
            //std.debug.print("loop at X:{d} Y:{d} \n", .{ x, y });
            if (is_in_string(PieceList, char_to_lower(char))) {
                _ = bb.storeGeneral(.{ .x = x, .y = y }, Piece.decode(char));

                if (last_char) {
                    current_idx = i;
                    break;
                }

                if (x < 7) {
                    x += 1;
                }
            } else if (is_ascii_number(char)) {
                var overflowed: u1 = 0;
                const numb: u8 = char - 48;
                if (numb > 8 or numb <= 0) {
                    return ParseError.InvalidNumber;
                }
                if (numb == 8) {
                    continue;
                }

                const result, overflowed = @addWithOverflow(x, @as(u3, @intCast(numb)));
                if (overflowed == 1) {
                    if (result != 0) {
                        return ParseError.InvalidNumber;
                    }
                }

                x = result;
            } else {
                switch (char) {
                    '/' => {
                        if (last_char) {
                            current_idx = i;
                            break;
                        }

                        y += 1;
                        x = 0;
                    },
                    ' ' => {
                        current_idx = i - 1;
                        break;
                    },
                    else => {
                        return ParseError.InvalidNumber;
                    },
                }
            }

            if (y == 7 and x == 7) {
                last_char = true;
            }
        }

        if (current_idx >= fen.len) {
            return ParseError.FenIncomplete;
        }

        current_idx += 2;

        if (fen[current_idx] == 'w') {
            bb.active_color = Color.white;
        } else if (fen[current_idx] == 'b') {
            bb.active_color = Color.black;
        } else {
            return ParseError.InvalidNumber;
        }
        current_idx += 2;

        if (current_idx >= fen.len) {
            return ParseError.FenIncomplete;
        }

        if (fen[current_idx] == '-') {
            current_idx += 1;
            bb.castling_rights = std.mem.zeroes([4]bool);
        } else {
            while (current_idx < fen.len) : (current_idx += 1) {
                switch (fen[current_idx]) {
                    'K' => bb.castling_rights[castle_white_king] = true,
                    'Q' => bb.castling_rights[castle_white_queen] = true,
                    'k' => bb.castling_rights[castle_black_king] = true,
                    'q' => bb.castling_rights[castle_black_queen] = true,
                    else => break,
                }
            }
        }

        if (current_idx > fen.len) {
            return bb;
        }

        //at the space now

        current_idx += 1;

        // en passant assume only one en_passnt at a 17:44

        const file: u8 = fen[current_idx];
        if (file != '-') {
            var en_passant_x: u3 = undefined;
            if (file >= 97 and file <= 104) {
                en_passant_x = file_to_coord(file);
            } else {
                return ParseError.InvalidNumber;
            }

            current_idx += 1;
            const rank: u8 = fen[current_idx];
            var en_passant_y: u3 = undefined;
            if (rank >= 48 and rank <= 56) {
                en_passant_y = @as(u3, @intCast(8 - (rank - 48))); // because a8 is (0,0) and is top left
            } else {
                return ParseError.InvalidNumber;
            }
            bb.en_passant = Coord2d{ .x = en_passant_x, .y = en_passant_y };
        }
        current_idx += 2;

        // half move

        var half_move: u8 = 0;
        var half_move_digit: u8 = fen[current_idx];

        while (current_idx < fen.len) : (current_idx += 1) {
            half_move_digit = fen[current_idx];
            if (half_move_digit < 48 or half_move_digit > 57) {
                break;
            }

            const mul_res, const mul_overflow = @mulWithOverflow(half_move, 10);
            if (mul_overflow == 1) {
                return ParseError.InvalidNumber;
            }
            half_move = mul_res;

            const sub_res, const sub_overflow = @subWithOverflow(half_move_digit, 48);
            if (sub_overflow == 1) {
                return ParseError.InvalidNumber;
            }
            half_move += sub_res;
        }

        bb.half_move = half_move;
        current_idx += 1;

        if (current_idx >= fen.len) {
            return ParseError.FenIncomplete;
        }

        // full move
        var full_move: u16 = 0;
        var full_move_digit: u8 = fen[current_idx];

        while (current_idx < fen.len) : (current_idx += 1) {
            full_move_digit = fen[current_idx];
            if (full_move_digit < 48 or full_move_digit > 57) {
                return ParseError.InvalidNumber;
            }

            const mul_res, const mul_overflow = @mulWithOverflow(full_move, 10);
            if (mul_overflow == 1) {
                return ParseError.InvalidNumber;
            }

            full_move = mul_res;

            const sub_res, const sub_overflow = @subWithOverflow(full_move_digit, 48);
            if (sub_overflow == 1) {
                return ParseError.InvalidNumber;
            }
            full_move += sub_res;
        }
        bb.full_move = full_move;

        return bb;
    }

    pub fn removeGeneral(bb: *BitBoard, src: Coord2d) void {
        const mask = src.to_mask();
        const removed = bb.occupancyBoard & mask != 0;

        if (removed) {
            bb.pawns.white &= ~mask;
            bb.pawns.black &= ~mask;

            bb.rooks.white &= ~mask;
            bb.rooks.black &= ~mask;

            bb.knights.white &= ~mask;
            bb.knights.black &= ~mask;

            bb.bishops.white &= ~mask;
            bb.bishops.black &= ~mask;

            bb.queens.white &= ~mask;
            bb.queens.black &= ~mask;

            bb.kings.white &= ~mask;
            bb.kings.black &= ~mask;
        }
        bb.occupancyBoard &= ~mask;
    }
    pub fn storePiece(bb: *BitBoard, pair: *BoardPair, src: Coord2d, piece: Piece) void {
        const mask = src.to_mask();
        if (piece.color == .white) {
            pair.white |= mask;
        } else {
            pair.black |= mask;
        }
        const removed = bb.occupancyBoard & mask != 0;

        if (removed) {
            bb.pawns.white &= ~mask;
            bb.pawns.black &= ~mask;

            bb.rooks.white &= ~mask;
            bb.rooks.black &= ~mask;

            bb.knights.white &= ~mask;
            bb.knights.black &= ~mask;

            bb.bishops.white &= ~mask;
            bb.bishops.black &= ~mask;

            bb.queens.white &= ~mask;
            bb.queens.black &= ~mask;

            bb.kings.white &= ~mask;
            bb.kings.black &= ~mask;
        }
        bb.occupancyBoard |= mask;
    }

    // return true if smth was replaced
    pub fn storeGeneral(bb: *BitBoard, src: Coord2d, piece: Piece) void {
        const mask = src.to_mask();
        const removed = bb.occupancyBoard & mask != 0;

        if (removed) {
            bb.pawns.white &= ~mask;
            bb.pawns.black &= ~mask;

            bb.rooks.white &= ~mask;
            bb.rooks.black &= ~mask;

            bb.knights.white &= ~mask;
            bb.knights.black &= ~mask;

            bb.bishops.white &= ~mask;
            bb.bishops.black &= ~mask;

            bb.queens.white &= ~mask;
            bb.queens.black &= ~mask;

            bb.kings.white &= ~mask;
            bb.kings.black &= ~mask;
        }
        bb.occupancyBoard |= mask;

        switch (piece.kind) {
            .pawn => {
                switch (piece.color) {
                    .white => bb.pawns.white |= mask,
                    .black => bb.pawns.black |= mask,
                }
            },
            .rook => {
                switch (piece.color) {
                    .white => bb.rooks.white |= mask,
                    .black => bb.rooks.black |= mask,
                }
            },
            .knight => {
                switch (piece.color) {
                    .white => bb.knights.white |= mask,
                    .black => bb.pawns.black |= mask,
                }
            },
            .bishop => {
                switch (piece.color) {
                    .white => bb.bishops.white |= mask,
                    .black => bb.bishops.black |= mask,
                }
            },
            .queen => {
                switch (piece.color) {
                    .white => bb.queens.white |= mask,
                    .black => bb.queens.black |= mask,
                }
            },
            .king => {
                switch (piece.color) {
                    .white => bb.kings.white |= mask,
                    .black => bb.kings.black |= mask,
                }
            },
        }

        bb.occupancyBoard |= mask;
    }

    pub fn getGeneral(bb: *const BitBoard, src: Coord2d) Piece {
        const src_mask = src.to_mask();

        if ((bb.pawns.white & src_mask) != 0) {
            return Piece{ .kind = .pawn, .color = Color.white };
        } else if ((bb.rooks.white & src_mask) != 0) {
            return Piece{ .kind = .rook, .color = Color.white };
        } else if ((bb.knights.white & src_mask) != 0) {
            return Piece{ .kind = .knight, .color = Color.white };
        } else if ((bb.bishops.white & src_mask) != 0) {
            return Piece{ .kind = .bishop, .color = Color.white };
        } else if ((bb.queens.white & src_mask) != 0) {
            return Piece{ .kind = .queen, .color = Color.white };
        } else if ((bb.kings.white & src_mask) != 0) {
            return Piece{ .kind = .king, .color = Color.white };
        } else if ((bb.pawns.black & src_mask) != 0) {
            return Piece{ .kind = .pawn, .color = Color.black };
        } else if ((bb.rooks.black & src_mask) != 0) {
            return Piece{ .kind = .rook, .color = Color.black };
        } else if ((bb.knights.black & src_mask) != 0) {
            return Piece{ .kind = .knight, .color = Color.black };
        } else if ((bb.bishops.black & src_mask) != 0) {
            return Piece{ .kind = .bishop, .color = Color.black };
        } else if ((bb.queens.black & src_mask) != 0) {
            return Piece{ .kind = .queen, .color = Color.black };
        } else if ((bb.kings.black & src_mask) != 0) {
            return Piece{ .kind = .king, .color = Color.black };
        } else {
            @panic("No piece at the given coordinate");
        }
    }

    pub fn getPiece(bb: *const BitBoard, src: Coord2d, piece: Piece) Piece {
        const mask = src.to_mask();

        switch (piece.kind) {
            .pawn => {
                switch (piece.color) {
                    .white => {
                        if ((bb.pawns.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white pawn at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.pawns.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black pawn at the given coordinate");
                        }
                    },
                }
            },
            .rook => {
                switch (piece.color) {
                    .white => {
                        if ((bb.rooks.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white rook at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.rooks.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black rook at the given coordinate");
                        }
                    },
                }
            },
            .knight => {
                switch (piece.color) {
                    .white => {
                        if ((bb.knights.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white knight at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.knights.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black knight at the given coordinate");
                        }
                    },
                }
            },
            .bishop => {
                switch (piece.color) {
                    .white => {
                        if ((bb.bishops.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white bishop at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.bishops.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black bishop at the given coordinate");
                        }
                    },
                }
            },
            .queen => {
                switch (piece.color) {
                    .white => {
                        if ((bb.queens.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white queen at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.queens.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black queen at the given coordinate");
                        }
                    },
                }
            },
            .king => {
                switch (piece.color) {
                    .white => {
                        if ((bb.kings.white & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No white king at the given coordinate");
                        }
                    },
                    .black => {
                        if ((bb.kings.black & mask) != 0) {
                            return piece;
                        } else {
                            @panic("No black king at the given coordinate");
                        }
                    },
                }
            },
        }
    }

    // return if a piece of the type is present at the given
    // coordinate and belongs to active_color of board
    pub fn isPieceAndOwn(bb: *const BitBoard, src: Coord2d, piece: Piece) bool {
        const mask = src.to_mask();
        switch (piece.kind) {
            .pawn => {
                return (if (bb.active_color == Color.black) bb.pawns.black else bb.pawns.white) & mask != 0;
            },
            .rook => {
                return (if (bb.active_color == Color.black) bb.rooks.black else bb.rooks.white) & mask != 0;
            },
            .knight => {
                return (if (bb.active_color == Color.black) bb.knights.black else bb.knights.white) & mask != 0;
            },
            .bishop => {
                return (if (bb.active_color == Color.black) bb.bishops.black else bb.bishops.white) & mask != 0;
            },
            .queen => {
                return (if (bb.active_color == Color.black) bb.queens.black else bb.queens.white) & mask != 0;
            },
            .king => {
                return (if (bb.active_color == Color.black) bb.kings.black else bb.kings.white) & mask != 0;
            },
        }
    }

    pub fn isEnemy(bb: *const BitBoard, src: Coord2d) bool {
        if (bb.active_color == Color.white) {
            return ((bb.pawns.black | bb.rooks.black | bb.knights.black | bb.bishops.black | bb.queens.black | bb.kings.black) & src.to_mask()) != 0;
        } else {
            return ((bb.pawns.white | bb.rooks.white | bb.knights.white | bb.bishops.white | bb.queens.white | bb.kings.white) & src.to_mask()) != 0;
        }
    }

    pub fn isEmptyGeneral(bb: *const BitBoard, src: Coord2d) bool {
        const mask = src.to_mask();

        return (bb.occupancyBoard & mask) == 0;
    }

    pub fn print_ansi_debug(bb: *const BitBoard) void {
        std.debug.print("-----Bitboard (ANSI)------\n\n", .{});

        // Print ranks (8 to 1)
        var y: u3 = 0;
        while (y <= 7) : (y += 1) {
            const rank: u8 = '8' - @as(u8, y);

            // Rank label (left)
            std.debug.print(" {c} ", .{rank});

            var x: u3 = 0;
            while (x <= 7) : (x += 1) {
                const c2d = Coord2d{ .x = x, .y = y };
                const is_even = ((@as(u4, x) + @as(u4, y)) & 1) == 0;

                // Background
                if (is_even) {
                    std.debug.print("\x1b[47m", .{}); // white square
                } else {
                    std.debug.print("\x1b[40m", .{}); // black square
                }

                // Content
                if (bb.isEmptyGeneral(c2d)) {
                    std.debug.print("  ", .{}); // empty square
                } else {
                    const piece = bb.getGeneral(c2d);
                    if (is_even) {
                        std.debug.print("\x1b[30m{c} ", .{piece.encode()});
                    } else {
                        std.debug.print("\x1b[37m{c} ", .{piece.encode()});
                    }
                }

                if (x == 7) break;
            }

            // Reset colors and end line
            std.debug.print("\x1b[0m\n", .{});
            if (y == 7) break;
        }

        // File labels (bottom)
        std.debug.print("  ", .{}); // align under board
        var file: u8 = 'a';
        while (file <= 'h') : (file += 1) {
            std.debug.print(" {c}", .{file});
        }
        std.debug.print("\n", .{});
    }

    pub fn print_ansi(bb: *const BitBoard, writer: *IO.Writer) !void {
        try writer.print("-----Bitboard (ANSI)------\n\n", .{});
        errdefer writer.flush() catch |err| {
            std.debug.print("failed to flush with err:{any}\n", .{err});
        };

        // Print ranks (8 to 1)
        var y: u3 = 0;
        while (y <= 7) : (y += 1) {
            const rank: u8 = '8' - @as(u8, y);

            // Rank label (left)
            try writer.print(" {c} ", .{rank});

            var x: u3 = 0;
            while (x <= 7) : (x += 1) {
                const c2d = Coord2d{ .x = x, .y = y };
                const is_even = ((@as(u4, x) + @as(u4, y)) & 1) == 0;

                // Background
                if (is_even) {
                    try writer.print("\x1b[47m", .{}); // white square
                } else {
                    try writer.print("\x1b[40m", .{}); // black square
                }

                // Content
                if (bb.isEmptyGeneral(c2d)) {
                    try writer.print("  ", .{}); // empty square
                } else {
                    const piece = bb.getGeneral(c2d);
                    if (is_even) {
                        try writer.print("\x1b[30m{c} ", .{piece.encode()});
                    } else {
                        try writer.print("\x1b[37m{c} ", .{piece.encode()});
                    }
                }

                if (x == 7) break;
            }

            // Reset colors and end line
            try writer.print("\x1b[0m\n", .{});
            if (y == 7) break;
        }

        // File labels (bottom)
        try writer.print("  ", .{}); // align under board
        var file: u8 = 'a';
        while (file <= 'h') : (file += 1) {
            try writer.print(" {c}", .{file});
        }
        try writer.print("\n", .{});

        try writer.flush();
    }

    pub fn to_FEN(bb: *const BitBoard) ![200]u8 {
        var fen: [200:0]u8 = [1:0]u8{' '} ** 200;
        var idx_in_str: usize = 0;

        var numb_empty: u8 = 0;
        var y: u3 = 0;
        while (y <= 7) : (y += 1) {
            var x: u3 = 0;
            while (x <= 7) : (x += 1) {
                if (idx_in_str >= fen.len) {
                    return ParseError.BufferTooSmall;
                }
                const c2d = Coord2d{ .x = x, .y = y };
                if (bb.isEmptyGeneral(c2d)) {
                    if (x == 7) {
                        break;
                    }
                    numb_empty += 1;
                    continue;
                }
                if (numb_empty != 0) {
                    if (numb_empty > 9) {
                        std.debug.panic("numb_empty is too big: {d}\n", .{numb_empty});
                    }

                    fen[idx_in_str] = numb_empty + 48;
                    idx_in_str += 1;
                    numb_empty = 0;
                }
                const piece = bb.getGeneral(c2d);
                fen[idx_in_str] = piece.encode();

                idx_in_str += 1;

                if (x == 7) {
                    break;
                }
            }
            if (numb_empty != 0) {
                fen[idx_in_str] = numb_empty + 49;
                idx_in_str += 1;
            }
            numb_empty = 0;
            if (y != 7) {
                fen[idx_in_str] = '/';
                idx_in_str += 1;
            } else {
                break;
            }
        }
        idx_in_str += 1;

        if (idx_in_str >= fen.len) {
            return ParseError.BufferTooSmall;
        }
        if (bb.active_color == Color.white) {
            fen[idx_in_str] = 'w';
        } else {
            fen[idx_in_str] = 'b';
        }

        idx_in_str += 2;
        if (idx_in_str >= fen.len) {
            return ParseError.BufferTooSmall;
        }
        if (bb.castling_rights[castle_white_king]) {
            fen[idx_in_str] = 'K';
        }
        if (bb.castling_rights[castle_white_queen]) {
            idx_in_str += 1;
            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
            fen[idx_in_str] = 'Q';
        }
        if (bb.castling_rights[castle_black_king]) {
            idx_in_str += 1;
            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
            fen[idx_in_str] = 'k';
        }
        if (bb.castling_rights[castle_black_queen]) {
            idx_in_str += 1;

            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
            fen[idx_in_str] = 'q';
        }

        idx_in_str += 2;
        if (idx_in_str >= fen.len) {
            return ParseError.BufferTooSmall;
        }

        if (bb.en_passant.x == 0 and bb.en_passant.y == 0) {
            fen[idx_in_str] = '-';
        } else {
            fen[idx_in_str] = @as(u8, bb.en_passant.x) + 97;
            idx_in_str += 1;
            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
            fen[idx_in_str] = (8 - @as(u8, bb.en_passant.y)) + 48;
        }
        idx_in_str += 2;

        if (idx_in_str >= fen.len) {
            return ParseError.BufferTooSmall;
        }
        var count_move_buf: [10]u8 = std.mem.zeroes([10]u8);
        const printed_half_move: []u8 = std.fmt.bufPrint(count_move_buf[0..], "{d}", .{bb.half_move}) catch {
            return ParseError.BufferTooSmall;
        };
        var buf_idx: usize = 0;

        while (idx_in_str < fen.len) : (idx_in_str += 1) {
            if (buf_idx >= printed_half_move.len) {
                break;
            }
            fen[idx_in_str] = printed_half_move[buf_idx];
            buf_idx += 1;
        } else {
            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
        }

        idx_in_str += 1;
        if (idx_in_str >= fen.len) {
            return ParseError.BufferTooSmall;
        }

        count_move_buf = std.mem.zeroes([10]u8);
        const printed_full_move = std.fmt.bufPrint(count_move_buf[0..], "{d}", .{bb.full_move}) catch {
            return ParseError.BufferTooSmall;
        };
        buf_idx = 0;

        while (idx_in_str < fen.len) : (idx_in_str += 1) {
            if (buf_idx >= printed_full_move.len) {
                break;
            }
            fen[idx_in_str] = printed_full_move[buf_idx];
            buf_idx += 1;
        } else {
            if (idx_in_str >= fen.len) {
                return ParseError.BufferTooSmall;
            }
        }

        return fen;
    }
};

pub const GameState: type = enum(u3) {
    going_on,
    white_won,
    black_won,
    stalemate,
    draw,
};

const BoardPair: type = struct {
    white: u64,
    black: u64,
};

pub const Color: type = enum(u1) {
    white,
    black,
    pub fn toggle(self: *Color) void {
        if (self.* == .white) {
            self.* = .black;
        } else if (self.* == .black) {
            self.* = .white;
        }
    }
};

pub const Piece = struct {
    kind: PieceKind,
    color: Color,

    pub fn toUnicode(piece: Piece) []const u8 {
        return switch (piece.kind) {
            .king => if (piece.color == Color.white) "♔" else "♚",
            .queen => if (piece.color == Color.white) "♕" else "♛",
            .rook => if (piece.color == Color.white) "♖" else "♜",
            .bishop => if (piece.color == Color.white) "♗" else "♝",
            .knight => if (piece.color == Color.white) "♘" else "♞",
            .pawn => if (piece.color == Color.white) "♙" else "♟",
        };
    }

    // returns the piece name as a byte
    // it is upper case for white
    // lower case for black
    pub fn encode(p: Piece) u8 {
        switch (p.kind) {
            .pawn => {
                if (p.color == .white) {
                    return 'P';
                } else {
                    return 'p';
                }
            },
            .rook => {
                if (p.color == .white) {
                    return 'R';
                } else {
                    return 'r';
                }
            },
            .knight => {
                if (p.color == .white) {
                    return 'N';
                } else {
                    return 'n';
                }
            },
            .bishop => {
                if (p.color == .white) {
                    return 'B';
                } else {
                    return 'b';
                }
            },
            .queen => {
                if (p.color == .white) {
                    return 'Q';
                } else {
                    return 'q';
                }
            },
            .king => {
                if (p.color == .white) {
                    return 'K';
                } else {
                    return 'k';
                }
            },
        }
    }
    pub fn decode(p: u8) Piece {
        switch (p) {
            'p' => return Piece{ .kind = .pawn, .color = Color.black },
            'P' => return Piece{ .kind = .pawn, .color = Color.white },

            'r' => return Piece{ .kind = .rook, .color = Color.black },
            'R' => return Piece{ .kind = .rook, .color = Color.white },

            'n' => return Piece{ .kind = .knight, .color = Color.black },
            'N' => return Piece{ .kind = .knight, .color = Color.white },

            'b' => return Piece{ .kind = .bishop, .color = Color.black },
            'B' => return Piece{ .kind = .bishop, .color = Color.white },

            'q' => return Piece{ .kind = .queen, .color = Color.black },
            'Q' => return Piece{ .kind = .queen, .color = Color.white },

            'k' => return Piece{ .kind = .king, .color = Color.black },
            'K' => return Piece{ .kind = .king, .color = Color.white },
            else => @panic("received invalid char to decode into piece"),
        }
    }
};

pub const PieceKind: type = enum {
    pawn,
    rook,
    knight,
    bishop,
    queen,
    king,
};

// 0,0 bottom right
pub const Coord2d: type = struct {
    x: u3,
    y: u3,

    pub fn to_mask(c2d: Coord2d) u64 {
        return @as(u64, 1) << (@as(u6, 7 - c2d.y) * 8 + @as(u6, 7 - c2d.x));
    }

    pub fn to_algebraic(c2d: Coord2d) [2]u8 {
        return [2]u8{ @as(u8, c2d.x) + 'a', @as(u8, 7 - c2d.y) + '1' };
    }
};

test "coord to mask " {
    try expect(coord_to_mask(0, 0) == 1 << 63);
    try expect(coord_to_mask(7, 0) == 1 << 63 - 7);
    try expect(coord_to_mask(0, 7) == 1 << 7);
    try expect(coord_to_mask(7, 7) == 1);
}
pub fn coord_to_mask(x: u3, y: u3) u64 {
    return @as(u64, 1) << (@as(u6, 7 - y) * 8 + @as(u6, 7 - x));
}

fn char_to_lower(char: u8) u8 {
    if (char >= 65 and char <= 90) {
        return char + 32;
    }
    return char;
}

fn is_in_string(str: []const u8, needle: u8) bool {
    for (str) |char| {
        if (char == needle) {
            return true;
        }
    }
    return false;
}

fn is_ascii_number(char: u8) bool {
    return (char >= 48) and (char <= 57);
}

pub fn print_board_debug(board: u64) void {
    std.debug.print(
        "\n\n\x1b[42m\x1b[0m  Chess Board \x1b[42m\x1b[0m\n",
        .{},
    );
    var y: u3 = 0;
    while (y <= 7) : (y += 1) {
        const rank: u8 = '8' - @as(u8, y);

        // Rank label (left)
        std.debug.print(" {c} ", .{rank});

        var x: u3 = 0;
        while (x <= 7) : (x += 1) {
            const mask = coord_to_mask(x, y);

            const is_even = ((@as(u4, x) + @as(u4, y)) & 1) == 0;

            if (is_even) {
                // white square - reset text color too
                std.debug.print("\x1b[47m\x1b[30m ", .{}); // white bg, black text
                if ((board & mask) != 0) {
                    std.debug.print("X", .{});
                } else {
                    std.debug.print(" ", .{});
                }
            } else {
                // black square - reset to white text
                std.debug.print("\x1b[40m\x1b[37m ", .{}); // black bg, white text

                if ((board & mask) != 0) {
                    std.debug.print("X", .{});
                } else {
                    std.debug.print(" ", .{});
                }
            }

            if (x == 7) {
                break;
            }
        }
        if (y == 7) {
            std.debug.print("\x1b[0m\n", .{});
            break;
        }

        // reset color + newline
        std.debug.print("\x1b[0m\n", .{});
    }
    // File labels (bottom)
    std.debug.print("  ", .{}); // align under board
    var file: u8 = 'a';
    while (file <= 'h') : (file += 1) {
        std.debug.print(" {c}", .{file});
    }
    std.debug.print("\n", .{});

    // final safety reset
    std.debug.print("\x1b[0m\n\n", .{});
}

pub fn print_board(board: u64, writer: *std.Io.Writer) !void {

    // Header
    try writer.print(
        "\n\n\x1b[42m\x1b[0m  Chess Board \x1b[42m\x1b[0m\n",
        .{},
    );
    var y: u3 = 0;
    while (y <= 7) : (y += 1) {
        const rank: u8 = '8' - @as(u8, y);

        // Rank label (left)
        try writer.print(" {c} ", .{rank});

        var x: u3 = 0;
        while (x <= 7) : (x += 1) {
            const mask = coord_to_mask(x, y);

            const is_even = ((@as(u4, x) + @as(u4, y)) & 1) == 0;

            if (is_even) {
                // white square - reset text color too
                try writer.print("\x1b[47m\x1b[30m ", .{}); // white bg, black text
                if ((board & mask) != 0) {
                    try writer.print("X", .{});
                } else {
                    try writer.print(" ", .{});
                }
            } else {
                // black square - reset to white text
                try writer.print("\x1b[40m\x1b[37m ", .{}); // black bg, white text

                if ((board & mask) != 0) {
                    try writer.print("X", .{});
                } else {
                    try writer.print(" ", .{});
                }
            }

            if (x == 7) {
                break;
            }
        }
        if (y == 7) {
            try writer.print("\x1b[0m\n", .{});
            break;
        }

        // reset color + newline
        try writer.print("\x1b[0m\n", .{});
    }
    // File labels (bottom)
    try writer.print("  ", .{}); // align under board
    var file: u8 = 'a';
    while (file <= 'h') : (file += 1) {
        try writer.print(" {c}", .{file});
    }
    try writer.print("\n", .{});

    // final safety reset
    try writer.print("\x1b[0m\n\n", .{});
}

pub fn file_to_coord(file: u8) u3 {
    if (file >= 97 and file <= 104) {
        const numb: u8 = file - 97;
        return @as(u3, @intCast(numb));
    }
    return 0;
    // a - 97
    // 0 - 48
}

test "file_to_coord" {
    try expect(file_to_coord('a') == 0);
    try expect(file_to_coord('b') == 1);
    try expect(file_to_coord('c') == 2);
    try expect(file_to_coord('d') == 3);
    try expect(file_to_coord('e') == 4);
    try expect(file_to_coord('f') == 5);
    try expect(file_to_coord('g') == 6);
    try expect(file_to_coord('h') == 7);
}

test "fen to board invalid" {
    const TestingBoard = struct {
        fen: []const u8,
        err: anyerror,
    };
    // mapping of invalid fen strings to expected errors
    const test_cases = [_]TestingBoard{
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0", .err = ParseError.FenIncomplete },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1", .err = ParseError.InvalidNumber },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq X 0 1", .err = ParseError.InvalidNumber },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 X", .err = ParseError.InvalidNumber },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - X 1", .err = ParseError.InvalidNumber },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 extra", .err = ParseError.InvalidNumber },
        //i.fen=nvalid board positions
        .{ .fen = "raou/eoue/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = ParseError.InvalidNumber },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPZ/RNBQKBNR w KQkq - 0 1", .err = ParseError.InvalidNumber },
        .{ .fen = "aoeuaoeu/aoeueaou/aoeu", .err = ParseError.InvalidNumber },
    };

    for (test_cases) |test_case| {
        const fen = test_case.fen;
        const expected_error = test_case.err;

        const result = BitBoard.from_fen(fen);
        try std.testing.expectError(expected_error, result);
    }
}
