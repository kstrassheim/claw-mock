/*
Post-deployment script for AdventureWorks.

Seeds a small, deterministic sample dataset (only into empty tables —
the script is idempotent across repeated dacpac publishes).

No database user is created here: the Azure SQL server is Entra-only
(azuread_authentication_only), so SQL-authenticated contained users
cannot exist. The claw-mock bot connects as the deploy identity
(deploy-claw-mock-dev) via Azure Workload Identity; that identity is a
member of the server's Entra-admin group and needs no per-database user.
*/

-- =========================================================================
-- Seed: dimensions first, then facts. Insert order fixes the identity
-- values (tables are empty when this runs), so FK literals below line up.
-- =========================================================================

IF NOT EXISTS (SELECT 1 FROM [Sales].[SalesTerritory])
BEGIN
    INSERT INTO [Sales].[SalesTerritory] ([Name], [CountryRegionCode], [Group], [SalesYTD], [CostYTD]) VALUES
    (N'Northwest',  N'US', N'North America', 0, 0),   -- 1
    (N'Northeast',  N'US', N'North America', 0, 0),   -- 2
    (N'Central',    N'US', N'North America', 0, 0),   -- 3
    (N'Southwest',  N'US', N'North America', 0, 0),   -- 4
    (N'Germany',    N'DE', N'Europe',        0, 0),   -- 5
    (N'United Kingdom', N'GB', N'Europe',    0, 0);   -- 6
END
GO

IF NOT EXISTS (SELECT 1 FROM [Person].[StateProvince])
BEGIN
    INSERT INTO [Person].[StateProvince] ([StateProvinceCode], [CountryRegionCode], [Name], [TerritoryID]) VALUES
    (N'WA ', N'US', N'Washington',    1),  -- 1
    (N'NY ', N'US', N'New York',      2),  -- 2
    (N'TX ', N'US', N'Texas',         4),  -- 3
    (N'BY ', N'DE', N'Bayern',        5),  -- 4
    (N'ENG', N'GB', N'England',       6);  -- 5
END
GO

IF NOT EXISTS (SELECT 1 FROM [Person].[Address])
BEGIN
    INSERT INTO [Person].[Address] ([AddressLine1], [City], [StateProvinceID], [PostalCode]) VALUES
    (N'1234 Pine St',        N'Seattle',   1, N'98101'),  -- 1
    (N'55 Hudson Yards',     N'New York',  2, N'10001'),  -- 2
    (N'77 Congress Ave',     N'Austin',    3, N'78701'),  -- 3
    (N'Maximilianstr. 12',   N'München',   4, N'80539'),  -- 4
    (N'221B Baker Street',   N'London',    5, N'NW1 6XE');-- 5
END
GO

IF NOT EXISTS (SELECT 1 FROM [Person].[Person])
BEGIN
    INSERT INTO [Person].[Person] ([PersonType], [Title], [FirstName], [MiddleName], [LastName]) VALUES
    (N'IN', N'Mr.',  N'John',    N'A', N'Doe'),        -- 1
    (N'IN', N'Ms.',  N'Jane',    NULL, N'Smith'),      -- 2
    (N'IN', N'Mr.',  N'Carlos',  NULL, N'Ramirez'),    -- 3
    (N'IN', N'Ms.',  N'Anna',    N'M', N'Schmidt'),    -- 4
    (N'IN', N'Mrs.', N'Emily',   NULL, N'Clark');      -- 5
END
GO

IF NOT EXISTS (SELECT 1 FROM [Sales].[Store])
BEGIN
    INSERT INTO [Sales].[Store] ([Name], [SalesPersonID]) VALUES
    (N'Next-Door Bike Store', 1),   -- 1
    (N'City Cycle Works',     2);   -- 2
END
GO

IF NOT EXISTS (SELECT 1 FROM [Sales].[Customer])
BEGIN
    INSERT INTO [Sales].[Customer] ([PersonID], [StoreID], [TerritoryID], [AccountNumber]) VALUES
    (1,    NULL, 1, N'AW00000001'),  -- 1  (individual)
    (2,    NULL, 2, N'AW00000002'),  -- 2
    (3,    NULL, 4, N'AW00000003'),  -- 3
    (NULL, 1,    1, N'AW00000004'),  -- 4  (store)
    (4,    NULL, 5, N'AW00000005'),  -- 5
    (5,    NULL, 6, N'AW00000006');  -- 6
END
GO

IF NOT EXISTS (SELECT 1 FROM [Sales].[ShipMethod])
BEGIN
    INSERT INTO [Sales].[ShipMethod] ([Name], [ShipBase], [ShipRate]) VALUES
    (N'XRQ - Truck Ground',  3.95, 0.99),   -- 1
    (N'ZY - Express',        9.95, 1.99),   -- 2
    (N'OVERSEAS - Deluxe',  29.95, 2.99);   -- 3
END
GO

IF NOT EXISTS (SELECT 1 FROM [Production].[ProductCategory])
BEGIN
    INSERT INTO [Production].[ProductCategory] ([Name]) VALUES
    (N'Bikes'),        -- 1
    (N'Components'),   -- 2
    (N'Clothing'),     -- 3
    (N'Accessories');  -- 4
END
GO

