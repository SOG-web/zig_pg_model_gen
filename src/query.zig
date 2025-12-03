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
        where_clauses: std.ArrayList(WhereClauseInternal),
        order_clauses: std.ArrayList([]const u8),
        group_clauses: std.ArrayList([]const u8),
        having_clauses: std.ArrayList([]const u8),
        join_clauses: std.ArrayList([]const u8),
        limit_val: ?u64 = null,
        offset_val: ?u64 = null,
        include_deleted: bool = false,
        distinct_enabled: bool = false,

        const Self = @This();

        /// Internal representation of where clauses
        const WhereClauseInternal = struct {
            sql: []const u8,
            clause_type: WhereClauseType,
        };

        /// Enum of field names for the model.
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
            between,
            not_between,

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
                    .between => "BETWEEN",
                    .not_between => "NOT BETWEEN",
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
            field: Field,
            operator: Operator,
            value: ?[]const u8 = null,
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

        pub const JoinType = enum {
            inner,
            left,
            right,
            full,

            pub fn toSql(self: JoinType) []const u8 {
                return switch (self) {
                    .inner => "INNER JOIN",
                    .left => "LEFT JOIN",
                    .right => "RIGHT JOIN",
                    .full => "FULL OUTER JOIN",
                };
            }
        };

        pub const AggregateType = enum {
            count,
            sum,
            avg,
            min,
            max,

            pub fn toSql(self: AggregateType) []const u8 {
                return switch (self) {
                    .count => "COUNT",
                    .sum => "SUM",
                    .avg => "AVG",
                    .min => "MIN",
                    .max => "MAX",
                };
            }
        };

        pub const SelectField = []const Field;

        pub fn init() Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .where_clauses = std.ArrayList(WhereClauseInternal){},
                .select_clauses = std.ArrayList([]const u8){},
                .order_clauses = std.ArrayList([]const u8){},
                .group_clauses = std.ArrayList([]const u8){},
                .having_clauses = std.ArrayList([]const u8){},
                .join_clauses = std.ArrayList([]const u8){},
            };
        }

        pub fn deinit(self: *Self) void {
            self.where_clauses.deinit(self.arena.allocator());
            self.select_clauses.deinit(self.arena.allocator());
            self.order_clauses.deinit(self.arena.allocator());
            self.group_clauses.deinit(self.arena.allocator());
            self.having_clauses.deinit(self.arena.allocator());
            self.join_clauses.deinit(self.arena.allocator());
            self.arena.deinit();
        }

        /// Reset the query - clear all clauses, this makes the query builder reusable
        ///
        /// Example:
        /// ```zig
        /// .reset()
        /// ```
        pub fn reset(self: *Self) void {
            self.where_clauses.clearAndFree(self.arena.allocator());
            self.select_clauses.clearAndFree(self.arena.allocator());
            self.order_clauses.clearAndFree(self.arena.allocator());
            self.group_clauses.clearAndFree(self.arena.allocator());
            self.having_clauses.clearAndFree(self.arena.allocator());
            self.join_clauses.clearAndFree(self.arena.allocator());
            self.limit_val: ?u64 = null,
            self.offset_val: ?u64 = null,
            self.include_deleted: bool = false,
            self.distinct_enabled: bool = false,
        }

        /// Add a SELECT clause
        ///
        /// Example:
        /// ```zig
        /// .select(&.{ .id, .name })
        /// ```
        pub fn select(self: *Self, fields: []const FE) *Self {
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

        /// Enable DISTINCT on the query
        ///
        /// Example:
        /// ```zig
        /// .distinct().select(&.{ .email })
        /// ```
        pub fn distinct(self: *Self) *Self {
            self.distinct_enabled = true;
            return self;
        }

        /// Select with an aggregate function
        ///
        /// Example:
        /// ```zig
        /// .selectAggregate(.sum, .amount, "total_amount")
        /// ```
        pub fn selectAggregate(self: *Self, agg: AggregateType, field: FE, alias: []const u8) *Self {
            const _field = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}({s}) AS {s}",
                .{ agg.toSql(), @tagName(field), alias },
            ) catch return self;
            self.select_clauses.append(self.arena.allocator(), _field) catch return self;
            return self;
        }

        /// Select raw SQL expression
        ///
        /// Example:
        /// ```zig
        /// .selectRaw("COUNT(*) AS total")
        /// ```
        pub fn selectRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.select_clauses.append(self.arena.allocator(), _raw) catch return self;
            return self;
        }

        /// Add a WHERE clause. Multiple calls are ANDed together.
        ///
        /// Example:
        /// ```zig
        /// .where(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        pub fn where(self: *Self, clause: WhereClause) *Self {
            const sql = self.buildWhereClauseSql(clause) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add an OR WHERE clause.
        ///
        /// Example:
        /// ```zig
        /// .orWhere(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        pub fn orWhere(self: *Self, clause: WhereClause) *Self {
            const sql = self.buildWhereClauseSql(clause) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"or",
            }) catch return self;
            return self;
        }

        fn buildWhereClauseSql(self: *Self, clause: WhereClause) ![]const u8 {
            const op_str = clause.operator.toSql();

            // Handle IS NULL / IS NOT NULL which don't have a value
            if (clause.operator == .is_null or clause.operator == .is_not_null) {
                return try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} {s}",
                    .{ @tagName(clause.field), op_str },
                );
            }

            // Handle standard operators
            if (clause.value) |val| {
                return try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} {s} {s}",
                    .{ @tagName(clause.field), op_str, val },
                );
            }

            return "";
        }

        /// Add a BETWEEN clause
        ///
        /// Example:
        /// ```zig
        /// .whereBetween(.age, "$1", "$2")
        /// ```
        pub fn whereBetween(self: *Self, field: FE, low: []const u8, high: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} BETWEEN {s} AND {s}",
                .{ @tagName(field), low, high },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a NOT BETWEEN clause
        ///
        /// Example:
        /// ```zig
        /// .whereNotBetween(.age, "$1", "$2")
        /// ```
        pub fn whereNotBetween(self: *Self, field: FE, low: []const u8, high: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} NOT BETWEEN {s} AND {s}",
                .{ @tagName(field), low, high },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE IN clause with values
        ///
        /// Example:
        /// ```zig
        /// .whereIn(.status, &.{ "'active'", "'pending'" })
        /// ```
        pub fn whereIn(self: *Self, field: FE, values: []const []const u8) *Self {
            var values_str = std.ArrayList(u8){};
            values_str.appendSlice(self.arena.allocator(), "(") catch return self;
            for (values, 0..) |val, i| {
                values_str.appendSlice(self.arena.allocator(), val) catch return self;
                if (i < values.len - 1) {
                    values_str.appendSlice(self.arena.allocator(), ", ") catch return self;
                }
            }
            values_str.appendSlice(self.arena.allocator(), ")") catch return self;

            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} IN {s}",
                .{ @tagName(field), values_str.items },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NOT IN clause with values
        ///
        /// Example:
        /// ```zig
        /// .whereNotIn(.status, &.{ "'deleted'", "'archived'" })
        /// ```
        pub fn whereNotIn(self: *Self, field: FE, values: []const []const u8) *Self {
            var values_str = std.ArrayList(u8){};
            values_str.appendSlice(self.arena.allocator(), "(") catch return self;
            for (values, 0..) |val, i| {
                values_str.appendSlice(self.arena.allocator(), val) catch return self;
                if (i < values.len - 1) {
                    values_str.appendSlice(self.arena.allocator(), ", ") catch return self;
                }
            }
            values_str.appendSlice(self.arena.allocator(), ")") catch return self;

            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} NOT IN {s}",
                .{ @tagName(field), values_str.items },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a raw WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .whereRaw("age > $1 AND age < $2")
        /// ```
        pub fn whereRaw(self: *Self, raw_sql: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add an OR raw WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .orWhereRaw("status = 'vip' OR role = 'admin'")
        /// ```
        pub fn orWhereRaw(self: *Self, raw_sql: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"or",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NULL clause
        ///
        /// Example:
        /// ```zig
        /// .whereNull(.deleted_at)
        /// ```
        pub fn whereNull(self: *Self, field: FE) *Self {
            return self.where(.{
                .field = field,
                .operator = .is_null,
            });
        }

        /// Add a WHERE NOT NULL clause
        ///
        /// Example:
        /// ```zig
        /// .whereNotNull(.email_verified_at)
        /// ```
        pub fn whereNotNull(self: *Self, field: FE) *Self {
            return self.where(.{
                .field = field,
                .operator = .is_not_null,
            });
        }

        /// Add a WHERE EXISTS subquery
        ///
        /// Example:
        /// ```zig
        /// .whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id")
        /// ```
        pub fn whereExists(self: *Self, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "EXISTS ({s})",
                .{subquery},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NOT EXISTS subquery
        ///
        /// Example:
        /// ```zig
        /// .whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id")
        /// ```
        pub fn whereNotExists(self: *Self, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "NOT EXISTS ({s})",
                .{subquery},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a subquery in WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .whereSubquery(.id, .in, "SELECT user_id FROM premium_users")
        /// ```
        pub fn whereSubquery(self: *Self, field: FE, operator: Operator, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} ({s})",
                .{ @tagName(field), operator.toSql(), subquery },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .join(.inner, "posts", "users.id = posts.user_id")
        /// ```
        pub fn join(self: *Self, join_type: JoinType, table: []const u8, on_clause: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} ON {s}",
                .{ join_type.toSql(), table, on_clause },
            ) catch return self;
            self.join_clauses.append(self.arena.allocator(), sql) catch return self;
            return self;
        }

        /// Add an INNER JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .innerJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn innerJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.inner, table, on_clause);
        }

        /// Add a LEFT JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .leftJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn leftJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.left, table, on_clause);
        }

        /// Add a RIGHT JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .rightJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn rightJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.right, table, on_clause);
        }

        /// Add a FULL OUTER JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .fullJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn fullJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.full, table, on_clause);
        }

        /// Add GROUP BY clause
        ///
        /// Example:
        /// ```zig
        /// .groupBy(&.{ .status, .role })
        /// ```
        pub fn groupBy(self: *Self, fields: []const FE) *Self {
            for (fields) |field| {
                const _field = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}",
                    .{@tagName(field)},
                ) catch return self;
                self.group_clauses.append(self.arena.allocator(), _field) catch return self;
            }
            return self;
        }

        /// Add GROUP BY with raw SQL
        ///
        /// Example:
        /// ```zig
        /// .groupByRaw("DATE(created_at)")
        /// ```
        pub fn groupByRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.group_clauses.append(self.arena.allocator(), _raw) catch return self;
            return self;
        }

        /// Add HAVING clause
        ///
        /// Example:
        /// ```zig
        /// .having("COUNT(*) > $1")
        /// ```
        pub fn having(self: *Self, condition: []const u8) *Self {
            const _cond = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{condition},
            ) catch return self;
            self.having_clauses.append(self.arena.allocator(), _cond) catch return self;
            return self;
        }

        /// Add HAVING with aggregate function
        ///
        /// Example:
        /// ```zig
        /// .havingAggregate(.count, .id, .gt, "$1")
        /// ```
        pub fn havingAggregate(self: *Self, agg: AggregateType, field: FE, operator: Operator, value: []const u8) *Self {
            const _cond = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}({s}) {s} {s}",
                .{ agg.toSql(), @tagName(field), operator.toSql(), value },
            ) catch return self;
            self.having_clauses.append(self.arena.allocator(), _cond) catch return self;
            return self;
        }

        /// Set ORDER BY clause (can be called multiple times)
        ///
        /// Example:
        /// ```zig
        /// .orderBy(.{ .field = .created_at, .direction = .desc })
        /// .orderBy(.{ .field = .name, .direction = .asc })
        /// ```
        pub fn orderBy(self: *Self, clause: OrderByClause) *Self {
            const direction_str = clause.toSql();
            const _clause = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s}",
                .{ @tagName(clause.field), direction_str },
            ) catch return self;
            self.order_clauses.append(self.arena.allocator(), _clause) catch return self;
            return self;
        }

        /// Add raw ORDER BY clause
        ///
        /// Example:
        /// ```zig
        /// .orderByRaw("RANDOM()")
        /// ```
        pub fn orderByRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.order_clauses.append(self.arena.allocator(), _raw) catch return self;
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

        /// Paginate results (convenience method for limit + offset)
        ///
        /// Example:
        /// ```zig
        /// .paginate(2, 20) // Page 2 with 20 items per page
        /// ```
        pub fn paginate(self: *Self, page: u64, per_page: u64) *Self {
            const actual_page = if (page == 0) 1 else page;
            self.limit_val = per_page;
            self.offset_val = (actual_page - 1) * per_page;
            return self;
        }

        /// Include soft-deleted records
        pub fn withDeleted(self: *Self) *Self {
            self.include_deleted = true;
            return self;
        }

        /// Only get soft-deleted records
        ///
        /// Example:
        /// ```zig
        /// .onlyDeleted()
        /// ```
        pub fn onlyDeleted(self: *Self) *Self {
            self.include_deleted = true;
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "deleted_at IS NOT NULL",
                .{},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        pub fn buildSql(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(allocator);

            const table_name = T.tableName();

            // SELECT clause
            if (self.distinct_enabled) {
                try sql.appendSlice(allocator, "SELECT DISTINCT ");
            } else {
                try sql.appendSlice(allocator, "SELECT ");
            }

            if (self.select_clauses.items.len > 0) {
                for (self.select_clauses.items, 0..) |clause, i| {
                    try sql.appendSlice(allocator, clause);
                    if (i < self.select_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
                try sql.appendSlice(allocator, " ");
            } else {
                try sql.appendSlice(allocator, "* ");
            }

            // FROM clause
            try sql.writer(allocator).print("FROM {s}", .{table_name});

            // JOIN clauses
            for (self.join_clauses.items) |join_sql| {
                try sql.appendSlice(allocator, " ");
                try sql.appendSlice(allocator, join_sql);
            }

            var first_where = true;

            // Handle soft deletes
            const has_deleted_at = @hasField(T, "deleted_at");
            if (has_deleted_at and !self.include_deleted) {
                try sql.appendSlice(allocator, " WHERE deleted_at IS NULL");
                first_where = false;
            }

            // WHERE clauses
            for (self.where_clauses.items) |clause| {
                if (first_where) {
                    try sql.appendSlice(allocator, " WHERE ");
                    first_where = false;
                } else {
                    try sql.writer(allocator).print(" {s} ", .{clause.clause_type.toSql()});
                }
                try sql.appendSlice(allocator, clause.sql);
            }

            // GROUP BY clause
            if (self.group_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " GROUP BY ");
                for (self.group_clauses.items, 0..) |group, i| {
                    try sql.appendSlice(allocator, group);
                    if (i < self.group_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
            }

            // HAVING clause
            if (self.having_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " HAVING ");
                for (self.having_clauses.items, 0..) |having_clause, i| {
                    try sql.appendSlice(allocator, having_clause);
                    if (i < self.having_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, " AND ");
                    }
                }
            }

            // ORDER BY clause
            if (self.order_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " ORDER BY ");
                for (self.order_clauses.items, 0..) |order, i| {
                    try sql.appendSlice(allocator, order);
                    if (i < self.order_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
            }

            // LIMIT clause
            if (self.limit_val) |l| {
                var buf: [32]u8 = undefined;
                const _limit = try std.fmt.bufPrint(&buf, " LIMIT {d}", .{l});
                try sql.appendSlice(allocator, _limit);
            }

            // OFFSET clause
            if (self.offset_val) |o| {
                var buf: [32]u8 = undefined;
                const _offset = try std.fmt.bufPrint(&buf, " OFFSET {d}", .{o});
                try sql.appendSlice(allocator, _offset);
            }

            return sql.toOwnedSlice(allocator);
        }

        /// Check if the query has custom projections that can't be mapped to the model type.
        /// This includes:
        /// - Aggregate functions (COUNT, SUM, etc.)
        /// - Raw selects with aliases (AS)
        /// - JOIN clauses (result columns from multiple tables)
        /// - GROUP BY clauses (typically used with aggregates)
        /// - HAVING clauses (requires GROUP BY)
        /// - DISTINCT with custom selects
        fn hasCustomProjection(self: *Self) bool {
            // JOINs produce columns from multiple tables - can't map to single model
            if (self.join_clauses.items.len > 0) {
                return true;
            }

            // GROUP BY typically means aggregation - result shape differs from model
            if (self.group_clauses.items.len > 0) {
                return true;
            }

            // HAVING requires GROUP BY and aggregates
            if (self.having_clauses.items.len > 0) {
                return true;
            }

            // Check select clauses for aggregates, aliases, or raw SQL patterns
            for (self.select_clauses.items) |clause| {
                // Check for aggregate function patterns: COUNT(, SUM(, AVG(, MIN(, MAX(
                if (std.mem.indexOf(u8, clause, "(") != null) {
                    return true;
                }
                // Check for AS alias (indicates custom projection)
                if (std.mem.indexOf(u8, clause, " AS ") != null or
                    std.mem.indexOf(u8, clause, " as ") != null)
                {
                    return true;
                }
                // Check for table.column pattern (indicates join-like select)
                if (std.mem.indexOf(u8, clause, ".") != null) {
                    return true;
                }
                // Check for wildcard with table prefix (e.g., "users.*")
                if (std.mem.indexOf(u8, clause, ".*") != null) {
                    return true;
                }
            }

            return false;
        }

        /// Execute query and return list of items.
        /// Returns an error if the query contains custom projections that can't map to model type K:
        /// - JOINs (use `fetchRaw` or `fetchAs` with a custom struct)
        /// - GROUP BY / HAVING clauses
        /// - Aggregate functions (selectAggregate)
        /// - Raw selects with aliases or table prefixes
        ///
        /// Example:
        /// ```zig
        /// const users = try User.query()
        ///     .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
        ///     .fetch(&pool, allocator, .{});
        /// defer allocator.free(users);
        /// ```
        pub fn fetch(self: *Self, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) ![]K {
            // Guard: reject queries with custom projections that can't map to K
            if (self.hasCustomProjection()) {
                return error.CustomProjectionRequiresFetchAs;
            }

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
            return items.toOwnedSlice(allocator);
        }

        /// Execute query and return list of items mapped to a custom result type.
        /// Use this when you have custom selects, aggregates, or need a different shape than the model.
        ///
        /// Example:
        /// ```zig
        /// const UserSummary = struct { id: i64, total_posts: i64 };
        /// const summaries = try User.query()
        ///     .select(&.{.id})
        ///     .selectAggregate(.count, .id, "total_posts")
        ///     .groupBy(&.{.id})
        ///     .fetchAs(UserSummary, &pool, allocator, .{});
        /// defer allocator.free(summaries);
        /// ```
        pub fn fetchAs(self: *Self, comptime R: type, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) ![]R {
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var items = std.ArrayList(R){};
            errdefer items.deinit(allocator);

            var mapper = result.mapper(R, .{ .allocator = allocator });
            while (try mapper.next()) |item| {
                try items.append(allocator, item);
            }
            return items.toOwnedSlice(allocator);
        }

        /// Execute query and return the raw pg.Result.
        /// Use this for complex queries with joins, subqueries, or when you need full control.
        /// The caller is responsible for calling result.deinit() when done.
        ///
        /// Example:
        /// ```zig
        /// var result = try User.query()
        ///     .innerJoin("posts", "users.id = posts.user_id")
        ///     .selectRaw("users.*, posts.title")
        ///     .fetchRaw(&pool, .{});
        /// defer result.deinit();
        ///
        /// while (try result.next()) |row| {
        ///     const user_id = row.get(i64, 0);
        ///     const post_title = row.get([]const u8, 1);
        ///     // ...
        /// }
        /// ```
        pub fn fetchRaw(self: *Self, db: *pg.Pool, args: anytype) !pg.Result {
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            return try db.queryOpts(sql, args, .{
                .column_names = true,
            });
        }

        /// Execute query and return first item or null.
        /// Returns an error if the query contains custom projections (JOINs, GROUP BY, aggregates, etc.).
        /// Use `firstAs` for custom result types or `firstRaw` for direct access.
        pub fn first(self: *Self, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) !?K {
            // Guard: reject queries with custom projections that can't map to K
            if (self.hasCustomProjection()) {
                return error.CustomProjectionRequiresFetchAs;
            }

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

        /// Execute query and return first item mapped to a custom result type, or null.
        ///
        /// Example:
        /// ```zig
        /// const UserStats = struct { id: i64, post_count: i64 };
        /// const stats = try User.query()
        ///     .select(&.{.id})
        ///     .selectAggregate(.count, .id, "post_count")
        ///     .where(.{ .field = .id, .operator = .eq, .value = "$1" })
        ///     .firstAs(UserStats, &pool, allocator, .{user_id});
        /// ```
        pub fn firstAs(self: *Self, comptime R: type, db: *pg.Pool, allocator: std.mem.Allocator, args: anytype) !?R {
            self.limit_val = 1;
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(R, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }
            return null;
        }

        /// Execute query and return first row as pg.QueryRow or null.
        /// The caller is responsible for calling row.deinit() when done.
        ///
        /// Example:
        /// ```zig
        /// if (try User.query()
        ///     .selectRaw("users.*, COUNT(posts.id) as post_count")
        ///     .innerJoin("posts", "users.id = posts.user_id")
        ///     .firstRaw(&pool, .{})) |row|
        /// {
        ///     defer row.deinit();
        ///     const name = row.get([]const u8, 1);
        ///     const post_count = row.get(i64, 2);
        /// }
        /// ```
        pub fn firstRaw(self: *Self, db: *pg.Pool, args: anytype) !?pg.Result {
            self.limit_val = 1;
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();
            // Check if there's at least one row
            if (try result.next()) |_| {
                return try db.queryOpts(sql, args, .{
                    .column_names = true,
                });
            }

            return null;
        }

        /// Count records matching the query
        pub fn count(self: *Self, db: *pg.Pool, args: anytype) !i64 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.appendSlice(temp_allocator, "SELECT COUNT(*) FROM ");
            try sql.appendSlice(temp_allocator, table_name);

            // JOIN clauses
            for (self.join_clauses.items) |join_sql| {
                try sql.appendSlice(temp_allocator, " ");
                try sql.appendSlice(temp_allocator, join_sql);
            }

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
                } else {
                    try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
                }
                try sql.appendSlice(temp_allocator, clause.sql);
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

        /// Check if any records match the query
        ///
        /// Example:
        /// ```zig
        /// const has_users = try User.query()
        ///     .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
        ///     .exists(&pool);
        /// ```
        pub fn exists(self: *Self, db: *pg.Pool, args: anytype) !bool {
            const c = try self.count(db, args);
            return c > 0;
        }

        /// Get a single column as a slice
        ///
        /// Example:
        /// ```zig
        /// const emails = try User.query().pluck(&pool, allocator, .email, .{});
        /// ```
        pub fn pluck(self: *Self, db: *pg.Pool, allocator: std.mem.Allocator, field: FE, args: anytype) ![][]const u8 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.writer(temp_allocator).print("SELECT {s} FROM {s}", .{ @tagName(field), table_name });

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
                } else {
                    try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
                }
                try sql.appendSlice(temp_allocator, clause.sql);
            }

            if (self.limit_val) |l| {
                var buf: [32]u8 = undefined;
                const _limit = try std.fmt.bufPrint(&buf, " LIMIT {d}", .{l});
                try sql.appendSlice(temp_allocator, _limit);
            }

            if (self.offset_val) |o| {
                var buf: [32]u8 = undefined;
                const _offset = try std.fmt.bufPrint(&buf, " OFFSET {d}", .{o});
                try sql.appendSlice(temp_allocator, _offset);
            }

            var result = try db.queryOpts(sql.items, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var items = std.ArrayList([]const u8){};
            errdefer items.deinit(allocator);

            while (try result.next()) |row| {
                const val = row.get([]const u8, 0);
                const dupe = try allocator.dupe(u8, val);
                try items.append(allocator, dupe);
            }

            return items.toOwnedSlice(allocator);
        }

        /// Get the sum of a column
        ///
        /// Example:
        /// ```zig
        /// const total = try Order.query().sum(&pool, .amount, .{});
        /// ```
        pub fn sum(self: *Self, db: *pg.Pool, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .sum, field, args);
        }

        /// Get the average of a column
        ///
        /// Example:
        /// ```zig
        /// const avg_rating = try Review.query().avg(&pool, .rating, .{});
        /// ```
        pub fn avg(self: *Self, db: *pg.Pool, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .avg, field, args);
        }

        /// Get the minimum value of a column
        ///
        /// Example:
        /// ```zig
        /// const min_price = try Product.query().min(&pool, .price, .{});
        /// ```
        pub fn min(self: *Self, db: *pg.Pool, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .min, field, args);
        }

        /// Get the maximum value of a column
        ///
        /// Example:
        /// ```zig
        /// const max_price = try Product.query().max(&pool, .price, .{});
        /// ```
        pub fn max(self: *Self, db: *pg.Pool, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .max, field, args);
        }

        fn aggregate(self: *Self, db: *pg.Pool, agg: AggregateType, field: FE, args: anytype) !f64 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.writer(temp_allocator).print("SELECT {s}({s}) FROM {s}", .{
                agg.toSql(),
                @tagName(field),
                table_name,
            });

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
                } else {
                    try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
                }
                try sql.appendSlice(temp_allocator, clause.sql);
            }

            var result = try db.queryOpts(sql.items, args, .{
                .column_names = true,
            });
            defer result.deinit();

            if (try result.next()) |row| {
                return row.get(?f64, 0) orelse 0.0;
            }
            return 0.0;
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

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
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

