# Transaction Documentation

The generated models include built-in support for database transactions.

## Usage

Transactions are handled via the `Transaction` struct, which wraps a database connection and provides transaction-aware CRUD methods.

```zig
const Transaction = @import("transaction.zig").Transaction;

// 1. Start a transaction
var tx = try Transaction(Users).begin(conn);
// Ensure rollback on error
defer tx.deinit();

// 2. Perform operations
const user_id = try tx.insert(allocator, .{
    .email = "test@example.com",
});

// 3. Commit
try tx.commit();
```

## Methods

### `begin(conn: *pg.Conn) !Self`

Starts a new transaction (`BEGIN`).

- Requires a `*pg.Conn`, not a `*pg.Pool`. You must acquire a connection from the pool first.

### `commit() !void`

Commits the transaction (`COMMIT`).

- Marks the transaction as committed.

### `rollback() !void`

Rolls back the transaction (`ROLLBACK`).

- Marks the transaction as rolled back.

### `deinit()`

Automatically rolls back the transaction if it hasn't been committed or rolled back yet.

- Designed to be used with `defer`.

## Transaction-Aware CRUD

The `Transaction` struct provides methods that mirror the `BaseModel` CRUD operations but execute within the transaction context.

- `insert(allocator, data)`
- `update(id, data)`
- `softDelete(id)`
- `hardDelete(id)`

> **Note**: Read operations (`findById`, `findAll`) should be performed directly on the connection (`conn`) if needed within the transaction, or using the standard model methods if outside.
