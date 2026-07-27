# MOCKING — AdventureWorks

Mocking manual for the `AdventureWorks` database. Read by the claw-mock
bot at the start of every hourly mock run (mounted into the pod at
`~/.openclaw/workspace/MOCKING/MOCKING-AdventureWorks.md`).

## Connection

```bash
sqlcmd -S "tcp:${SQL_SERVER_FQDN},1433" -d "${SQL_DB_ADVENTUREWORKS}" \
       -G --authentication-method=ActiveDirectoryDefault -l 30 -N -C
```

(Entra-only server — the bot authenticates via Azure Workload Identity
as the deploy identity. No SQL user/password exists.)

## Table classification

| Table | Type | Mock behaviour |
|---|---|---|
| `Sales.SalesOrderHeader` | **Fact** | Append new orders every run |
| `Sales.SalesOrderDetail` | **Fact** | Append line items for the new orders (1–4 per order) |
| `Sales.Customer` | Dimension | Occasionally add a customer; never churn existing ones |
| `Person.Person` | Dimension | Grows together with new individual customers |
| `Person.Address` | Dimension | Grows slowly; reused as bill-to/ship-to |
| `Person.StateProvince` | Dimension | Static reference data — do not touch |
| `Sales.SalesTerritory` | Dimension | Static reference data — do not touch |
| `Sales.Store` | Dimension | Static reference data — do not touch |
| `Sales.ShipMethod` | Dimension | Static reference data — do not touch |
| `Production.ProductCategory` | Dimension | Static reference data — do not touch |
| `Production.ProductSubcategory` | Dimension | Static reference data — do not touch |
| `Production.Product` | Dimension | Rarely add a product; ListPrice/StandardCost may drift on existing ones |

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
- Never delete or rewrite fact rows older than the current run. Facts are
  append-only.

## Live-timing rules (dimensions)

Dimensions change slowly — they are *not* expected to move every run:

- `Sales.Customer` / `Person.Person`: add 0–2 new individual customers per
  run (some runs none). New customers need a `Person.Person` row first,
  then the `Sales.Customer` row with `AccountNumber` =
  `AW` + zero-padded next number, and usually a fresh `Person.Address`.
- `Production.Product`: on roughly every 10th run, add one product to an
  existing subcategory. `ListPrice` of existing products may drift ±2%
  on any run (UPDATE at most 2 products per run).
- All other dimension tables are static seed/reference data.

## Integrity rules

- FKs are enforced: insert parents before children
  (Person → Customer → SalesOrderHeader → SalesOrderDetail).
- Every `BillToAddressID` / `ShipToAddressID` must reference an existing
  `Person.Address` (reuse existing addresses most of the time).
- `TerritoryID` on customers/orders must reference an existing
  `Sales.SalesTerritory`.
- Set `ModifiedDate = SYSUTCDATETIME()` on every row you insert or update.

## Reporting

At the end of the run, report the number of rows **you created in this
run** per table, grouped:

```
AdventureWorks
  fact
    Sales.SalesOrderHeader: +N
    Sales.SalesOrderDetail: +N
  dimension
    Sales.Customer: +N
    Person.Person: +N
    ...
```

Tables with zero new rows may be omitted from the report. On failure,
report the failing table and the SQL error message verbatim.