test "query builder with pagination" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(3, 25);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 25 OFFSET 50", sql);
}

test "query builder with distinct" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.distinct().select(&.{.name});
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT DISTINCT name FROM users", sql);
}

test "query builder with join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.innerJoin("posts", "users.id = posts.user_id").where(.{
        .field = .id,
        .operator = .eq,
        .value = "$1",
    });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users INNER JOIN posts ON users.id = posts.user_id WHERE id = $1", sql);
}

test "query builder with group by and having" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, status };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.selectRaw("status, COUNT(*) as count").groupBy(&.{.status}).having("COUNT(*) > 5");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT status, COUNT(*) as count FROM orders GROUP BY status HAVING COUNT(*) > 5", sql);
}

test "query builder with whereBetween" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        age: i32,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, age };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereBetween(.age, "$1", "$2");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age BETWEEN $1 AND $2", sql);
}

test "query builder with whereIn" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereIn(.status, &.{ "'active'", "'pending'" });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE status IN ('active', 'pending')", sql);
}

test "query builder with whereNotIn" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotIn(.status, &.{ "'deleted'", "'banned'" });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE status NOT IN ('deleted', 'banned')", sql);
}

test "query builder with whereNotBetween" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        age: i32,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, age };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotBetween(.age, "13", "17");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age NOT BETWEEN 13 AND 17", sql);
}

