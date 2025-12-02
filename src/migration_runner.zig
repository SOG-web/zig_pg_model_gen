const std = @import("std");
const pg = @import("pg");

// Migration runner configuration from environment variables
pub const Config = struct {
    host: []const u8,
    port: u16,
    database: []const u8,
    username: []const u8,
    password: ?[]const u8,

    pub fn fromEnv() Config {
        return .{
            .host = std.posix.getenv("FLUENT_DB_HOST") orelse "127.0.0.1",
            .port = blk: {
                const port_str = std.posix.getenv("FLUENT_DB_PORT") orelse "5432";
                break :blk std.fmt.parseInt(u16, port_str, 10) catch 5432;
            },
            .database = std.posix.getenv("FLUENT_DB_NAME") orelse "postgres",
            .username = std.posix.getenv("FLUENT_DB_USER") orelse "postgres",
            .password = std.posix.getenv("FLUENT_DB_PASSWORD"),
        };
    }
};

// Migration file info
pub const MigrationInfo = struct {
    name: []const u8,
    path: []const u8,
    is_up: bool,
    timestamp: i64,

    pub fn lessThan(_: void, a: MigrationInfo, b: MigrationInfo) bool {
        return a.timestamp < b.timestamp;
    }
};

/// Applied migration record
pub const AppliedMigration = struct {
    name: []const u8,
    checksum: []const u8,
    applied_at: i64,
};

