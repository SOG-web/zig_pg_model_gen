// Model Generator - Generates Zig model files from JSON schema definitions
const std = @import("std");

const generateRegistry = @import("registry_generator.zig").generateRegistry;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <schemas_directory> [output_directory]\n", .{args[0]});
        std.debug.print("Example: {s} schemas src/db/models/generated\n", .{args[0]});
        return error.MissingArgument;
    }

    const schemas_dir = args[1];
    const output_dir = if (args.len >= 3) args[2] else "../src/db/models/generated";

    std.debug.print("Scanning schemas directory: {s}\n", .{schemas_dir});
    std.debug.print("Output directory: {s}\n\n", .{output_dir});

    // 1. Generate Registry
    const registry_path = try std.fmt.allocPrint(allocator, "{s}/registry.zig", .{schemas_dir});
    defer allocator.free(registry_path);

    try generateRegistry(schemas_dir, registry_path);
    std.debug.print("✅ Generated registry at {s}\n", .{registry_path});

    // 2. Generate Runner Script
    const runner_path = try std.fmt.allocPrint(allocator, "{s}/runner.zig", .{schemas_dir});
    defer allocator.free(runner_path);

    try generateRunner(allocator, runner_path, output_dir);
    std.debug.print("✅ Generated runner at {s}\n", .{runner_path});

    // 3. Execute Runner
    std.debug.print("🚀 Executing runner...\n", .{});

    // We need to find the absolute path to src/root.zig for the module
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    const root_path = try std.fmt.allocPrint(allocator, "{s}/src/root.zig", .{cwd});
    defer allocator.free(root_path);

    const run_args = &[_][]const u8{
        "zig",
        "run",
        runner_path,
        "--mod",
        try std.fmt.allocPrint(allocator, "fluentorm:{s}", .{root_path}),
        "--deps",
        "fluentorm",
        "--",
        output_dir,
    };

    var child = std.process.Child.init(run_args, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term.Exited != 0) {
        std.debug.print("❌ Runner failed with exit code {d}\n", .{term.Exited});
        return error.RunnerFailed;
    }

    // 4. Copy Base Models
    try copyBaseModel(allocator, output_dir);
    std.debug.print("✅ Successfully generated models\n", .{});
}

fn generateRunner(allocator: std.mem.Allocator, output_path: []const u8, output_dir: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    const content = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\const registry = @import("registry.zig");
        \\const fluentorm = @import("fluentorm");
        \\
        \\pub fn main() !void {{
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\
        \\    const schemas = try registry.getAllSchemas(allocator);
        \\    defer {{
        \\        for (schemas) |*s| s.deinit();
        \\        allocator.free(schemas);
        \\    }}
        \\
        \\    const output_dir = "{s}";
        \\
        \\    for (schemas) |schema| {{
        \\        // Use schema name as the source file name for comments
        \\        const schema_file = try std.fmt.allocPrint(allocator, "{{s}}.zig", .{{schema.name}});
        \\        defer allocator.free(schema_file);
        \\
        \\        try fluentorm.model_generator.generateModel(allocator, schema, schema_file, output_dir);
        \\    }}
        \\}}
        \\
    , .{output_dir});
    defer allocator.free(content);

    try file.writeAll(content);
}

/// Copy base.zig, query.zig, and transaction.zig to the output directory
fn copyBaseModel(allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const base_dest_path = try std.fmt.allocPrint(allocator, "{s}/base.zig", .{output_dir});
    const query_builder_dest_path = try std.fmt.allocPrint(allocator, "{s}/query.zig", .{output_dir});
    const transaction_dest_path = try std.fmt.allocPrint(allocator, "{s}/transaction.zig", .{output_dir});
    defer allocator.free(base_dest_path);
    defer allocator.free(query_builder_dest_path);
    defer allocator.free(transaction_dest_path);

    // Embed source files directly into the executable
    const base_content = @embedFile("base.zig");
    const query_content = @embedFile("query.zig");
    const transaction_content = @embedFile("transaction.zig");

    // Write to output directory (always overwrite to ensure latest version)
    try std.fs.cwd().writeFile(.{
        .sub_path = base_dest_path,
        .data = base_content,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = query_builder_dest_path,
        .data = query_content,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = transaction_dest_path,
        .data = transaction_content,
    });

    std.debug.print("📦 Bundled base.zig to {s}\n", .{base_dest_path});
    std.debug.print("📦 Bundled query.zig to {s}\n", .{query_builder_dest_path});
    std.debug.print("📦 Bundled transaction.zig to {s}\n", .{transaction_dest_path});
}
