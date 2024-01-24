const IPC = @import("../bun.js/ipc.zig");
const Allocator = std.mem.Allocator;
const uws = bun.uws;
const std = @import("std");
const default_allocator = @import("root").bun.default_allocator;
const bun = @import("root").bun;
const Environment = bun.Environment;
const Async = bun.Async;
const JSC = @import("root").bun.JSC;
const JSValue = JSC.JSValue;
const JSGlobalObject = JSC.JSGlobalObject;
const Which = @import("../which.zig");
const Output = @import("root").bun.Output;
const PosixSpawn = @import("../bun.js/api/bun/spawn.zig").PosixSpawn;
const os = std.os;
const windows = bun.windows;
const uv = windows.libuv;

pub const OutKind = enum { stdout, stderr };

pub const Stdio = union(enum) {
    /// When set to true, it means to capture the output
    inherit: struct { captured: ?*bun.ByteList = null },
    ignore: void,
    fd: bun.FileDescriptor,
    path: JSC.Node.PathLike,
    blob: JSC.WebCore.AnyBlob,
    pipe: ?JSC.WebCore.ReadableStream,
    array_buffer: struct { buf: JSC.ArrayBuffer.Strong, from_jsc: bool = false },

    pub fn isPiped(self: Stdio) bool {
        return switch (self) {
            .array_buffer, .blob, .pipe => true,
            .inherit => self.inherit.captured != null,
            else => false,
        };
    }

    pub fn setUpChildIoPosixSpawn(
        stdio: @This(),
        actions: *PosixSpawn.Actions,
        pipe_fd: [2]bun.FileDescriptor,
        comptime std_fileno: bun.FileDescriptor,
    ) !void {
        switch (stdio) {
            .array_buffer, .blob, .pipe => {
                std.debug.assert(!(stdio == .blob and stdio.blob.needsToReadFile()));
                const idx: usize = if (std_fileno == bun.STDIN_FD) 0 else 1;

                try actions.dup2(pipe_fd[idx], std_fileno);
                try actions.close(pipe_fd[1 - idx]);
            },
            .inherit => {
                if (stdio.inherit.captured != null) {
                    // Same as above
                    std.debug.assert(!(stdio == .blob and stdio.blob.needsToReadFile()));
                    const idx: usize = if (std_fileno == bun.STDIN_FD) 0 else 1;

                    try actions.dup2(pipe_fd[idx], std_fileno);
                    try actions.close(pipe_fd[1 - idx]);
                    return;
                }

                if (comptime Environment.isMac) {
                    try actions.inherit(std_fileno);
                } else {
                    try actions.dup2(std_fileno, std_fileno);
                }
            },
            .fd => |fd| {
                try actions.dup2(fd, std_fileno);
            },
            .path => |pathlike| {
                const flag = if (std_fileno == bun.STDIN_FD) @as(u32, os.O.RDONLY) else @as(u32, std.os.O.WRONLY);
                try actions.open(std_fileno, pathlike.slice(), flag | std.os.O.CREAT, 0o664);
            },
            .ignore => {
                const flag = if (std_fileno == bun.STDIN_FD) @as(u32, os.O.RDONLY) else @as(u32, std.os.O.WRONLY);
                try actions.openZ(std_fileno, "/dev/null", flag, 0o664);
            },
        }
    }

    pub fn setUpChildIoUvSpawn(
        stdio: @This(),
        std_fileno: i32,
        pipe: *uv.uv_pipe_t,
        isReadable: bool,
        fd: bun.FileDescriptor,
    ) !uv.uv_stdio_container_s {
        return switch (stdio) {
            .array_buffer, .blob, .pipe => {
                if (uv.uv_pipe_init(uv.Loop.get(), pipe, 0) != 0) {
                    return error.FailedToCreatePipe;
                }
                if (fd != bun.invalid_fd) {
                    // we receive a FD so we open this into our pipe
                    if (uv.uv_pipe_open(pipe, bun.uvfdcast(fd)).errEnum()) |_| {
                        return error.FailedToCreatePipe;
                    }
                    return uv.uv_stdio_container_s{
                        .flags = @intCast(uv.UV_INHERIT_STREAM),
                        .data = .{ .stream = @ptrCast(pipe) },
                    };
                }
                // we dont have any fd so we create a new pipe
                return uv.uv_stdio_container_s{
                    .flags = @intCast(uv.UV_CREATE_PIPE | if (isReadable) uv.UV_READABLE_PIPE else uv.UV_WRITABLE_PIPE),
                    .data = .{ .stream = @ptrCast(pipe) },
                };
            },
            .inherit => {
                if (stdio.inherit.captured != null) {
                    if (uv.uv_pipe_init(uv.Loop.get(), pipe, 0) != 0) {
                        return error.FailedToCreatePipe;
                    }
                    if (fd != bun.invalid_fd) {
                        // we receive a FD so we open this into our pipe
                        if (uv.uv_pipe_open(pipe, bun.uvfdcast(fd)).errEnum()) |_| {
                            return error.FailedToCreatePipe;
                        }
                        return uv.uv_stdio_container_s{
                            .flags = @intCast(uv.UV_INHERIT_STREAM),
                            .data = .{ .stream = @ptrCast(pipe) },
                        };
                    }
                    // we dont have any fd so we create a new pipe
                    return uv.uv_stdio_container_s{
                        .flags = @intCast(uv.UV_CREATE_PIPE | if (isReadable) uv.UV_READABLE_PIPE else uv.UV_WRITABLE_PIPE),
                        .data = .{ .stream = @ptrCast(pipe) },
                    };
                }

                return uv.uv_stdio_container_s{
                    .flags = uv.UV_INHERIT_FD,
                    .data = .{ .fd = std_fileno },
                };
            },
            .fd => |_fd| uv.uv_stdio_container_s{
                .flags = uv.UV_INHERIT_FD,
                .data = .{ .fd = bun.uvfdcast(_fd) },
            },
            .path => |pathlike| {
                _ = pathlike;
                @panic("TODO");
            },
            .ignore => uv.uv_stdio_container_s{
                .flags = uv.UV_IGNORE,
                .data = undefined,
            },
            // .memfd => unreachable,
        };
    }
};