IF NOT EXISTS (SELECT 1 FROM [Production].[ProductSubcategory])
BEGIN
    INSERT INTO [Production].[ProductSubcategory] ([ProductCategoryID], [Name]) VALUES
    (1, N'Road Bikes'),      -- 1
    (1, N'Mountain Bikes'),  -- 2
    (2, N'Handlebars'),      -- 3
    (2, N'Wheels'),          -- 4
    (3, N'Jerseys'),         -- 5
    (4, N'Helmets'),         -- 6
    (4, N'Bottles and Cages');-- 7
END
GO

IF NOT EXISTS (SELECT 1 FROM [Production].[Product])
BEGIN
    INSERT INTO [Production].[Product]
        ([Name], [ProductNumber], [Color], [StandardCost], [ListPrice], [Size], [Weight], [ProductSubcategoryID], [SellStartDate]) VALUES
    (N'Road-150 Red, 62',        N'BK-R93R-62', N'Red',   2171.29, 3578.27, N'62',  9.50, 1, '2025-01-01'),  -- 1
    (N'Road-150 Black, 58',      N'BK-R93B-58', N'Black', 2171.29, 3578.27, N'58',  9.20, 1, '2025-01-01'),  -- 2
    (N'Mountain-100 Silver, 44', N'BK-M82S-44', N'Silver',1912.15, 3399.99, N'44', 10.80, 2, '2025-01-01'),  -- 3
    (N'Mountain-100 Black, 48',  N'BK-M82B-48', N'Black', 1912.15, 3399.99, N'48', 11.10, 2, '2025-01-01'),  -- 4
    (N'LL Road Handlebars',      N'HB-R721',    NULL,       44.54,  120.27, NULL,   0.50, 3, '2025-01-01'),  -- 5
    (N'Road-650 Wheelset',       N'WH-R650',    N'Black',  199.38,  539.99, NULL,   1.60, 4, '2025-01-01'),  -- 6
    (N'Long-Sleeve Logo Jersey', N'LJ-0192',    N'Multi',   38.49,   89.99, N'L',   0.30, 5, '2025-01-01'),  -- 7
    (N'Sport-100 Helmet, Blue',  N'HL-U509-B',  N'Blue',    13.09,   34.99, NULL,   0.25, 6, '2025-01-01'),  -- 8
    (N'Water Bottle - 30 oz.',   N'WB-H098',    NULL,        1.87,    4.99, NULL,   0.10, 7, '2025-01-01');  -- 9
END
GO

-- Facts: a handful of historical orders so reports have something to chew on.
IF NOT EXISTS (SELECT 1 FROM [Sales].[SalesOrderHeader])
BEGIN
    INSERT INTO [Sales].[SalesOrderHeader]
        ([RevisionNumber], [OrderDate], [DueDate], [ShipDate], [Status], [OnlineOrderFlag],
         [CustomerID], [TerritoryID], [BillToAddressID], [ShipToAddressID], [ShipMethodID],
         [SubTotal], [TaxAmt], [Freight], [TotalDue]) VALUES
    (0, DATEADD(day, -30, SYSUTCDATETIME()), DATEADD(day, -18, SYSUTCDATETIME()), DATEADD(day, -23, SYSUTCDATETIME()), 5, 1, 1, 1, 1, 1, 1, 3578.27,  286.26, 89.46,  3953.99), -- 1
    (0, DATEADD(day, -21, SYSUTCDATETIME()), DATEADD(day,  -9, SYSUTCDATETIME()), DATEADD(day, -14, SYSUTCDATETIME()), 5, 1, 2, 2, 2, 2, 1, 4118.26,  329.46, 102.96, 4550.68), -- 2
    (0, DATEADD(day, -14, SYSUTCDATETIME()), DATEADD(day,  -2, SYSUTCDATETIME()), DATEADD(day,  -7, SYSUTCDATETIME()), 5, 1, 3, 4, 3, 3, 2, 3519.71,  281.58, 87.99,  3889.28), -- 3
    (0, DATEADD(day,  -7, SYSUTCDATETIME()), DATEADD(day,   5, SYSUTCDATETIME()), NULL,                            2, 0, 4, 1, 1, 1, 2, 6799.98,  544.00, 170.00, 7513.98), -- 4
    (0, DATEADD(day,  -2, SYSUTCDATETIME()), DATEADD(day,  10, SYSUTCDATETIME()), NULL,                            2, 1, 5, 5, 4, 4, 2,  124.98,   10.00,   3.12,  138.10); -- 5

    INSERT INTO [Sales].[SalesOrderDetail]
        ([SalesOrderID], [OrderQty], [ProductID], [UnitPrice], [UnitPriceDiscount], [LineTotal]) VALUES
    (1, 1, 1, 3578.27, 0, 3578.27),
    (2, 1, 2, 3578.27, 0, 3578.27),
    (2, 1, 6,  539.99, 0,  539.99),
    (3, 1, 4, 3399.99, 0, 3399.99),
    (3, 2, 5,  120.27, 0,  240.54),
    (4, 2, 3, 3399.99, 0, 6799.98),
    (5, 3, 8,   34.99, 0,  104.97),
    (5, 4, 9,    4.99, 0,   19.96);
END
GO
