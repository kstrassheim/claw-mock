# MOCK — AdventureWorks

Mocking manual for the `AdventureWorks` database. Read by the claw-mock
bot at the start of every hourly mock run (mounted into the pod at
`~/.openclaw/workspace/MOCK/MOCK-AdventureWorks.md`).

This file covers only what is specific to this database: where it lives,
which tables are facts and which are dimensions, and how they may move.
How to connect is in `TOOLS.md`, and the report format is in the run
prompt — neither is repeated here.

## Target

| | |
| --- | --- |
| Engine | `mssql` (Azure SQL) |
| Server | `${SQL_SERVER_FQDN}` |
| Database | `${SQL_DB_ADVENTUREWORKS}` |

Connect as described in `TOOLS.md` ("Connecting to the mock databases").

## Table classification

| Table | Type | Mock behaviour |
|---|---|---|
| `Sales.SalesOrderHeader` | **Fact** | Append new orders every run; status advances on previous runs' orders; trim oldest when above band |
| `Sales.SalesOrderDetail` | **Fact** | Append line items for the new orders (1–4 per order); deleted together with their header |
| `Sales.Customer` | Dimension | Occasionally add a customer; occasionally update one; delete only unreferenced customers when above band |
| `Person.Person` | Dimension | Grows together with new individual customers; names/titles may drift on updates |
| `Person.Address` | Dimension | Grows slowly; reused as bill-to/ship-to; city/postal code may drift on updates |
| `Person.StateProvince` | Dimension | Static reference data — do not touch |
| `Sales.SalesTerritory` | Dimension | Static reference data — do not touch |
| `Sales.Store` | Dimension | Static reference data — do not touch |
| `Sales.ShipMethod` | Dimension | Static reference data — do not touch |
| `Production.ProductCategory` | Dimension | Static reference data — do not touch |
| `Production.ProductSubcategory` | Dimension | Static reference data — do not touch |
| `Production.Product` | Dimension | Rarely add a product; ListPrice/StandardCost may drift on existing ones; delete only unreferenced products when above band |

## Live-timing rules (facts)

The run interval is **1 hour**. To look like a live OLTP database:

- `Sales.SalesOrderHeader.OrderDate` of every new order MUST fall inside
  the window `(now - 65 minutes, now]` — spread them randomly through the
  window, not all at `now`.
- `DueDate` = `OrderDate + 12 days`, `ShipDate` = `OrderDate + 5..7 days`
  (so `ShipDate` is usually still in the future → leave it `NULL` for
  `Status` < 5).
- `Status`: ~70% of new orders `2` (in process), ~30% `1` (pending).
  ~20% of the *previous* run's orders with `Status IN (1,2)` should
  advance one step (`1→2`, `2→3`); when advancing to `5`, set
  `ShipDate` to a time between `OrderDate` and now.
- Create **3–10 new orders per run** (random each run).
- Every new order gets 1–4 `SalesOrderDetail` rows. `ProductID` drawn
  randomly from existing products, `UnitPrice` = the product's current
  `ListPrice`, `OrderQty` 1–5, `UnitPriceDiscount` 0 in 90% of rows,
  otherwise 0.02–0.15. `LineTotal` = `OrderQty * UnitPrice * (1 - UnitPriceDiscount)`.
- After inserting details, update the header: `SubTotal` = SUM(LineTotal),
  `TaxAmt` = 8% of SubTotal, `Freight` = `ShipMethod.ShipBase + 0.02 * SubTotal`,
  `TotalDue` = SubTotal + TaxAmt + Freight.
- Never rewrite fact rows older than the current run, except the
  status advances above and the trimming below.

## Live-timing rules (dimensions)

Dimensions change slowly — they are *not* expected to move every run:

- `Sales.Customer` / `Person.Person`: add 0–2 new individual customers per
  run (some runs none). New customers need a `Person.Person` row first,
  then the `Sales.Customer` row with `AccountNumber` =
  `AW` + zero-padded next number, and usually a fresh `Person.Address`.
