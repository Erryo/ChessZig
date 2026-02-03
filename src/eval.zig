const std = @import("std");
const BB = @import("bitboard.zig");
pub fn claude_shanon(bb: *const BB.BitBoard) f32 {
    _ = bb;
    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = 0;
        };
        break :blk seed;
    });
    const rand = prng.random();
    return rand.float(f32);
}