/// Migration runner
pub const MigrationRunner = struct {
    allocator: std.mem.Allocator,
    pool: *pg.Pool,
    migrations_dir: []const u8,

    const Self = @This();

    /// Initialize the migration runner
    pub fn init(allocator: std.mem.Allocator, config: Config, migrations_dir: []const u8) !Self {
        const pool = try pg.Pool.init(allocator, .{
            .size = 1,
            .connect = .{
                .host = config.host,
                .port = config.port,
            },
            .auth = .{
                .username = config.username,
                .password = config.password,
                .database = config.database,
            },
        });

        return .{
            .allocator = allocator,
            .pool = pool,
            .migrations_dir = migrations_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit();
    }

    /// Ensure the migrations tracking table exists
    pub fn ensureMigrationsTable(self: *Self) !void {
        _ = try self.pool.exec(
            \\CREATE TABLE IF NOT EXISTS _fluent_migrations (
            \\    id SERIAL PRIMARY KEY,
            \\    name TEXT NOT NULL UNIQUE,
            \\    checksum TEXT NOT NULL,
            \\    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
            \\)
        , .{});
    }

    /// Get list of applied migrations from database
    pub fn getAppliedMigrations(self: *Self) ![]AppliedMigration {
        var result = try self.pool.query(
            "SELECT name, checksum, EXTRACT(EPOCH FROM applied_at)::BIGINT as applied_at FROM _fluent_migrations ORDER BY name",
            .{},
        );
        defer result.deinit();

        var applied = std.ArrayList(AppliedMigration){};
        errdefer {
            for (applied.items) |m| {
                self.allocator.free(m.name);
                self.allocator.free(m.checksum);
            }
            applied.deinit(self.allocator);
        }

        while (try result.next()) |row| {
            const name = row.get([]const u8, 0);
            const checksum = row.get([]const u8, 1);
            const applied_at = row.get(i64, 2);

            try applied.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, name),
                .checksum = try self.allocator.dupe(u8, checksum),
                .applied_at = applied_at,
            });
        }

        return try applied.toOwnedSlice(self.allocator);
    }

    /// Scan migrations directory for migration files
    pub fn scanMigrations(self: *Self) ![]MigrationInfo {
        var dir = std.fs.cwd().openDir(self.migrations_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                return &.{};
            }
            return err;
        };
        defer dir.close();

        var migrations = std.ArrayList(MigrationInfo){};
        errdefer {
            for (migrations.items) |m| {
                self.allocator.free(m.name);
                self.allocator.free(m.path);
            }
            migrations.deinit(self.allocator);
        }

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".sql")) continue;

            // Skip down migrations in the scan - we handle them separately
            if (std.mem.endsWith(u8, entry.name, "_down.sql")) continue;

            // Parse timestamp from filename: {timestamp}_{name}.sql
            const underscore_pos = std.mem.indexOf(u8, entry.name, "_") orelse continue;
            const timestamp = std.fmt.parseInt(i64, entry.name[0..underscore_pos], 10) catch continue;

            const path = try std.fs.path.join(self.allocator, &.{ self.migrations_dir, entry.name });

            try migrations.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, entry.name),
                .path = path,
                .is_up = true,
                .timestamp = timestamp,
            });
        }

        // Sort by timestamp
        std.mem.sort(MigrationInfo, migrations.items, {}, MigrationInfo.lessThan);

        return try migrations.toOwnedSlice(self.allocator);
    }

    /// Calculate checksum of a file
    pub fn calculateChecksum(self: *Self, path: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});

        // Convert to hex string
        const hex = std.fmt.bytesToHex(hash, .lower);

        return try self.allocator.dupe(u8, &hex);
    }

    /// Run pending migrations
    pub fn migrate(self: *Self) !MigrateResult {
        try self.ensureMigrationsTable();

        const applied = try self.getAppliedMigrations();
        defer {
            for (applied) |m| {
                self.allocator.free(m.name);
                self.allocator.free(m.checksum);
            }
            self.allocator.free(applied);
        }

        const migrations = try self.scanMigrations();
        defer {
            for (migrations) |m| {
                self.allocator.free(m.name);
                self.allocator.free(m.path);
            }
            self.allocator.free(migrations);
        }

        // Build set of applied migration names
        var applied_set = std.StringHashMap([]const u8).init(self.allocator);
        defer applied_set.deinit();

        for (applied) |m| {
            try applied_set.put(m.name, m.checksum);
        }

        var result = MigrateResult{
            .applied_count = 0,
            .skipped_count = 0,
            .error_count = 0,
            .applied_names = std.ArrayList([]const u8){},
        };

        // Apply pending migrations
        for (migrations) |migration| {
            if (applied_set.contains(migration.name)) {
                result.skipped_count += 1;
                continue;
            }

            // Read migration SQL
            const file = std.fs.cwd().openFile(migration.path, .{}) catch |err| {
                std.debug.print("Error opening migration {s}: {}\n", .{ migration.name, err });
                result.error_count += 1;
                continue;
            };
            defer file.close();

            const sql = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
                std.debug.print("Error reading migration {s}: {}\n", .{ migration.name, err });
                result.error_count += 1;
                continue;
            };
            defer self.allocator.free(sql);

            // Calculate checksum
            const checksum = try self.calculateChecksum(migration.path);
            defer self.allocator.free(checksum);

            // Execute migration in a transaction
            const conn = try self.pool.acquire();
            defer self.pool.release(conn);

            conn.begin() catch |err| {
                std.debug.print("Error starting transaction for {s}: {}\n", .{ migration.name, err });
                result.error_count += 1;
                continue;
            };

            _ = conn.exec(sql, .{}) catch |err| {
                std.debug.print("Error executing migration {s}: {}\n", .{ migration.name, err });
                if (conn.err) |pg_err| {
                    std.debug.print("  PostgreSQL error: {s}\n", .{pg_err.message});
                }
                conn.rollback() catch {};
                result.error_count += 1;
                continue;
            };

            // Record the migration
            _ = conn.exec(
                "INSERT INTO _fluent_migrations (name, checksum) VALUES ($1, $2)",
                .{ migration.name, checksum },
            ) catch |err| {
                std.debug.print("Error recording migration {s}: {}\n", .{ migration.name, err });
                conn.rollback() catch {};
                result.error_count += 1;
                continue;
            };

            conn.commit() catch |err| {
                std.debug.print("Error committing migration {s}: {}\n", .{ migration.name, err });
                result.error_count += 1;
                continue;
            };

            try result.applied_names.append(self.allocator, try self.allocator.dupe(u8, migration.name));
            result.applied_count += 1;
        }

        return result;
    }

    /// Get migration status
    pub fn status(self: *Self) !MigrationStatus {
        try self.ensureMigrationsTable();

        const applied = try self.getAppliedMigrations();
        const migrations = try self.scanMigrations();

        // Build set of applied migration names
        var applied_set = std.StringHashMap(void).init(self.allocator);
        defer applied_set.deinit();

        for (applied) |m| {
            try applied_set.put(m.name, {});
        }

        var pending = std.ArrayList([]const u8){};
        for (migrations) |m| {
            if (!applied_set.contains(m.name)) {
                try pending.append(self.allocator, try self.allocator.dupe(u8, m.name));
            }
        }

        return .{
            .applied = applied,
            .pending = try pending.toOwnedSlice(self.allocator),
            .all_migrations = migrations,
            .allocator = self.allocator,
        };
    }

    /// Rollback the last migration
    pub fn rollback(self: *Self) !?[]const u8 {
        try self.ensureMigrationsTable();

        // Get the last applied migration
        var result = try self.pool.query(
            "SELECT name FROM _fluent_migrations ORDER BY applied_at DESC LIMIT 1",
            .{},
        );
        defer result.deinit();

        const row = try result.next() orelse return null;
        const name = try self.allocator.dupe(u8, row.get([]const u8, 0));

        // Find the down migration file
        const down_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}_down.sql",
            .{name[0 .. name.len - 4]}, // Remove .sql
        );
        defer self.allocator.free(down_name);

        const down_path = try std.fs.path.join(self.allocator, &.{ self.migrations_dir, down_name });
        defer self.allocator.free(down_path);

        // Read and execute the down migration
        const file = std.fs.cwd().openFile(down_path, .{}) catch |err| {
            std.debug.print("Down migration not found: {s} ({any})\n", .{ down_name, err });
            return null;
        };
        defer file.close();

        const sql = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(sql);

        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        try conn.begin();

        _ = conn.exec(sql, .{}) catch |err| {
            std.debug.print("Error executing rollback {s}: {}\n", .{ down_name, err });
            if (conn.err) |pg_err| {
                std.debug.print("  PostgreSQL error: {s}\n", .{pg_err.message});
            }
            conn.rollback() catch {};
            return null;
        };

        // Remove the migration record
        _ = try conn.exec("DELETE FROM _fluent_migrations WHERE name = $1", .{name});

        try conn.commit();

        return name;
    }
};