pub fn extractStdioBlob(
    globalThis: *JSC.JSGlobalObject,
    blob: JSC.WebCore.AnyBlob,
    i: u32,
    stdio_array: []Stdio,
) bool {
    const fd = bun.stdio(i);

    if (blob.needsToReadFile()) {
        if (blob.store()) |store| {
            if (store.data.file.pathlike == .fd) {
                if (store.data.file.pathlike.fd == fd) {
                    stdio_array[i] = Stdio{ .inherit = .{} };
                } else {
                    switch (bun.FDTag.get(i)) {
                        .stdin => {
                            if (i == 1 or i == 2) {
                                globalThis.throwInvalidArguments("stdin cannot be used for stdout or stderr", .{});
                                return false;
                            }
                        },

                        .stdout, .stderr => {
                            if (i == 0) {
                                globalThis.throwInvalidArguments("stdout and stderr cannot be used for stdin", .{});
                                return false;
                            }
                        },
                        else => {},
                    }

                    stdio_array[i] = Stdio{ .fd = store.data.file.pathlike.fd };
                }

                return true;
            }

            stdio_array[i] = .{ .path = store.data.file.pathlike.path };
            return true;
        }
    }

    if (i == 1 or i == 2) {
        globalThis.throwInvalidArguments("Blobs are immutable, and cannot be used for stdout/stderr", .{});
        return false;
    }

    stdio_array[i] = .{ .blob = blob };
    return true;
}

pub const WatchFd = if (Environment.isLinux) std.os.fd_t else i32;