test "query builder with whereRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, created_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereRaw("created_at > NOW() - INTERVAL '7 days'");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE created_at > NOW() - INTERVAL '7 days'", sql);
}

test "query builder with orWhereRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        role: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, role };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.where(.{ .field = .role, .operator = .eq, .value = "'user'" })
        .orWhereRaw("role = 'admin' AND id < 100");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE role = 'user' OR role = 'admin' AND id < 100", sql);
}

test "query builder with whereNull" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        verified_at: ?[]const u8, // Using verified_at instead of deleted_at to avoid soft delete auto-filter

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, verified_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNull(.verified_at);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE verified_at IS NULL", sql);
}

test "query builder with whereNotNull" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        email_verified_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, email_verified_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotNull(.email_verified_at);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE email_verified_at IS NOT NULL", sql);
}

test "query builder with whereExists" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who have at least one order
    _ = query.whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id)", sql);
}

test "query builder with whereNotExists" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who have never been banned
    _ = query.whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE NOT EXISTS (SELECT 1 FROM bans WHERE bans.user_id = users.id)", sql);
}

test "query builder with whereSubquery - IN operator" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who are premium members
    // SQL: SELECT * FROM users WHERE id IN (SELECT user_id FROM premium_members)
    _ = query.whereSubquery(.id, .in, "SELECT user_id FROM premium_members");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE id IN (SELECT user_id FROM premium_members)", sql);
}