/// Result of a migration run
pub const MigrateResult = struct {
    applied_count: usize,
    skipped_count: usize,
    error_count: usize,
    applied_names: std.ArrayList([]const u8),

    pub fn deinit(self: *MigrateResult, allocator: std.mem.Allocator) void {
        for (self.applied_names.items) |name| {
            allocator.free(name);
        }
        self.applied_names.deinit(allocator);
    }
};

/// Migration status info
pub const MigrationStatus = struct {
    applied: []AppliedMigration,
    pending: [][]const u8,
    all_migrations: []MigrationInfo,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MigrationStatus) void {
        for (self.applied) |m| {
            self.allocator.free(m.name);
            self.allocator.free(m.checksum);
        }
        self.allocator.free(self.applied);

        for (self.pending) |p| {
            self.allocator.free(p);
        }
        self.allocator.free(self.pending);

        for (self.all_migrations) |m| {
            self.allocator.free(m.name);
            self.allocator.free(m.path);
        }
        self.allocator.free(self.all_migrations);
    }
};

/// CLI entry point for migration runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line arguments
    var migrations_dir: []const u8 = "migrations";
    var command: []const u8 = "up";

    var i: usize = 1; // Skip program name
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--migrations-dir") or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --migrations-dir requires a value\n", .{});
                std.debug.print("Usage: fluent-migrate [--migrations-dir <dir>] [up|status|down]\n", .{});
                return error.InvalidArgument;
            }
            migrations_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("FluentORM Migration Runner\n", .{});
            std.debug.print("\nUsage: fluent-migrate [--migrations-dir <dir>] [command]\n", .{});
            std.debug.print("\nCommands:\n", .{});
            std.debug.print("  up         Run pending migrations (default)\n", .{});
            std.debug.print("  status     Show migration status\n", .{});
            std.debug.print("  down       Rollback last migration\n", .{});
            std.debug.print("  rollback   Alias for down\n", .{});
            std.debug.print("\nOptions:\n", .{});
            std.debug.print("  -d, --migrations-dir <dir>  Directory containing migration files (default: migrations)\n", .{});
            std.debug.print("  -h, --help                 Show this help message\n", .{});
            std.debug.print("\nEnvironment Variables:\n", .{});
            std.debug.print("  FLUENT_DB_HOST     Database host (default: 127.0.0.1)\n", .{});
            std.debug.print("  FLUENT_DB_PORT     Database port (default: 5432)\n", .{});
            std.debug.print("  FLUENT_DB_NAME     Database name (default: postgres)\n", .{});
            std.debug.print("  FLUENT_DB_USER     Database user (default: postgres)\n", .{});
            std.debug.print("  FLUENT_DB_PASSWORD Database password\n", .{});
            return;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // Positional argument - assume it's the command
            command = arg;
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            std.debug.print("Usage: fluent-migrate [--migrations-dir <dir>] [up|status|down]\n", .{});
            return error.InvalidArgument;
        }
        i += 1;
    }

    const config = Config.fromEnv();

    std.debug.print("Connecting to PostgreSQL at {s}:{d}/{s}...\n", .{
        config.host,
        config.port,
        config.database,
    });
    std.debug.print("Using migrations directory: {s}\n", .{migrations_dir});

    var runner = MigrationRunner.init(allocator, config, migrations_dir) catch |err| {
        std.debug.print("Failed to connect to database: {}\n", .{err});
        std.debug.print("\nMake sure the following environment variables are set:\n", .{});
        std.debug.print("  FLUENT_DB_HOST (default: 127.0.0.1)\n", .{});
        std.debug.print("  FLUENT_DB_PORT (default: 5432)\n", .{});
        std.debug.print("  FLUENT_DB_NAME (default: postgres)\n", .{});
        std.debug.print("  FLUENT_DB_USER (default: postgres)\n", .{});
        std.debug.print("  FLUENT_DB_PASSWORD\n", .{});
        return err;
    };
    defer runner.deinit();

    if (std.mem.eql(u8, command, "up")) {
        var result = try runner.migrate();
        defer result.deinit(allocator);

        if (result.applied_count == 0) {
            std.debug.print("No pending migrations.\n", .{});
        } else {
            std.debug.print("Applied {d} migration(s):\n", .{result.applied_count});
            for (result.applied_names.items) |name| {
                std.debug.print("  ✓ {s}\n", .{name});
            }
        }

        if (result.error_count > 0) {
            std.debug.print("\n{d} migration(s) failed.\n", .{result.error_count});
        }
    } else if (std.mem.eql(u8, command, "status")) {
        var status_result = try runner.status();
        defer status_result.deinit();

        std.debug.print("Applied migrations:\n", .{});
        if (status_result.applied.len == 0) {
            std.debug.print("  (none)\n", .{});
        } else {
            for (status_result.applied) |m| {
                std.debug.print("  ✓ {s}\n", .{m.name});
            }
        }

        std.debug.print("\nPending migrations:\n", .{});
        if (status_result.pending.len == 0) {
            std.debug.print("  (none)\n", .{});
        } else {
            for (status_result.pending) |name| {
                std.debug.print("  ○ {s}\n", .{name});
            }
        }
    } else if (std.mem.eql(u8, command, "down") or std.mem.eql(u8, command, "rollback")) {
        if (try runner.rollback()) |name| {
            defer allocator.free(name);
            std.debug.print("Rolled back: {s}\n", .{name});
        } else {
            std.debug.print("No migrations to rollback.\n", .{});
        }
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("Usage: fluent-migrate [--migrations-dir <dir>] [up|status|down]\n", .{});
        std.debug.print("Run 'fluent-migrate --help' for more information.\n", .{});
    }
}
