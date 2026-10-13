# Smart Properties

Type-safe query expressions using `Prop<T>`. This allows you to write queries that are checked at compile time, eliminating "magic strings".

> 📦 **Example**: [Web.SmartPropsDemo](../../../Examples/Web.SmartPropsDemo/)

## What are Smart Properties?

Smart Properties are entity properties declared with the `Prop<T>` record type (or its aliases like `StringType`, `IntType`, etc.) instead of plain Delphi types (`string`, `Integer`).

They carry **metadata** at runtime — property name, type info, and expression-building capability — that makes type-safe query expressions possible.

```pascal
type
  [Table('users')]
  TUser = class
  private
    FName: StringType;   // ✅ Smart Property — carries metadata
    FAge:  IntType;      // ✅ Smart Property
    FEmail: string;      // ⚠️ Plain property — no metadata for expressions
  public
    property Name: StringType read FName write FName;
    property Age:  IntType    read FAge  write FAge;
    property Email: string    read FEmail write FEmail;
  end;
```

> [!IMPORTANT]
> Only properties declared as `Prop<T>` (or its aliases) carry metadata.  
> `Nullable<T>` is **not** a Smart Property — it only represents the nullability state of a value and does not provide expression metadata.

## Type Aliases

For cleaner entity definitions, use the following aliases from `Dext.Core.SmartTypes`:

| Type | Delphi Equivalent |
|------|-------------------|
| `StringType` | `string` |
| `IntType` | `Integer` |
| `Int64Type` | `Int64` |
| `BoolType` | `Boolean` |
| `DateTimeType` | `TDateTime` |
| `CurrencyType` | `Currency` |

For custom types (e.g., enums), define your own alias:

```pascal
type
  StatusType = Prop<TOrderStatus>;
```

## Querying with Smart Properties

### Pattern 1: `Props` class function (Recommended)

The cleanest pattern is to add a `class function Props` (or `class function Prototype`) to your entity that returns the companion metadata class. This avoids using `Prototype.Entity<T>` at the call site and keeps the knowledge of the metadata class encapsulated in the entity itself.

**Entity declaration:**

```pascal
type
  TUserType = class(TEntityType<TUser>)
  public
    class var Name:  TPropExpression;
    class var Age:   TPropExpression;
    class var Email: TPropExpression;
    class constructor Create;
  end;

  [Table('users')]
  TUser = class
  private
    FName: StringType;
    FAge:  IntType;
    FEmail: string;
  public
    property Name:  StringType read FName write FName;
    property Age:   IntType    read FAge  write FAge;
    property Email: string     read FEmail write FEmail;

    /// Returns the metadata companion for type-safe query expressions.
    class function Props: TUserType; static; inline;
  end;
```

**Implementation:**

```pascal
class function TUser.Props: TUserType;
begin
  Result := TUserType.Default;
end;

class constructor TUserType.Create;
begin
  Name  := TPropExpression.Create('Name');
  Age   := TPropExpression.Create('Age');
  Email := TPropExpression.Create('Email');
end;
```

**Usage:**

```pascal
var u := TUser.Props;

var Adults := Context.Users
  .Where(u.Age > 18)
  .OrderBy(u.Name.Asc)
  .ToList;
```

> [!TIP]
> You can also name it `class function Prototype` if you prefer:
> ```pascal
> var u := TUser.Prototype;
> ```

### Pattern 2: `Prototype.Entity<T>` (No changes to entity)

When the entity already has `Prop<T>` fields, you can use `Prototype.Entity<T>` directly without defining any companion class:

```pascal
uses Dext.Entity.Prototype;

var u := Prototype.Entity<TUser>;
var Adults := Context.Users
  .Where(u.Age > 18)
  .ToList;
```