test "query builder with whereSubquery - NOT IN operator" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who are NOT banned
    _ = query.whereSubquery(.id, .not_in, "SELECT user_id FROM banned_users");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM banned_users)", sql);
}

test "query builder with whereSubquery - comparison operator" {
    const allocator = std.testing.allocator;

    const Product = struct {
        id: i64,
        price: f64,

        pub fn tableName() []const u8 {
            return "products";
        }
    };

    const FieldEnum = enum { id, price };
    const ProductQuery = QueryBuilder(Product, Product, FieldEnum);
    var query = ProductQuery.init();
    defer query.deinit();
    // Find products priced above average
    // SQL: SELECT * FROM products WHERE price > (SELECT AVG(price) FROM products)
    _ = query.whereSubquery(.price, .gt, "SELECT AVG(price) FROM products");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM products WHERE price > (SELECT AVG(price) FROM products)", sql);
}

test "query builder with selectAggregate" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        amount: f64,
        user_id: i64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, amount, user_id };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total_spent")
        .selectAggregate(.count, .id, "order_count")
        .groupBy(&.{.user_id});
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total_spent, COUNT(id) AS order_count FROM orders GROUP BY user_id", sql);
}

test "query builder with multiple orderBy" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, created_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.orderBy(.{ .field = .created_at, .direction = .desc })
        .orderBy(.{ .field = .name, .direction = .asc });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users ORDER BY created_at DESC, name ASC", sql);
}

