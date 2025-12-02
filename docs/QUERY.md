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

### `first(db: *pg.Pool, allocator: Allocator, args: anytype) !?T`

Executes the query with `LIMIT 1` and returns the first result or `null`.

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

## Complex Query Example

```zig
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
    .fetch(&pool, allocator, .{});
defer allocator.free(results);
```

Generates:

```sql
SELECT DISTINCT user_id, SUM(amount) AS total, COUNT(id) AS order_count
FROM orders INNER JOIN users ON orders.user_id = users.id
WHERE status = 'completed' AND amount BETWEEN 10 AND 10000
GROUP BY user_id HAVING SUM(amount) > 100
ORDER BY user_id ASC LIMIT 10 OFFSET 10
```
