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
| `dbo.Orders` | **Fact** | Append new orders every run |
| `dbo.[Order Details]` | **Fact** | Append line items for the new orders (1–3 per order) |
| `dbo.Customers` | Dimension | Occasionally add a customer |
| `dbo.Products` | Dimension | UnitsInStock moves with sales; rarely add a product |
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
- Never delete or rewrite fact rows older than the current run. Facts are
  append-only.

## Live-timing rules (dimensions)

- `Products.UnitsInStock`: decrease by the sold quantities of the orders
  you created this run (do not go below 0). When a product hits 0–5
  units, set `UnitsOnOrder` to 40–70; when a later run sees
  `UnitsOnOrder > 0`, it may restock (`UnitsInStock += UnitsOnOrder`,
  `UnitsOnOrder = 0`).
- `Customers`: add 0–1 new customers per run (some runs none). New
  `CustomerID` = 5 uppercase letters derived from the company name.
- `Products`: on roughly every 10th run add one product to an existing
  category/supplier.
- All other dimension tables are static seed/reference data.

## Integrity rules

- FKs are enforced: insert `Orders` before `[Order Details]`.
- `CustomerID`, `EmployeeID`, `ShipVia`, `ProductID` must reference
  existing parent rows.
- `[Order Details]` PK is (`OrderID`, `ProductID`) — one row per product
  per order.