test "query builder with orderByRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.orderByRaw("RANDOM()");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users ORDER BY RANDOM()", sql);
}

test "query builder with groupByRaw" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        created_at: []const u8,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, created_at, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.selectRaw("DATE(created_at) as order_date, SUM(amount) as daily_total")
        .groupByRaw("DATE(created_at)");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT DATE(created_at) as order_date, SUM(amount) as daily_total FROM orders GROUP BY DATE(created_at)", sql);
}

test "query builder with havingAggregate" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    // Find users who have spent more than $1000 total
    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{.user_id})
        .havingAggregate(.sum, .amount, .gt, "1000");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id HAVING SUM(amount) > 1000", sql);
}

test "query builder with left join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Get all users and their posts (if any)
    _ = query.leftJoin("posts", "users.id = posts.user_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LEFT JOIN posts ON users.id = posts.user_id", sql);
}

test "query builder with right join" {
    const allocator = std.testing.allocator;

    const Post = struct {
        id: i64,
        user_id: i64,

        pub fn tableName() []const u8 {
            return "posts";
        }
    };

    const FieldEnum = enum { id, user_id };
    const PostQuery = QueryBuilder(Post, Post, FieldEnum);
    var query = PostQuery.init();
    defer query.deinit();
    _ = query.rightJoin("users", "posts.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM posts RIGHT JOIN users ON posts.user_id = users.id", sql);
}

