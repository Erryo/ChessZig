const moveGen = @import("move_gen.zig");
const std = @import("std");
const log = std.log;
const IO = std.Io;

const PieceList = "prkqbn";

pub const ParseError = error{
    InvalidCharacter,
    InvalidNumber,
};

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

    active_color: Color,

    pub fn from_fen(fen: []const u8) !BitBoard {
        var bb: BitBoard = undefined;
        log.debug("making bitboard from fen: {s}\n", .{fen});

        bb.pawns = BoardPair{ .white = 0, .black = 0 };
        bb.rooks = BoardPair{ .white = 0, .black = 0 };
        bb.knights = BoardPair{ .white = 0, .black = 0 };
        bb.bishops = BoardPair{ .white = 0, .black = 0 };
        bb.queens = BoardPair{ .white = 0, .black = 0 };
        bb.kings = BoardPair{ .white = 0, .black = 0 };
        bb.attackBoard = 0;
        bb.half_move = 0;
        bb.full_move = 1;
        bb.en_passant = Coord2d{ .x = 0, .y = 0 };
        bb.active_color = .white;

        var x: u3 = 0;
        var y: u3 = 0;
        var current_idx = fen.len;
        var last_char: bool = false;
        for (fen, 0..) |char, i| {
            if (is_in_string(PieceList, char_to_lower(char))) {
                _ = bb.storeGeneral(.{ .x = 7 - x, .y = 7 - y }, Piece.decode(char));

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

                x, overflowed = @addWithOverflow(x, @as(u3, @intCast(numb)));
                if (overflowed == 1) {
                    return ParseError.InvalidNumber;
                }
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
                        current_idx = i;
                        break;
                    },
                    else => {
                        return ParseError.InvalidCharacter;
                    },
                }
            }

            if (y == 7 and x == 7) {
                last_char = true;
            }
        }

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

    pub fn isEmptyGeneral(bb: *const BitBoard, src: Coord2d) bool {
        const mask = src.to_mask();
        return ((bb.pawns.white | bb.pawns.black |
            bb.rooks.white | bb.rooks.black |
            bb.knights.white | bb.knights.black |
            bb.bishops.white | bb.bishops.black |
            bb.queens.white | bb.queens.black |
            bb.kings.white | bb.kings.black) & mask) == 0;
    }

    pub fn print(bb: *const BitBoard, writer: *IO.Writer) !void {
        try writer.print("-----Bitboard------\n", .{});

        var y: u3 = 7;
        while (y >= 0) : (y -= 1) {
            var x: u3 = 7;
            while (x >= 0) : (x -= 1) {
                const c2d = Coord2d{ .x = x, .y = y };
                if (bb.isEmptyGeneral(c2d)) {
                    //if (c2d.to_mask() & bb.occupancyBoard != 0) {
                    //    try print_board(bb.occupancyBoard, writer);
                    //    std.debug.panic("occupancyBoard does not match other boards {d}\n", .{bb.occupancyBoard});
                    //}

                    try writer.print(".", .{});

                    if (x == 0) {
                        break;
                    }
                    continue;
                }
                const piece = bb.getGeneral(c2d);
                try writer.print("{c}", .{piece.encode()});

                if (x == 0) {
                    break;
                }
            }
            try writer.print("\n", .{});
            if (y == 0) {
                break;
            }
        }
        try writer.flush();
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
        return @as(u64, 1) << (@as(u6, c2d.y) * 8 + @as(u6, c2d.x));
    }
};

fn coord_to_mask(x: u3, y: u3) u64 {
    return @as(u64, 1) << (@as(u6, y) * 8 + @as(u6, x));
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

    var y: u3 = 7;
    while (y >= 0) : (y -= 1) {
        var x: u3 = 7;
        while (x >= 0) : (x -= 1) {
            const mask = coord_to_mask(x, y);
            if ((board & mask) != 0) {
                try writer.print("1", .{});
            } else {
                try writer.print("0", .{});
            }

            if (x == 0) {
                break;
            }
        }
        try writer.print("\n", .{});
        if (y == 0) {
            break;
        }
    }
    try writer.flush();
}