> [!WARNING]
> This pattern **only works if the entity has at least one `Prop<T>` field**.  
> If the entity uses only plain Delphi types, `Prototype.Entity<T>` will raise an exception at runtime.  
> See [Entities without Smart Properties](#entities-without-smart-properties) below.

## Entities without Smart Properties

### Why they exist

Many entities in existing codebases were written with plain Delphi types:

```pascal
// Plain entity — no Smart Properties
[Table('products')]
TProduct = class
  property Id:    Integer read FId write FId;
  property Name:  string  read FName write FName;
  property Price: Double  read FPrice write FPrice;
end;
```

These entities are **fully functional** for CRUD, `ToList`, `Find`, `Any`, and `Count`. No Smart Properties are required for those operations.

### What happens with expressions

Calling `Prototype.Entity<TProduct>` on a plain entity raises a descriptive exception at runtime:

```
Entity "TProduct" does not contain any Smart Properties (Prop<T>).
Expressions using Prototype.Entity<TProduct> will fail because standard Delphi
properties compare at compile-time.
To query this entity, please use its metadata class (inheriting from
TEntityType<TProduct>) or string-based properties (e.g. Prop('PropertyName')).
```

### Solutions for plain entities

**Option A — Add a companion `TEntityType<T>` class with a `Props` or `Prototype` class function (recommended)**

This is the cleanest approach: create a companion class and expose it directly from the entity. This gives developers a familiar, discoverable API without touching the entity's plain properties:

```pascal
type
  TProductType = class(TEntityType<TProduct>)
  public
    class var Name:  TPropExpression;
    class var Price: TPropExpression;
    class constructor Create;
  end;

  TProduct = class
  public
    property Id:    Integer read FId write FId;
    property Name:  string  read FName write FName;
    property Price: Double  read FPrice write FPrice;

    // Expose metadata directly from the entity
    class function Props: TProductType; static; inline;
  end;
```

Usage:

```pascal
var p := TProduct.Props;

var Cheap := Context.Products
  .Where(p.Price < 10)
  .ToList;
```

**Option B — Use string-based expressions**

For ad-hoc queries without creating a companion class, use `Prop('PropertyName')`:

```pascal
var Cheap := Context.Products
  .Where(Prop('Price') < 10)
  .ToList;
```

> [!CAUTION]
> String-based expressions are not verified at compile time. Typos in property names will only surface as runtime errors.

## Return-all queries always work

Querying **all records** without a `Where` clause never requires Smart Properties:

```pascal
// ✅ Always works, regardless of property types
var All := Context.Products.ToList;
var Any := Context.Products.Any;
var N   := Context.Products.Count;
```

Only `.Where(expression)` and `.OrderBy(prop)` benefit from Smart Properties.

## Supported Operations

### Comparisons
- `=`, `<>`, `>`, `>=`, `<`, `<=`
- `In([V1, V2])`, `NotIn([V1, V2])`
- `IsNull`, `IsNotNull`

### String Logic
- `Contains('text')`
- `StartsWith('text')`
- `EndsWith('text')`
- `Like('%text%')`

`Contains`, `StartsWith` and `EndsWith` match their value literally: Dext escapes `%`, `_` and the escape character, and sends the pattern as a **parameter**. `Like` takes the pattern as you write it.

### Prefix search and indexes

`EndsWith` and `Contains` start with a wildcard, so no database can answer them from a B-tree index. `StartsWith` can, but whether it does depends on the database, not on Dext. Measured on one million rows with server-side parameters on Firebird 5, PostgreSQL 14 and MariaDB, and from the query plan on SQLite 3.50:

| Database | SQL generated | Uses a plain index? | What you need |
|---|---|---|---|
| Firebird | `col STARTING WITH :p` | Yes | Nothing |
| MariaDB / MySQL | `col LIKE :p ESCAPE '!'` | Yes (range scan) | Nothing |
| PostgreSQL | `col LIKE :p ESCAPE '!'` | **No**, unless the database collation is `C` | A prefix-capable index (below) |
| SQLite | `col LIKE :p ESCAPE '!'` | Only if the index is `COLLATE NOCASE` | A `NOCASE` index, or `PRAGMA case_sensitive_like = ON` with a plain index |

**PostgreSQL.** With a linguistic collation (`en_US.UTF-8`, `Italian_Italy.1252`, ...) a plain B-tree index is never used for `LIKE`, not even with a literal pattern: on 1,000,000 rows that is a sequential scan of about 140 ms instead of about 1 ms. Add a second index that can serve prefix matches, next to the plain one. Keep the plain one: the prefix index does not serve `ORDER BY`, nor comparisons in the database collation.

```sql
CREATE INDEX ix_customers_name_prefix ON customers (name COLLATE "C");
-- or
CREATE INDEX ix_customers_name_prefix ON customers (name varchar_pattern_ops);
```

`CreateIndex` in a migration quotes every column name, so write this one with `Sql`:

```pascal
Builder.Sql('CREATE INDEX ix_customers_name_prefix ON customers (name COLLATE "C")');
```

PostgreSQL uses it with custom plans, which is what it picks for a reused prepared statement in the default `plan_cache_mode = auto`. Under `force_generic_plan` no `LIKE` uses an index.

**Do not replace `StartsWith` with a range** (`col >= :a AND col < :b`). It uses the plain index, but returns wrong rows: with a linguistic collation on PostgreSQL (`'ab'` found 11 rows instead of 9, `'Ab'` 9 instead of 1), and on MariaDB with trailing spaces (PAD SPACE collations). On PostgreSQL 14, `starts_with(col, $1)` and `col ^@ $1` do not use a B-tree either.

### Boolean Logic
```pascal
var u := TUser.Props;
Context.Users.Where((u.Age > 18) and (u.IsActive = True)).ToList;
```

## Why use Smart Properties?

1. **Refactoring Safety**: Renaming a property is caught at compile time across all queries.
2. **Readability**: Code reads close to SQL yet remains 100% Pascal.
3. **IDE Support**: Code completion works for all available fields in the query.
4. **Discoverability**: `TUser.Props` is self-documenting — developers immediately know which fields are queryable.

---

## Nullable Smart Properties

When a database column is nullable **and** you need type-safe query expressions (filtering, ordering), combine both features with the `Prop<Nullable<T>>` composition.

### Why not `Nullable<Prop<T>>`?

The older pattern `Nullable<Prop<T>>` (a Nullable wrapping a Smart Property) has two silent problems:

1. **OrderBy fails at runtime**: `Prop<T>.Asc` / `Desc` return an `IExpression` — but `Nullable<Prop<T>>` stores the inner value as a struct, breaking the expression metadata chain. `OrderBy` silently produces incorrect SQL or no ordering at all.
2. **Type inference confusion**: Delphi's implicit operator resolution chains fail for nested generics like `Nullable<Prop<T>>`, making assignments inconsistent.

The correct composition is `Prop<Nullable<T>>`:

```pascal
// ❌ DEPRECATED — do NOT use
FScheduledAt: Nullable<Prop<TDateTime>>;

// ✅ CORRECT — Smart Property of a Nullable value
FScheduledAt: Prop<Nullable<TDateTime>>;
```

> [!CAUTION]
> The framework emits a runtime warning when it detects `Nullable<Prop<T>>` in your entity:
> ```
> [Dext.Orm] WARNING: Field "TOrder.ScheduledAt" is declared as legacy "Nullable<Prop<T>>".
> This pattern is deprecated and causes silent issues in query ordering (OrderBy).
> Please change its declaration to "Prop<Nullable<TDateTime>>" for full type safety.
> ```
> Update any field showing this warning before the next major release.

### Declaring a Nullable Smart Property

```pascal
uses
  Dext.Types.Nullable,   // Nullable<T>
  Dext.Core.SmartTypes;  // Prop<T> and aliases

type
  [Table('work_orders')]
  TWorkOrder = class
  private
    FId:           IntType;                       // non-nullable
    FClientName:   StringType;                    // non-nullable
    FScheduledAt:  Prop<Nullable<TDateTime>>;     // nullable datetime
    FAssigneeId:   Prop<Nullable<Integer>>;       // nullable FK
  public
    [PK, AutoInc]
    property Id:          IntType                    read FId          write FId;
    property ClientName:  StringType                 read FClientName  write FClientName;
    property ScheduledAt: Prop<Nullable<TDateTime>>  read FScheduledAt write FScheduledAt;
    property AssigneeId:  Prop<Nullable<Integer>>    read FAssigneeId  write FAssigneeId;
  end;
```

### Reading and writing nullable values

```pascal
var Order: TWorkOrder;

// Assign a concrete value (implicit conversion)
Order.ScheduledAt := EncodeDate(2026, 12, 31);

// Assign null explicitly
Order.ScheduledAt := Nullable<TDateTime>.Null;

// Check for null (runtime mode)
if Order.ScheduledAt.IsNull then
  WriteLn('Not scheduled yet');

// Read the inner value safely
if Order.ScheduledAt.Value.HasValue then
  WriteLn('Scheduled: ', DateToStr(Order.ScheduledAt.Value.Value));

// Or use the default shorthand
var Date := Order.ScheduledAt.Value.GetValueOrDefault(Now);
```

### Querying with `IsNull` / `IsNotNull`

```pascal
var o := TWorkOrder.Props;

// Orders with no scheduled date
var Unscheduled := Context.WorkOrders
  .Where(o.ScheduledAt.IsNull)
  .ToList;

// Orders already assigned
var Assigned := Context.WorkOrders
  .Where(o.AssigneeId.IsNotNull)
  .ToList;
```

### Ordering by a nullable column

`Prop<Nullable<T>>` fully supports `.Asc` and `.Desc`, producing correct SQL (`ORDER BY scheduled_at ASC`):

```pascal
var o := TWorkOrder.Props;

// Nulls last (database default for ASC)
var ByDate := Context.WorkOrders
  .QueryAll
  .OrderBy(o.ScheduledAt.Asc)
  .ToList;

// Descending — most recent first
var Latest := Context.WorkOrders
  .QueryAll
  .OrderBy(o.ScheduledAt.Desc)
  .ToList;
```

> [!WARNING]
> `OrderBy` on `Nullable<Prop<T>>` (the deprecated pattern) produces **silent incorrect ordering** because the expression metadata is not preserved through the outer `Nullable<>` wrapper. This was the root motivation for the `Prop<Nullable<T>>` design.

### Combining nullable and non-nullable filters

```pascal
var o := TWorkOrder.Props;

var Results := Context.WorkOrders
  .Where(
    (o.ClientName.Contains('Acme')) and
    (o.ScheduledAt.IsNotNull) and
    (o.AssigneeId.IsNull)
  )
  .OrderBy(o.ScheduledAt.Asc)
  .ToList;
```

### Migration guide: `Nullable<Prop<T>>` → `Prop<Nullable<T>>`

If you have existing entities using the deprecated pattern, the change is mechanical:

```pascal
// Before (deprecated)
type
  TOrder = class
  private
    FDueDate: Nullable<DateTimeType>;    // Nullable<Prop<TDateTime>>
    FNotes:   Nullable<StringType>;      // Nullable<Prop<string>>
  public
    property DueDate: Nullable<DateTimeType> read FDueDate write FDueDate;
    property Notes:   Nullable<StringType>   read FNotes   write FNotes;
  end;

// After (correct)
type
  TOrder = class
  private
    FDueDate: Prop<Nullable<TDateTime>>;
    FNotes:   Prop<Nullable<string>>;
  public
    property DueDate: Prop<Nullable<TDateTime>> read FDueDate write FDueDate;
    property Notes:   Prop<Nullable<string>>    read FNotes   write FNotes;
  end;
```

The call sites that read/write the values require **no changes**: implicit operators handle both assignment and comparison transparently.

---

[← Querying](querying.md) | [Next: Specifications →](specifications.md)