test "query builder with full outer join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.fullJoin("orders", "users.id = orders.user_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users FULL OUTER JOIN orders ON users.id = orders.user_id", sql);
}

test "query builder with multiple joins" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Join users with posts and comments
    _ = query.innerJoin("posts", "users.id = posts.user_id")
        .leftJoin("comments", "posts.id = comments.post_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users INNER JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id", sql);
}

test "query builder with offset only" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.offset(10);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users OFFSET 10", sql);
}

test "query builder with limit and offset" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.limit(20).offset(40);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 20 OFFSET 40", sql);
}

test "query builder paginate with page 0 defaults to page 1" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(0, 10); // Page 0 should become page 1
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 10 OFFSET 0", sql);
}

test "query builder paginate page 1" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(1, 15);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 15 OFFSET 0", sql);
}

test "query builder with soft delete - withDeleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Include soft-deleted records
    _ = query.withDeleted();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    // No WHERE deleted_at IS NULL clause
    try std.testing.expectEqualStrings("SELECT * FROM users", sql);
}

test "query builder with soft delete - default excludes deleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    // Should automatically filter out soft-deleted records
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE deleted_at IS NULL", sql);
}

test "query builder with soft delete - onlyDeleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Only get soft-deleted records
    _ = query.onlyDeleted();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE deleted_at IS NOT NULL", sql);
}

