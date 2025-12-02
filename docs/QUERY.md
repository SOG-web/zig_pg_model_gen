# Query Builder Documentation

The `QueryBuilder` provides a fluent API for constructing complex SQL queries in a type-safe manner.

> [!NOTE]
> Due to [ZLS issue #2515](https://github.com/zigtools/zls/issues/2515), auto-complete for `Field` enums (e.g., `.id`, `.name`) does not work in editors. However, **type safety is strictly enforced**: using an invalid field name will result in a compile-time error.

## Usage

```zig
const users = try Users.query()
    .where(.{
        .field = .age,
        .operator = .gt,
        .value = "$1",
    })
    .orderBy(.{
        .field = .created_at,
        .direction = .desc,
    })
    .limit(10)
    .fetch(&pool, allocator, .{18});
```

## SELECT Methods

### `select(fields: []const Field)`

Specifies which columns to retrieve. Defaults to `SELECT *` if not called.

```zig
.select(&.{ .id, .name })
```

### `distinct()`

Enable DISTINCT on the query.

```zig
.distinct().select(&.{ .email })
```

### `selectAggregate(agg: AggregateType, field: Field, alias: []const u8)`

Select with an aggregate function.

```zig
.selectAggregate(.sum, .amount, "total_amount")
```

### `selectRaw(raw_sql: []const u8)`

Select raw SQL expression.

```zig
.selectRaw("COUNT(*) AS total")
```

## WHERE Methods

### `where(clause: WhereClause)`

Adds a `WHERE` clause. Multiple calls are combined with `AND`.

```zig
.where(.{
    .field = .status,
    .operator = .eq,
    .value = "$1",
})
```

### `orWhere(clause: WhereClause)`

Adds an `OR` condition to the `WHERE` clause.

```zig
.orWhere(.{
    .field = .status,
    .operator = .eq,
    .value = "$2",
})
```

### `whereBetween(field: Field, low: []const u8, high: []const u8)`

Adds a BETWEEN clause.

```zig
.whereBetween(.age, "$1", "$2")
```

### `whereNotBetween(field: Field, low: []const u8, high: []const u8)`

Adds a NOT BETWEEN clause.

```zig
.whereNotBetween(.age, "13", "17")
```

### `whereIn(field: Field, values: []const []const u8)`

Adds a WHERE IN clause.

```zig
.whereIn(.status, &.{ "'active'", "'pending'" })
```

### `whereNotIn(field: Field, values: []const []const u8)`

Adds a WHERE NOT IN clause.

```zig
.whereNotIn(.status, &.{ "'deleted'", "'banned'" })
```

### `whereRaw(raw_sql: []const u8)`

Adds a raw WHERE clause.

```zig
.whereRaw("created_at > NOW() - INTERVAL '7 days'")
```

### `orWhereRaw(raw_sql: []const u8)`

Adds an OR raw WHERE clause.

```zig
.orWhereRaw("status = 'vip' OR role = 'admin'")
```

### `whereNull(field: Field)`

Adds a WHERE NULL clause.

```zig
.whereNull(.deleted_at)
```

### `whereNotNull(field: Field)`

Adds a WHERE NOT NULL clause.

```zig
.whereNotNull(.email_verified_at)
```

### `whereExists(subquery: []const u8)`

Adds a WHERE EXISTS subquery.

```zig
.whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id")
```

### `whereNotExists(subquery: []const u8)`

Adds a WHERE NOT EXISTS subquery.

```zig
.whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id")
```

### `whereSubquery(field: Field, operator: Operator, subquery: []const u8)`

Adds a subquery in WHERE clause.

```zig
.whereSubquery(.id, .in, "SELECT user_id FROM premium_users")
```

## JOIN Methods

### `join(join_type: JoinType, table: []const u8, on_clause: []const u8)`

Adds a JOIN clause.

```zig
.join(.inner, "posts", "users.id = posts.user_id")
```

### `innerJoin(table: []const u8, on_clause: []const u8)`

Adds an INNER JOIN clause.

```zig
.innerJoin("posts", "users.id = posts.user_id")
```

### `leftJoin(table: []const u8, on_clause: []const u8)`

Adds a LEFT JOIN clause.

```zig
.leftJoin("posts", "users.id = posts.user_id")
```

### `rightJoin(table: []const u8, on_clause: []const u8)`

Adds a RIGHT JOIN clause.

```zig
.rightJoin("posts", "users.id = posts.user_id")
```

### `fullJoin(table: []const u8, on_clause: []const u8)`

Adds a FULL OUTER JOIN clause.

```zig
.fullJoin("orders", "users.id = orders.user_id")
```

## GROUP BY / HAVING Methods

### `groupBy(fields: []const Field)`

Adds GROUP BY clause.

```zig
.groupBy(&.{ .status, .role })
```

### `groupByRaw(raw_sql: []const u8)`

Adds GROUP BY with raw SQL.

```zig
.groupByRaw("DATE(created_at)")
```

### `having(condition: []const u8)`

Adds HAVING clause.

```zig
.having("COUNT(*) > $1")
```

### `havingAggregate(agg: AggregateType, field: Field, operator: Operator, value: []const u8)`

Adds HAVING with aggregate function.

```zig
.havingAggregate(.count, .id, .gt, "$1")
```

## ORDER BY Methods

### `orderBy(clause: OrderByClause)`

Sets the `ORDER BY` clause.

```zig
.orderBy(.{
    .field = .created_at,
    .direction = .desc, // .asc or .desc
})
```

### `orderByRaw(raw_sql: []const u8)`

Adds raw ORDER BY clause.

```zig
.orderByRaw("RANDOM()")
```

## LIMIT / OFFSET Methods

### `limit(n: u64)`

Sets the `LIMIT` clause.

```zig
.limit(20)
```

### `offset(n: u64)`

Sets the `OFFSET` clause.

```zig
.offset(10)
```

### `paginate(page: u64, per_page: u64)`

Paginate results (convenience method for limit + offset).

```zig
.paginate(2, 20) // Page 2 with 20 items per page
```

## Soft Delete Methods

### `withDeleted()`

Includes soft-deleted records (where `deleted_at` is not null) in the results.

```zig
.withDeleted()
```

### `onlyDeleted()`

Only get soft-deleted records.

```zig
.onlyDeleted()
```

## Execution Methods

### `fetch(db: *pg.Pool, allocator: Allocator, args: anytype) ![]T`

Executes the query and returns a slice of models.

> [!IMPORTANT] > `fetch` will return `error.CustomProjectionRequiresFetchAs` if your query contains any of the following:
>
> - **JOINs** (`innerJoin`, `leftJoin`, `rightJoin`, `fullJoin`)
> - **GROUP BY** clauses (`groupBy`, `groupByRaw`)
> - **HAVING** clauses (`having`, `havingAggregate`)
> - **Aggregate functions** (`selectAggregate`)
> - **Raw selects with aliases** (e.g., `selectRaw("COUNT(*) AS total")`)
> - **Table-prefixed columns** (e.g., `selectRaw("users.id")`)
>
> For these cases, use `fetchAs` with a custom struct or `fetchRaw` for direct result access.

### `fetchAs(comptime R: type, db: *pg.Pool, allocator: Allocator, args: anytype) ![]R`

Executes the query and returns a slice of a custom result type. Use this when your query produces a different shape than the model (e.g., with JOINs, aggregates, or custom selects).

```zig
const UserSummary = struct {
    id: i64,
    total_posts: i64
};

const summaries = try Users.query()
    .select(&.{.id})
    .selectAggregate(.count, .id, "total_posts")
    .groupBy(&.{.id})
    .fetchAs(UserSummary, &pool, allocator, .{});
defer allocator.free(summaries);
```

### `fetchRaw(db: *pg.Pool, args: anytype) !pg.Result`

Executes the query and returns the raw `pg.Result`. Use this for complex queries with JOINs, subqueries, or when you need full control over result processing.

> [!NOTE]
> The caller is responsible for calling `result.deinit()` when done.

```zig
var result = try Users.query()
    .innerJoin("posts", "users.id = posts.user_id")
    .selectRaw("users.*, posts.title")
    .fetchRaw(&pool, .{});
defer result.deinit();

while (try result.next()) |row| {
    const user_id = row.get(i64, 0);
    const user_name = row.get([]const u8, 1);
    const post_title = row.get([]const u8, 2);
    // ...
}
```

### `first(db: *pg.Pool, allocator: Allocator, args: anytype) !?T`

Executes the query with `LIMIT 1` and returns the first result or `null`.

> [!IMPORTANT]
> Like `fetch`, this method will return `error.CustomProjectionRequiresFetchAs` if the query contains JOINs, GROUP BY, aggregates, or other custom projections. Use `firstAs` or `firstRaw` instead.

### `firstAs(comptime R: type, db: *pg.Pool, allocator: Allocator, args: anytype) !?R`

Executes the query with `LIMIT 1` and returns the first result mapped to a custom type, or `null`.

```zig
const UserStats = struct { id: i64, post_count: i64 };

const stats = try Users.query()
    .select(&.{.id})
    .selectAggregate(.count, .id, "post_count")
    .where(.{ .field = .id, .operator = .eq, .value = "$1" })
    .groupBy(&.{.id})
    .firstAs(UserStats, &pool, allocator, .{user_id});
```

### `firstRaw(db: *pg.Pool, args: anytype) !?pg.Result`

Executes the query with `LIMIT 1` and returns the raw `pg.Result`, or `null` if no rows found.

> [!NOTE]
> The caller is responsible for calling `result.deinit()` when done.

### `count(db: *pg.Pool, args: anytype) !i64`

Executes a `COUNT(*)` query based on the current filters.

### `exists(db: *pg.Pool, args: anytype) !bool`

Check if any records match the query.

```zig
const has_users = try Users.query()
    .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
    .exists(&pool, .{});
```

### `pluck(db: *pg.Pool, allocator: Allocator, field: Field, args: anytype) ![][]const u8`

Get a single column as a slice.

```zig
const emails = try Users.query().pluck(&pool, allocator, .email, .{});
```

## Aggregate Methods

### `sum(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the sum of a column.

```zig
const total = try Orders.query().sum(&pool, .amount, .{});
```

### `avg(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the average of a column.

```zig
const avg_rating = try Reviews.query().avg(&pool, .rating, .{});
```

### `min(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the minimum value of a column.

```zig
const min_price = try Products.query().min(&pool, .price, .{});
```

### `max(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the maximum value of a column.

```zig
const max_price = try Products.query().max(&pool, .price, .{});
```

## SQL Generation

### `buildSql(allocator: Allocator) ![]const u8`

Constructs and returns the raw SQL string that will be executed. Useful for debugging or manual execution.

```zig
const sql = try query.buildSql(allocator);
defer allocator.free(sql);
```

## Types

### `Operator`

- `.eq` (`=`)
- `.neq` (`!=`)
- `.gt` (`>`)
- `.gte` (`>=`)
- `.lt` (`<`)
- `.lte` (`<=`)
- `.like` (`LIKE`)
- `.ilike` (`ILIKE`)
- `.in` (`IN`)
- `.not_in` (`NOT IN`)
- `.is_null` (`IS NULL`)
- `.is_not_null` (`IS NOT NULL`)
- `.between` (`BETWEEN`)
- `.not_between` (`NOT BETWEEN`)

### `WhereClause`

```zig
struct {
    field: Field,
    operator: Operator,
    value: ?[]const u8 = null, // Optional for IS NULL / IS NOT NULL
}
```

### `OrderByClause`

```zig
struct {
    field: Field,
    direction: enum { asc, desc },
}
```

### `JoinType`

- `.inner` (`INNER JOIN`)
- `.left` (`LEFT JOIN`)
- `.right` (`RIGHT JOIN`)
- `.full` (`FULL OUTER JOIN`)

### `AggregateType`

- `.count` (`COUNT`)
- `.sum` (`SUM`)
- `.avg` (`AVG`)
- `.min` (`MIN`)
- `.max` (`MAX`)

## Complex Query Examples

### Using `fetchAs` for Aggregated Results

When using JOINs, GROUP BY, or aggregates, you must use `fetchAs` with a custom struct:

```zig
// Define a struct that matches the query's output shape
const OrderStats = struct {
    user_id: i64,
    total: f64,
    order_count: i64,
};

var query = Orders.query();
defer query.deinit();

const results = try query
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
    .paginate(2, 10)
    .fetchAs(OrderStats, &pool, allocator, .{});  // Note: fetchAs, not fetch
defer allocator.free(results);

for (results) |stats| {
    std.debug.print("User {d}: total={d}, orders={d}\n", .{
        stats.user_id, stats.total, stats.order_count
    });
}
```

Generates:

```sql
SELECT DISTINCT user_id, SUM(amount) AS total, COUNT(id) AS order_count
FROM orders INNER JOIN users ON orders.user_id = users.id
WHERE status = 'completed' AND amount BETWEEN 10 AND 10000
GROUP BY user_id HAVING SUM(amount) > 100
ORDER BY user_id ASC LIMIT 10 OFFSET 10
```

### Using `fetchRaw` for Maximum Flexibility

For complex JOINs where you need to access columns from multiple tables:

```zig
var result = try Users.query()
    .selectRaw("users.id, users.name, posts.title, posts.created_at")
    .innerJoin("posts", "users.id = posts.user_id")
    .where(.{ .field = .id, .operator = .eq, .value = "$1" })
    .fetchRaw(&pool, .{user_id});
defer result.deinit();

while (try result.next()) |row| {
    const id = row.get(i64, 0);
    const name = row.get([]const u8, 1);
    const title = row.get([]const u8, 2);
    const created_at = row.get(i64, 3);
    // Process the row...
}
```

### Simple Query with `fetch`

For basic queries without JOINs or aggregates, use `fetch` directly:

```zig
const active_users = try Users.query()
    .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
    .orderBy(.{ .field = .created_at, .direction = .desc })
    .limit(10)
    .fetch(&pool, allocator, .{});
defer allocator.free(active_users);

for (active_users) |user| {
    std.debug.print("User: {s}\n", .{user.name});
}
```
