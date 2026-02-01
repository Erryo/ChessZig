const moveGen = @import("move_gen.zig");
const std = @import("std");
const log = std.log;
const IO = std.Io;
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
    full_move: u32,
    en_passant: Coord2d,

    castling_rights: [4]bool,

    active_color: Color,

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

    // return true if smth was replaced
    pub fn storeGeneral(bb: *BitBoard, src: Coord2d, piece: Piece) bool {
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

        switch (piece) {
            .pawn => |pawn| {
                switch (pawn) {
                    .white => bb.pawns.white |= mask,
                    .black => bb.pawns.black |= mask,
                }
            },
            .rook => |rook| {
                switch (rook) {
                    .white => bb.rooks.white |= mask,
                    .black => bb.rooks.black |= mask,
                }
            },
            .knight => |knight| {
                switch (knight) {
                    .white => bb.knights.white |= mask,
                    .black => bb.pawns.black |= mask,
                }
            },
            .bishop => |bishop| {
                switch (bishop) {
                    .white => bb.bishops.white |= mask,
                    .black => bb.bishops.black |= mask,
                }
            },
            .queen => |queen| {
                switch (queen) {
                    .white => bb.queens.white |= mask,
                    .black => bb.queens.black |= mask,
                }
            },
            .king => |king| {
                switch (king) {
                    .white => bb.kings.white |= mask,
                    .black => bb.kings.black |= mask,
                }
            },
        }

        bb.occupancyBoard |= mask;
        return removed;
    }

    pub fn getGeneral(bb: *const BitBoard, src: Coord2d) Piece {
        const src_mask = src.to_mask();

        if ((bb.pawns.white & src_mask) != 0) {
            return Piece{ .pawn = Color.white };
        } else if ((bb.rooks.white & src_mask) != 0) {
            return Piece{ .rook = Color.white };
        } else if ((bb.knights.white & src_mask) != 0) {
            return Piece{ .knight = Color.white };
        } else if ((bb.bishops.white & src_mask) != 0) {
            return Piece{ .bishop = Color.white };
        } else if ((bb.queens.white & src_mask) != 0) {
            return Piece{ .queen = Color.white };
        } else if ((bb.kings.white & src_mask) != 0) {
            return Piece{ .king = Color.white };
        } else if ((bb.pawns.black & src_mask) != 0) {
            return Piece{ .pawn = Color.black };
        } else if ((bb.rooks.black & src_mask) != 0) {
            return Piece{ .rook = Color.black };
        } else if ((bb.knights.black & src_mask) != 0) {
            return Piece{ .knight = Color.black };
        } else if ((bb.bishops.black & src_mask) != 0) {
            return Piece{ .bishop = Color.black };
        } else if ((bb.queens.black & src_mask) != 0) {
            return Piece{ .queen = Color.black };
        } else if ((bb.kings.black & src_mask) != 0) {
            return Piece{ .king = Color.black };
        } else {
            @panic("No piece at the given coordinate");
        }
    }

    pub fn getPiece(bb: *const BitBoard, src: Coord2d, piece: Piece) Piece {
        const mask = src.to_mask();

        switch (piece) {
            .pawn => |pawn| {
                switch (pawn) {
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
            .rook => |rook| {
                switch (rook) {
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
            .knight => |knight| {
                switch (knight) {
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
            .bishop => |bishop| {
                switch (bishop) {
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
            .queen => |queen| {
                switch (queen) {
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
            .king => |king| {
                switch (king) {
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
        switch (piece) {
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

    pub fn print(bb: *const BitBoard, writer: *IO.Writer) !void {
        try writer.print("-----Bitboard------\n", .{});
        errdefer writer.flush() catch |err| {
            std.debug.print("failed to flush with err:{any}\n", .{err});
        };

        var y: u3 = 0;
        while (y <= 7) : (y += 1) {
            var x: u3 = 0;
            while (x <= 7) : (x += 1) {
                const c2d = Coord2d{ .x = x, .y = y };
                if (bb.isEmptyGeneral(c2d)) {
                    try writer.print(".", .{});

                    if (x == 7) {
                        break;
                    }
                    continue;
                }
                const piece = bb.getGeneral(c2d);
                try writer.print("{c}", .{piece.encode()});

                if (x == 7) {
                    break;
                }
            }
            try writer.print("\n", .{});
            if (y == 7) {
                break;
            }
        }
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

const BoardPair: type = struct {
    white: u64,
    black: u64,
};

pub const Color: type = enum(u1) {
    white,
    black,
    pub fn toggle(self: *Color) void {
        if (self == .white) {
            self.* = .black;
        } else if (self == .black) {
            self.* = .white;
        }
    }
};

pub const Piece: type = union(enum) {
    pawn: Color,
    rook: Color,
    knight: Color,
    bishop: Color,
    queen: Color,
    king: Color,

    pub fn getColor(piece: Piece) Color {
        return switch (piece) {
            .king => |king| king,
            .queen => |queen| queen,
            .rook => |rook| rook,
            .bishop => |bishop| bishop,
            .knight => |knight| knight,
            .pawn => |pawn| pawn,
        };
    }

    pub fn toUnicode(piece: Piece) []const u8 {
        return switch (piece) {
            .king => |king| if (king == Color.white) "♔" else "♚",
            .queen => |queen| if (queen == Color.white) "♕" else "♛",
            .rook => |rook| if (rook == Color.white) "♖" else "♜",
            .bishop => |bishop| if (bishop == Color.white) "♗" else "♝",
            .knight => |knight| if (knight == Color.white) "♘" else "♞",
            .pawn => |pawn| if (pawn == Color.white) "♙" else "♟",
        };
    }

    // returns the piece name as a byte
    // it is upper case for white
    // lower case for black
    pub fn encode(p: Piece) u8 {
        switch (p) {
            .pawn => |pawn| {
                if (pawn == .white) {
                    return 'P';
                } else {
                    return 'p';
                }
            },
            .rook => |rook| {
                if (rook == .white) {
                    return 'R';
                } else {
                    return 'r';
                }
            },
            .knight => |knight| {
                if (knight == .white) {
                    return 'N';
                } else {
                    return 'n';
                }
            },
            .bishop => |bishop| {
                if (bishop == .white) {
                    return 'B';
                } else {
                    return 'b';
                }
            },
            .queen => |queen| {
                if (queen == .white) {
                    return 'Q';
                } else {
                    return 'q';
                }
            },
            .king => |king| {
                if (king == .white) {
                    return 'K';
                } else {
                    return 'k';
                }
            },
        }
    }
    pub fn decode(p: u8) Piece {
        switch (p) {
            'p' => return Piece{ .pawn = Color.black },
            'P' => return Piece{ .pawn = Color.white },

            'r' => return Piece{ .rook = Color.black },
            'R' => return Piece{ .rook = Color.white },

            'n' => return Piece{ .knight = Color.black },
            'N' => return Piece{ .knight = Color.white },

            'b' => return Piece{ .bishop = Color.black },
            'B' => return Piece{ .bishop = Color.white },

            'q' => return Piece{ .queen = Color.black },
            'Q' => return Piece{ .queen = Color.white },

            'k' => return Piece{ .king = Color.black },
            'K' => return Piece{ .king = Color.white },
            else => @panic("received invalid char to decode into piece"),
        }
    }
};

// 0,0 bottom right
pub const Coord2d: type = struct {
    x: u3,
    y: u3,

    pub fn to_mask(c2d: Coord2d) u64 {
        return @as(u64, 1) << (@as(u6, 7 - c2d.y) * 8 + @as(u6, 7 - c2d.x));
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

pub fn print_board(board: u64, writer: *IO.Writer) !void {
    try writer.print("-----Board------\n", .{});

    var y: u3 = 0;
    while (y <= 7) : (y += 1) {
        var x: u3 = 0;
        while (x <= 7) : (x += 1) {
            const mask = coord_to_mask(x, y);
            if ((board & mask) != 0) {
                try writer.print("+", .{});
            } else {
                try writer.print(".", .{});
            }

            if (x == 7) {
                break;
            }
        }
        try writer.print("\n", .{});
        if (y == 7) {
            break;
        }
    }
    try writer.flush();
}

pub fn print_board_ansi(board: u64) void {
    var w = std.fs.File.stdout().writer(&.{});
    const writer = &w.interface;

    // Header
    writer.print(
        "\n\n\x1b[42m\x1b[0m  Chess Board \x1b[42m\x1b[0m\n",
        .{},
    ) catch {};
    var y: u3 = 0;
    while (y <= 7) : (y += 1) {
        const rank: u8 = '8' - @as(u8, y);

        // Rank label (left)
        writer.print(" {c} ", .{rank}) catch {};

        var x: u3 = 0;
        while (x <= 7) : (x += 1) {
            const mask = coord_to_mask(x, y);

            const is_even = ((@as(u4, x) + @as(u4, y)) & 1) == 0;

            if (is_even) {
                // white square - reset text color too
                writer.print("\x1b[47m\x1b[30m ", .{}) catch {}; // white bg, black text
                if ((board & mask) != 0) {
                    writer.print("X", .{}) catch {};
                } else {
                    writer.print(" ", .{}) catch {};
                }
            } else {
                // black square - reset to white text
                writer.print("\x1b[40m\x1b[37m ", .{}) catch {}; // black bg, white text

                if ((board & mask) != 0) {
                    writer.print("X", .{}) catch {};
                } else {
                    writer.print(" ", .{}) catch {};
                }
            }

            if (x == 7) {
                break;
            }
        }
        if (y == 7) {
            writer.print("\x1b[0m\n", .{}) catch {};
            break;
        }

        // reset color + newline
        writer.print("\x1b[0m\n", .{}) catch {};
    }
    // File labels (bottom)
    writer.print("  ", .{}) catch {}; // align under board
    var file: u8 = 'a';
    while (file <= 'h') : (file += 1) {
        writer.print(" {c}", .{file}) catch {};
    }
    writer.print("\n", .{}) catch {};

    // final safety reset
    writer.print("\x1b[0m\n\n", .{}) catch {};
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