test "query builder with all operators" {
    const allocator = std.testing.allocator;

    const Product = struct {
        id: i64,
        name: []const u8,
        price: f64,

        pub fn tableName() []const u8 {
            return "products";
        }
    };

    const FieldEnum = enum { id, name, price };
    const ProductQuery = QueryBuilder(Product, Product, FieldEnum);

    // Test eq (=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .id, .operator = .eq, .value = "1" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE id = 1", sql);
    }

    // Test neq (!=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .id, .operator = .neq, .value = "1" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE id != 1", sql);
    }

    // Test gt (>)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .gt, .value = "100" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price > 100", sql);
    }

    // Test gte (>=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .gte, .value = "100" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price >= 100", sql);
    }

    // Test lt (<)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .lt, .value = "50" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price < 50", sql);
    }

    // Test lte (<=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .lte, .value = "50" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price <= 50", sql);
    }

    // Test like
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .name, .operator = .like, .value = "'%phone%'" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE name LIKE '%phone%'", sql);
    }

    // Test ilike (case-insensitive like)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .name, .operator = .ilike, .value = "'%PHONE%'" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE name ILIKE '%PHONE%'", sql);
    }
}

test "query builder complex query with all features" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        status: []const u8,
        amount: f64,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, status, amount, created_at };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    // Complex query: Get order statistics per user for completed orders
    // with total > 100, sorted by total descending, page 2 with 10 per page
    _ = query
        .distinct()
        .select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .selectAggregate(.count, .id, "order_count")
        .innerJoin("users", "orders.user_id = users.id")
        .where(.{ .field = .status, .operator = .eq, .value = "'completed'" })
        .whereBetween(.amount, "10", "10000")
        .groupBy(&.{.user_id})
        .havingAggregate(.sum, .amount, .gt, "100")
        .orderBy(.{ .field = .user_id, .direction = .asc })
        .paginate(2, 10);

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    const expected = "SELECT DISTINCT user_id, SUM(amount) AS total, COUNT(id) AS order_count " ++
        "FROM orders INNER JOIN users ON orders.user_id = users.id " ++
        "WHERE status = 'completed' AND amount BETWEEN 10 AND 10000 " ++
        "GROUP BY user_id HAVING SUM(amount) > 100 " ++
        "ORDER BY user_id ASC LIMIT 10 OFFSET 10";

    try std.testing.expectEqualStrings(expected, sql);
}

test "query builder with multiple having clauses" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{.user_id})
        .having("COUNT(*) > 5")
        .having("SUM(amount) < 10000");

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id HAVING COUNT(*) > 5 AND SUM(amount) < 10000", sql);
}

test "query builder with multiple group by fields" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        status: []const u8,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, status, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    _ = query.select(&.{ .user_id, .status })
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{ .user_id, .status });

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, status, SUM(amount) AS total FROM orders GROUP BY user_id, status", sql);
}

test "query builder chaining or conditions" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        role: []const u8,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, role, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();

    // WHERE role = 'admin' OR role = 'moderator' OR role = 'superuser'
    _ = query.where(.{ .field = .role, .operator = .eq, .value = "'admin'" })
        .orWhere(.{ .field = .role, .operator = .eq, .value = "'moderator'" })
        .orWhere(.{ .field = .role, .operator = .eq, .value = "'superuser'" });

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE role = 'admin' OR role = 'moderator' OR role = 'superuser'", sql);
}