- On 0–2 existing customers per run, update a contact attribute:
  `Person.Person.Title` / `FirstName` / `MiddleName` / `LastName` /
  `EmailPromotion`, or the `City` / `PostalCode` / `AddressLine2` of one
  of their addresses. Respect column lengths and NOT NULLs; set
  `ModifiedDate`.
- `Production.Product`: on roughly every 10th run, add one product to an
  existing subcategory. `ListPrice` of existing products may drift ±2%
  on any run (UPDATE at most 2 products per run). When `ListPrice`
  changes, drift `StandardCost` with it so cost stays below price.
- All other dimension tables are static seed/reference data.

## Size bands (min–max rows)

The databases feed a DWH import and must not grow without limit. At the
END of every run, check each table against its band and trim when above
the max. Never trim below the min.

| Table | Min | Max |
|---|---|---|
| `Sales.SalesOrderHeader` | 5,000 | 20,000 |
| `Sales.SalesOrderDetail` | (follows header) | (follows header) |
| `Sales.Customer` | 200 | 1,000 |
| `Person.Person` | 200 | 1,000 |
| `Person.Address` | 200 | 1,000 |
| `Production.Product` | 100 | 500 |

Trimming rules — **dependencies first, children before parents**:

- Facts: delete the oldest `Sales.SalesOrderDetail` rows together with
  their `Sales.SalesOrderHeader` (details first, then the header),
  oldest `OrderDate` first, until the header count is back at the max.
  Never delete rows created in this run.
- Dimensions: a row is deletable only when NOTHING references it —
  check every FK that can point at it:
  - `Sales.Customer`: no `SalesOrderHeader` with that `CustomerID`.
  - `Person.Person`: no `Sales.Customer` with that `PersonID`.
  - `Person.Address`: no `SalesOrderHeader` with that `BillToAddressID`
    or `ShipToAddressID`.
  - `Production.Product`: no `SalesOrderDetail` with that `ProductID`.
- Delete dimension rows child-first (`Sales.Customer` before
  `Person.Person` before `Person.Address`), never rows created in this
  run, and stop as soon as the table is back at its max — do not
  over-delete.
- Static reference tables are never trimmed.

## Edge cases (DWH import testing)

On 0–2 of the rows you insert or update per run, deliberately use a
boundary value from this catalogue. Rotate through it over runs so
every column gets exercised. Hard limits: never violate PK/FK/NOT
NULL/CHECK, never put edge values into FK columns, keep computed
columns consistent, keep fact timestamps inside the live window.

- Max-length strings: `FirstName`/`LastName`/`Product.Name` exactly 50
  chars, `AddressLine1` exactly 60, `Title` exactly 8, `AccountNumber`
  exactly 10.
- Unicode (always `N''` literals): accented and non-Latin names —
  `N'Björk'`, `N'Guðmundsdóttir'`, `N'José'`, `N'北京'`, `N'Москва'`.
- Apostrophes in names, properly escaped: `N'O''Brien'`, `N'D''Angelo'`.
- Numeric extremes: `OrderQty` 1 or 5, `UnitPriceDiscount` exactly
  0.15, `ListPrice` 0.00 (free product) or a large MONEY value like
  99999.99, `Weight` at the `DECIMAL(8,2)` ceiling 999999.99.
- Dates: `OrderDate` one second after the window opens
  (`now - 65 minutes`); a `ShipDate` exactly equal to its `OrderDate`
  when advancing to `Status = 5`.
- NULLs in nullable columns: `MiddleName`, `Title`, `AddressLine2`,
  `Color`, `Size`, `Weight`, `ShipDate` (status < 5 only).

## Integrity rules

- FKs are enforced: insert parents before children
  (Person → Customer → SalesOrderHeader → SalesOrderDetail) and delete
  children before parents (SalesOrderDetail → SalesOrderHeader →
  Customer → Person → Address).
- Every `BillToAddressID` / `ShipToAddressID` must reference an existing
  `Person.Address` (reuse existing addresses most of the time).
- `TerritoryID` on customers/orders must reference an existing
  `Sales.SalesTerritory`.
- Set `ModifiedDate = SYSUTCDATETIME()` on every row you insert or update.

