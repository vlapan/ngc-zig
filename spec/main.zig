const std = @import("std");
comptime {
    _ = @import("default/input.zig");
    _ = @import("default/resolve.zig");
    _ = @import("default/output.zig");
    _ = @import("default/run.zig");
    _ = @import("default/options.zig");
    _ = @import("nginx_spec.zig");
    _ = @import("scenario/basic_pipeline.zig");
    _ = @import("scenario/filtered_pipeline.zig");
    _ = @import("scenario/grouped_pipeline.zig");
    _ = @import("scenario/static_override.zig");
    _ = @import("scenario/cli_orchestration.zig");
    _ = @import("properties.zig");
    _ = @import("regressions.zig");
}
