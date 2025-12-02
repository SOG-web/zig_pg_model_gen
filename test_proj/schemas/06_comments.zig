// Comment table schema definition
// Comments on posts - demonstrates multiple belongsTo relationships

const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Build function called by the registry generator
pub fn build(t: *TableSchema) void {
    // Primary key - UUID auto-generated
    t.uuid(.{
        .name = "id",
        .primary_key = true,
        .unique = true,
        .create_input = .excluded,
        .update_input = false,
    });

    // Foreign key to posts table
    t.uuid(.{
        .name = "post_id",
    });

    // Foreign key to users table (comment author)
    t.uuid(.{
        .name = "user_id",
    });

    // Parent comment for nested replies - optional (null for top-level comments)
    t.uuid(.{
        .name = "parent_id",
        .not_null = false,
        .create_input = .optional,
    });

    // Comment content - required
    t.string(.{
        .name = "content",
    });

    // Is approved flag (for moderation)
    t.boolean(.{
        .name = "is_approved",
        .default_value = "true",
        .create_input = .optional,
    });

    // Like count
    t.integer(.{
        .name = "like_count",
        .default_value = "0",
        .create_input = .excluded,
        .update_input = true,
    });

    // Timestamps
    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    t.dateTime(.{
        .name = "updated_at",
        .create_input = .excluded,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // Soft delete support
    t.dateTime(.{
        .name = "deleted_at",
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
    });

    // BelongsTo: Comment belongs to a Post
    t.belongsTo(.{
        .name = "comment_post",
        .column = "post_id",
        .references_table = "posts",
        .on_delete = .cascade,
    });

    // BelongsTo: Comment belongs to a User (author)
    t.belongsTo(.{
        .name = "comment_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });

    // Self-referential: Comment can have a parent comment (for replies)
    t.belongsTo(.{
        .name = "comment_parent",
        .column = "parent_id",
        .references_table = "comments",
        .on_delete = .cascade,
    });

    // HasMany: Comment has many replies (child comments)
    t.hasMany(.{
        .name = "comment_replies",
        .foreign_table = "comments",
        .foreign_column = "parent_id",
    });

    // Indexes for common queries
    t.addIndexes(&.{
        .{
            .name = "idx_comments_post",
            .columns = &.{"post_id"},
            .unique = false,
        },
        .{
            .name = "idx_comments_user",
            .columns = &.{"user_id"},
            .unique = false,
        },
        .{
            .name = "idx_comments_parent",
            .columns = &.{"parent_id"},
            .unique = false,
        },
    });
}
