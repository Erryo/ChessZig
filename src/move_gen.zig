const bb = @import("bitboard.zig");

pub const Move: type = struct {
    src: bb.Coord2D,
    dst: bb.Coord2d,
};
