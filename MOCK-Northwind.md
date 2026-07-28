# MOCK — Northwind

Mocking manual for the `Northwind` database. Read by the claw-mock bot
at the start of every hourly mock run (mounted into the pod at
`~/.openclaw/workspace/MOCK/MOCK-Northwind.md`).

This file covers only what is specific to this database: where it lives,
which tables are facts and which are dimensions, and how they may move.
How to connect is in `TOOLS.md`, and the report format is in the run
prompt — neither is repeated here.

## Target

| | |
| --- | --- |
| Engine | `mssql` (Azure SQL) |
| Server | `${SQL_SERVER_FQDN}` |
| Database | `${SQL_DB_NORTHWIND}` |

Connect as described in `TOOLS.md` ("Connecting to the mock databases").

## Table classification

| Table | Type | Mock behaviour |
|---|---|---|
| `dbo.Orders` | **Fact** | Append new orders every run; ship previous runs' orders; trim oldest when above band |
| `dbo.[Order Details]` | **Fact** | Append line items for the new orders (1–3 per order); deleted together with their order |
| `dbo.Customers` | Dimension | Occasionally add a customer; occasionally update contact fields; delete only unreferenced customers when above band |
| `dbo.Products` | Dimension | UnitsInStock moves with sales; rarely add a product; UnitPrice may drift; delete only unreferenced products when above band |
| `dbo.Categories` | Dimension | Static reference data — do not touch |
| `dbo.Suppliers` | Dimension | Static reference data — do not touch |
| `dbo.Employees` | Dimension | Static reference data — do not touch |
| `dbo.Shippers` | Dimension | Static reference data — do not touch |

## Live-timing rules (facts)

The run interval is **1 hour**. To look like a live OLTP database:

- `Orders.OrderDate` of every new order MUST fall inside the window
  `(now - 65 minutes, now]` — spread randomly through the window.
- `RequiredDate` = `OrderDate + 14 days`. `ShippedDate` = `NULL` for new
  orders (they haven't shipped yet).
- ~25% of the *previous* run's orders with `ShippedDate IS NULL` should
  ship: set `ShippedDate` to a time between `OrderDate` and now.
- Create **2–8 new orders per run** (random each run). `CustomerID` drawn
  from existing customers, `EmployeeID` from existing employees,
  `ShipVia` 1–3, `Freight` between 4 and 90 with 2 decimals.
- Every new order gets 1–3 `[Order Details]` rows: existing `ProductID`s,
  `UnitPrice` = product's current `UnitPrice`, `Quantity` 1–30,
  `Discount` 0 in 85% of rows, otherwise 0.05/0.10/0.15.
- Never rewrite fact rows older than the current run, except the
  shipments above and the trimming below.

## Live-timing rules (dimensions)

- `Products.UnitsInStock`: decrease by the sold quantities of the orders
  you created this run (do not go below 0). When a product hits 0–5
  units, set `UnitsOnOrder` to 40–70; when a later run sees
  `UnitsOnOrder > 0`, it may restock (`UnitsInStock += UnitsOnOrder`,
  `UnitsOnOrder = 0`).
- `Customers`: add 0–1 new customers per run (some runs none). New
  `CustomerID` = 5 uppercase letters derived from the company name.
- On 0–2 existing customers per run, update a contact field:
  `ContactName`, `ContactTitle`, `Phone`, or `City`. Respect column
  lengths and NOT NULLs.
- `Products`: on roughly every 10th run add one product to an existing
  category/supplier. `UnitPrice` may drift ±2% on any run (UPDATE at
  most 2 products per run).
- All other dimension tables are static seed/reference data.

## Size bands (min–max rows)

The database feeds a DWH import and must not grow without limit. At the
END of every run, check each table against its band and trim when above
the max. Never trim below the min.

| Table | Min | Max |
|---|---|---|
| `dbo.Orders` | 8 | 15 |
| `dbo.[Order Details]` | (follows Orders) | (follows Orders) |
| `dbo.Customers` | 4 | 6 |
| `dbo.Products` | 5 | 8 |

These are deliberately tight — smaller than the database already is. At
2–8 new orders per hourly run, an `Orders` max of 15 means every single
run inserts, then trims back to 15, so the fact tables sit at their
maximum permanently and the DWH import always sees deletions between two
imports. That is the behaviour being exercised here; correctness of the
trim path matters more than realistic warehouse volume.

Earlier bands (5,000 rows, then 120) were never reached at this run rate,
so the trim path was correct but dead code and the database only ever grew.
If you later want a larger corpus, raise the maxima — but keep
`max - min` well above the per-run insert rate so a single run cannot
push the table from below the min to above the max.

Trimming rules — **dependencies first, children before parents**:

- Facts: delete the oldest `[Order Details]` rows together with their
  `Orders` row (details first, then the order), oldest `OrderDate`
  first, until the `Orders` count is back at the max. Never delete
  rows created in this run.
- Dimensions: a row is deletable only when NOTHING references it —
  check every FK that can point at it:
  - `dbo.Customers`: no `Orders` with that `CustomerID`.
  - `dbo.Products`: no `[Order Details]` with that `ProductID`.
- Never delete dimension rows created in this run, and stop as soon as
  the table is back at its max — do not over-delete.
- Static reference tables are never trimmed.
- A dimension can sit above its max with nothing deletable, because every
  candidate row is still referenced. That is expected and not an error:
  delete what you can, report the rest as not deleted, and never break an
  FK or disable a constraint to get under the max. Trimming the facts
  first usually frees dimension rows for the next run.

## Edge cases (DWH import testing)

On 0–2 of the rows you insert or update per run, deliberately use a
boundary value from this catalogue. Rotate through it over runs so
every column gets exercised. Hard limits: never violate PK/FK/NOT
NULL/CHECK, never put edge values into FK columns, keep fact
timestamps inside the live window.

- Max-length strings: `CompanyName`/`ShipName` exactly 40 chars,
  `ContactName`/`ContactTitle` exactly 30, `ProductName` exactly 40,
  `QuantityPerUnit` exactly 20, `City`/`Country`/`ShipCountry` exactly
  15, `Phone` exactly 24.
- Unicode (always `N''` literals): accented and non-Latin names —
  `N'Björk'`, `N'Guðmundsdóttir'`, `N'José'`, `N'北京'`, `N'Москва'`.
- Apostrophes in names, properly escaped: `N'O''Brien'`, `N'D''Angelo'`.
- Numeric extremes: `Quantity` 1 or 30, `Discount` exactly 0.15,
  `UnitPrice` 0.00 (free product) or a large MONEY value like
  99999.99, `UnitsInStock` at the SMALLINT ceiling 32767 on a restock,
  `Freight` exactly 4.00 or 90.00.
- Dates: `OrderDate` one second after the window opens
  (`now - 65 minutes`); a `ShippedDate` exactly equal to its
  `OrderDate` when shipping.
- NULLs in nullable columns: `ContactName`, `ContactTitle`, `Phone`,
  `ShippedDate` (unshipped orders only).

## Integrity rules

- FKs are enforced: insert `Orders` before `[Order Details]`, and delete
  `[Order Details]` before `Orders`.
- `CustomerID`, `EmployeeID`, `ShipVia`, `ProductID` must reference
  existing parent rows.
- `[Order Details]` PK is (`OrderID`, `ProductID`) — one row per product
  per order.

