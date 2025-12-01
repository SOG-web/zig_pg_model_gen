const std = @import("std");

const pg = @import("pg");

/// Query builder for BaseModel operations
pub fn QueryBuilder(comptime T: type, comptime K: type, comptime FE: type) type {
    if (!@hasDecl(T, "tableName")) {
        @compileError("Struct must have a tableName field");
    }
    return struct {
        arena: std.heap.ArenaAllocator,
        select_clauses: std.ArrayList([]const u8),
        where_clauses: std.ArrayList([]const u8),
        order_clause: ?[]const u8 = null,
        limit_val: ?u64 = null,
        offset_val: ?u64 = null,
        include_deleted: bool = false,

        const Self = @This();

        /// Enum of field names for the model.
        ///
        pub const Field = FE;

        pub const Operator = enum {
            eq,
            neq,
            gt,
            gte,
            lt,
            lte,
            like,
            ilike,
            in,
            not_in,
            is_null,
            is_not_null,

            pub fn toSql(self: Operator) []const u8 {
                return switch (self) {
                    .eq => "=",
                    .neq => "!=",
                    .gt => ">",
                    .gte => ">=",
                    .lt => "<",
                    .lte => "<=",
                    .like => "LIKE",
                    .ilike => "ILIKE",
                    .in => "IN",
                    .not_in => "NOT IN",
                    .is_null => "IS NULL",
                    .is_not_null => "IS NOT NULL",
                };
            }
        };

        pub const WhereClauseType = enum {
            @"and",
            @"or",

            pub fn toSql(self: WhereClauseType) []const u8 {
                return switch (self) {
                    .@"and" => "AND",
                    .@"or" => "OR",
                };
            }
        };

        pub const WhereClause = struct {
            /// Enum of field names for the model.
            ///
            field: Field,
            operator: Operator,
            value: ?[]const u8 = null,
            // type: ?WhereClauseType = null,
        };

        pub const OrderByClause = struct {
            field: Field,
            direction: enum {
                asc,
                desc,
            },

            pub fn toSql(self: OrderByClause) []const u8 {
                return switch (self.direction) {
                    .asc => "ASC",
                    .desc => "DESC",
                };
            }
        };

        /// Enum of field names for the model.
        ///
        pub const SelectField = []const Field;

        pub fn init() Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .where_clauses = std.ArrayList([]const u8){},
                .select_clauses = std.ArrayList([]const u8){},
            };
        }

        pub fn deinit(self: *Self) void {
            self.where_clauses.deinit(self.arena.allocator());
            self.select_clauses.deinit(self.arena.allocator());
            self.arena.deinit();
        }

        /// Add a SELECT clause
        ///
        /// Example:
        /// ```zig
        /// .select(.{ .id, .name })
        /// ```
        pub fn select(self: *Self, fields: SelectField) *Self {
            for (fields) |field| {
                const _field = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}",
                    .{@tagName(field)},
                ) catch return self;
                self.select_clauses.append(self.arena.allocator(), _field) catch return self;
            }
            return self;
        }

        /// Add a WHERE clause. Multiple calls are ANDed together.
        ///
        /// Example:
        /// ```zig
        /// .where(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        ///
        pub fn where(self: *Self, clause: WhereClause) *Self {
            const op_str = clause.operator.toSql();
            // Handle IS NULL / IS NOT NULL which don't have a value
            if (clause.operator == .is_null or clause.operator == .is_not_null) {
                const _clause = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} {s}",
                    .{ @tagName(clause.field), op_str },
                ) catch return self;
                self.where_clauses.append(self.arena.allocator(), _clause) catch return self;
                return self;
            }

            // Handle standard operators
            if (clause.value) |val| {
                const _clause = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} {s} {s}",
                    .{ @tagName(clause.field), op_str, val },
                ) catch return self;
                self.where_clauses.append(self.arena.allocator(), _clause) catch return self;
            }
            return self;
        }

        /// Add an OR WHERE clause. Multiple calls are ORed together.
        ///
        /// Example:
        /// ```zig
        /// .orWhere(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        pub fn orWhere(self: *Self, clause: WhereClause) *Self {
            const op_str = clause.operator.toSql();

            // Handle IS NULL / IS NOT NULL which don't have a value
            if (clause.operator == .is_null or clause.operator == .is_not_null) {
                const _clause = std.fmt.allocPrint(
                    self.arena.allocator(),
                    " OR {s} {s}",
                    .{ @tagName(clause.field), op_str },
                ) catch return self;
                self.where_clauses.append(self.arena.allocator(), _clause) catch return self;
                return self;
            }

            // Handle standard operators
            if (clause.value) |val| {
                const _clause = std.fmt.allocPrint(
                    self.arena.allocator(),
                    " OR {s} {s} {s}",
                    .{ @tagName(clause.field), op_str, val },
                ) catch return self;
                self.where_clauses.append(self.arena.allocator(), _clause) catch return self;
            }
            return self;
        }

        /// Set ORDER BY clause
        ///
        /// Example:
        /// ```zig
        /// .orderBy(.{ .field = .created_at, .direction = .desc })
        /// ```
        pub fn orderBy(self: *Self, clause: OrderByClause) *Self {
            const direction_str = clause.toSql();
            const _clause = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s}",
                .{ @tagName(clause.field), direction_str },
            ) catch return self;
            self.order_clause = _clause;
            return self;
        }

        /// Set LIMIT
        ///
        /// Example:
        /// ```zig
        /// .limit(10)
        /// ```
        pub fn limit(self: *Self, n: u64) *Self {
            self.limit_val = n;
            return self;
        }

        /// Set OFFSET
        ///
        /// Example:
        /// ```zig
        /// .offset(10)
        /// ```
        pub fn offset(self: *Self, n: u64) *Self {
            self.offset_val = n;
            return self;
        }

        /// Include soft-deleted records
        pub fn withDeleted(self: *Self) *Self {
            self.include_deleted = true;
            return self;
        }

        pub fn buildSql(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(allocator);

            const table_name = T.tableName();
            if (self.select_clauses.items.len > 0) {
                try sql.appendSlice(allocator, "SELECT ");
                for (self.select_clauses.items, 0..) |clause, i| {
                    try sql.appendSlice(allocator, clause);
                    if (i < self.select_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
                try sql.appendSlice(allocator, " ");
            } else {
                try sql.appendSlice(allocator, "SELECT * ");
            }
            try sql.writer(allocator).print("FROM {s}", .{table_name});

            var first_where = true;

            // Handle soft deletes
            const has_deleted_at = @hasField(T, "deleted_at");
            if (has_deleted_at and !self.include_deleted) {
                try sql.appendSlice(allocator, " WHERE deleted_at IS NULL");
                first_where = false;
            }

            for (self.where_clauses.items) |clause| {
                if (first_where) {
                    try sql.appendSlice(allocator, " WHERE ");
                    first_where = false;
                } else if (std.mem.indexOf(u8, clause, "OR") == null) {
                    try sql.appendSlice(allocator, " AND ");
                }
                try sql.appendSlice(allocator, clause);
            }

            if (self.order_clause) |order| {
                try sql.writer(allocator).print(" ORDER BY {s}", .{order});
            }

            if (self.limit_val) |l| {
                var buf: [32]u8 = undefined;
                const _limit = try std.fmt.bufPrint(&buf, " LIMIT {d}", .{l});
                try sql.appendSlice(allocator, _limit);
            }

            if (self.offset_val) |o| {
                var buf: [32]u8 = undefined;
                const _offset = try std.fmt.bufPrint(&buf, " OFFSET {d}", .{o});
                try sql.appendSlice(allocator, _offset);
            }

            return sql.toOwnedSlice(allocator);
        }

        /// Execute query and return list of items
        pub fn fetch(self: *Self, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) ![]K {
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var items = std.ArrayList(K){};
            errdefer items.deinit(allocator);

            var mapper = result.mapper(K, .{ .allocator = allocator });
            while (try mapper.next()) |item| {
                try items.append(allocator, item);
            }
            return items.toOwnedSlice();
        }

        /// Execute query and return first item or null
        pub fn first(self: *Self, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) !?K {
            self.limit_val = 1;
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(K, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }
            return null;
        }

        /// Count records matching the query
        pub fn count(self: *Self, db: *pg.Pool, args: anytype) !i64 {
            const temp_allocator = self.arena.allocator();

            // Build count SQL manually to avoid SELECT *
            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.appendSlice(temp_allocator, "SELECT COUNT(*) FROM ");
            try sql.appendSlice(temp_allocator, table_name);

            var first_where = true;
            const has_deleted_at = @hasField(T, "deleted_at");
            if (has_deleted_at and !self.include_deleted) {
                try sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL");
                first_where = false;
            }

            for (self.where_clauses.items) |clause| {
                if (first_where) {
                    try sql.appendSlice(temp_allocator, " WHERE ");
                    first_where = false;
                } else if (std.mem.indexOf(u8, clause, "OR") == null) {
                    try sql.appendSlice(temp_allocator, " AND ");
                }
                try sql.appendSlice(temp_allocator, clause);
            }

            var result = try db.queryOpts(sql.items, args, .{
                .column_names = true,
            });
            defer result.deinit();

            if (try result.next()) |row| {
                return row.get(i64, 0);
            }
            return 0;
        }
    };
}

test "query builder" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const UserQuery = QueryBuilder(User);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.select(&.{ .id, .name }).where(.{
        .field = .id,
        .operator = .eq,
        .value = "1",
    }).orWhere(.{
        .field = .name,
        .operator = .eq,
        .value = "1",
    }).where(.{
        .field = .name,
        .operator = .eq,
        .value = "2",
    }).orderBy(.{
        .field = .id,
        .direction = .asc,
    }).limit(1);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    std.debug.print("working \n {s} \n", .{sql});

    try std.testing.expectEqualStrings("SELECT id, name FROM users WHERE id = 1 OR name = 1 AND name = 2 ORDER BY id ASC LIMIT 1", sql);
}
