const std = @import("std");
const chess = @import("chessZig");

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const alloator = arena.allocator();

    const buffer = try alloator.alloc(u8, 500);
    var w = std.fs.File.stdout().writer(buffer);
    const writer = &w.interface;
    defer writer.flush() catch {
        std.debug.print("failde to flush buffer at the end of the program\n", .{});
    };

    try writer.print("starting chess engine: CLI-UCI version\n", .{});
    try writer.flush();

    // later:
    // - parse UCI
    // - run perft
    // - benchmark search
}
