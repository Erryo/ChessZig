const moveGen = @import("move_gen.zig");
const std = @import("std");
const log = std.log;
const IO = std.Io;

pub const BitBoard: type = struct {
    pawns: BoardPair,
    rooks: BoardPair,
    knights: BoardPair,
    bishops: BoardPair,
    queens: BoardPair,
    kings: BoardPair,

    attackBoard: u64,
    half_move: u16,
    full_move: u32,
    en_passant: Coord2d,

    active_color: Color,

    pub fn from_fen(fen: []const u8) BitBoard {
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

        return bb;
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

pub const Color: type = enum(u2) {
    white,
    black,
    any,
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
};

// 0,0 bottom right
pub const Coord2d: type = struct {
    x: u3,
    y: u3,

    pub fn to_mask(c2d: Coord2d) u64 {
        return @as(u64, 1) << (@as(u6, c2d.y) * 8 + @as(u6, c2d.x));
    }
};

// 0,0 bottom right
fn coord_to_mask(x: u3, y: u3) u64 {
    return 1 << (y * 8 + x);
}
