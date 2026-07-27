/*
Post-deployment script for Northwind.

1. Seeds a small, deterministic sample dataset (only into empty tables —
   the script is idempotent across repeated dacpac publishes).
2. Creates the contained database user `clawmockbot` that the claw-mock
   bot uses for its hourly mock runs. The password is supplied at publish
   time via the $(BotPassword) sqlcmd variable
   (sqlpackage /v:BotPassword="...").
*/

-- =========================================================================
-- Seed: dimensions first, then facts. Insert order fixes the identity
-- values (tables are empty when this runs), so FK literals below line up.
-- =========================================================================

IF NOT EXISTS (SELECT 1 FROM [dbo].[Categories])
BEGIN
    INSERT INTO [dbo].[Categories] ([CategoryName], [Description]) VALUES
    (N'Beverages',    N'Soft drinks, coffees, teas, beers, and ales'),      -- 1
    (N'Condiments',   N'Sweet and savory sauces, relishes, spreads'),       -- 2
    (N'Confections',  N'Desserts, candies, and sweet breads'),              -- 3
    (N'Dairy Products', N'Cheeses'),                                        -- 4
    (N'Grains/Cereals', N'Breads, crackers, pasta, and cereal'),            -- 5
    (N'Meat/Poultry', N'Prepared meats'),                                   -- 6
    (N'Produce',      N'Dried fruit and bean curd'),                        -- 7
    (N'Seafood',      N'Seaweed and fish');                                 -- 8
END
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers])
BEGIN
    INSERT INTO [dbo].[Suppliers] ([CompanyName], [ContactName], [ContactTitle], [City], [Country], [Phone]) VALUES
    (N'Exotic Liquids',          N'Charlotte Cooper', N'Purchasing Manager', N'London',   N'UK',     N'(171) 555-2222'),   -- 1
    (N'New Orleans Cajun Delights', N'Shelley Burke', N'Order Administrator', N'New Orleans', N'USA', N'(100) 555-4822'), -- 2
    (N'Grandma Kelly''s Homestead', N'Regina Murphy', N'Sales Representative', N'Ann Arbor', N'USA', N'(313) 555-5735'),  -- 3
    (N'Tokyo Traders',           N'Yoshi Nagase',     N'Marketing Manager',  N'Tokyo',    N'Japan',  N'(03) 3555-5011'),  -- 4
    (N'Pavlova, Ltd.',           N'Ian Devling',      N'Marketing Manager',  N'Melbourne', N'Australia', N'(03) 444-2343');-- 5
END
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[Products])
BEGIN
    INSERT INTO [dbo].[Products]
        ([ProductName], [SupplierID], [CategoryID], [QuantityPerUnit], [UnitPrice], [UnitsInStock], [UnitsOnOrder], [ReorderLevel], [Discontinued]) VALUES
    (N'Chai',               1, 1, N'10 boxes x 20 bags', 18.00,  39, 0,  10, 0),   -- 1
    (N'Chang',              1, 1, N'24 - 12 oz bottles', 19.00,  17, 40, 25, 0),   -- 2
    (N'Aniseed Syrup',      1, 2, N'12 - 550 ml bottles', 10.00, 13, 70, 25, 0),   -- 3
    (N'Chef Anton''s Cajun Seasoning', 2, 2, N'48 - 6 oz jars', 22.00, 53, 0, 0, 0), -- 4
    (N'Queso Cabrales',     4, 4, N'1 kg pkg.',          21.00,  22, 30, 30, 0),   -- 5
    (N'Tofu',               4, 7, N'40 - 100 g pkgs.',   23.25,  35, 0,  0,  0),   -- 6
    (N'Genen Shouyu',       4, 2, N'24 - 250 ml bottles', 15.50, 39, 0,  5,  0),   -- 7
    (N'Pavlova',            5, 3, N'32 - 500 g boxes',   17.45,  29, 0,  10, 0),   -- 8
    (N'Alice Mutton',       5, 6, N'20 - 1 kg tins',     39.00,  0,  0,  0,  1),   -- 9
    (N'Ikura',              4, 8, N'12 - 200 ml jars',   31.00,  31, 0,  0,  0);   -- 10
END
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[Customers])
BEGIN
    INSERT INTO [dbo].[Customers] ([CustomerID], [CompanyName], [ContactName], [ContactTitle], [City], [Country], [Phone]) VALUES
    (N'ALFKI', N'Alfreds Futterkiste',    N'Maria Anders',     N'Sales Representative', N'Berlin',  N'Germany', N'030-0074321'),
    (N'ANATR', N'Ana Trujillo Emparedados', N'Ana Trujillo',   N'Owner',                N'México D.F.', N'Mexico', N'(5) 555-4729'),
    (N'BERGS', N'Berglunds snabbköp',     N'Christina Berglund', N'Order Administrator', N'Luleå',   N'Sweden',  N'0921-12 34 65'),
    (N'BONAP', N'Bon app''',              N'Laurence Lebihan', N'Owner',                N'Marseille', N'France', N'91.24.45.40'),
    (N'WILMK', N'Wilman Kala',            N'Matti Karttunen',  N'Owner/Marketing Assistant', N'Helsinki', N'Finland', N'90-224 8858');
END
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[Employees])
BEGIN
    INSERT INTO [dbo].[Employees] ([LastName], [FirstName], [Title], [HireDate], [City], [Country]) VALUES
    (N'Davolio',   N'Nancy',  N'Sales Representative', '2024-05-01', N'Seattle', N'USA'),  -- 1
    (N'Fuller',    N'Andrew', N'Vice President, Sales', '2023-08-14', N'Tacoma', N'USA'),  -- 2
    (N'Leverling', N'Janet',  N'Sales Representative', '2024-04-01', N'Kirkland', N'USA'); -- 3
END
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[Shippers])
BEGIN
    INSERT INTO [dbo].[Shippers] ([CompanyName], [Phone]) VALUES
    (N'Speedy Express',   N'(503) 555-9831'),  -- 1
    (N'United Package',   N'(503) 555-3199'),  -- 2
    (N'Federal Shipping', N'(503) 555-9931');  -- 3
END
GO

-- Facts: a handful of historical orders so reports have something to chew on.
IF NOT EXISTS (SELECT 1 FROM [dbo].[Orders])
BEGIN
    INSERT INTO [dbo].[Orders]
        ([CustomerID], [EmployeeID], [OrderDate], [RequiredDate], [ShippedDate], [ShipVia], [Freight], [ShipName], [ShipCity], [ShipCountry]) VALUES
    (N'ALFKI', 1, DATEADD(day, -25, SYSUTCDATETIME()), DATEADD(day,  3, SYSUTCDATETIME()), DATEADD(day, -19, SYSUTCDATETIME()), 1, 32.38, N'Alfreds Futterkiste',    N'Berlin',  N'Germany'),  -- 1
    (N'ANATR', 3, DATEADD(day, -18, SYSUTCDATETIME()), DATEADD(day, 10, SYSUTCDATETIME()), DATEADD(day, -14, SYSUTCDATETIME()), 2, 11.61, N'Ana Trujillo Emparedados', N'México D.F.', N'Mexico'), -- 2
    (N'BERGS', 2, DATEADD(day, -11, SYSUTCDATETIME()), DATEADD(day, 17, SYSUTCDATETIME()), DATEADD(day,  -6, SYSUTCDATETIME()), 3, 65.83, N'Berglunds snabbköp',     N'Luleå',   N'Sweden'),   -- 3
    (N'BONAP', 1, DATEADD(day,  -5, SYSUTCDATETIME()), DATEADD(day, 23, SYSUTCDATETIME()), NULL,                               2, 41.34, N'Bon app''',              N'Marseille', N'France'), -- 4
    (N'WILMK', 3, DATEADD(day,  -1, SYSUTCDATETIME()), DATEADD(day, 27, SYSUTCDATETIME()), NULL,                               1,  8.19, N'Wilman Kala',            N'Helsinki', N'Finland');-- 5

    INSERT INTO [dbo].[Order Details] ([OrderID], [ProductID], [UnitPrice], [Quantity], [Discount]) VALUES
    (1, 1,  18.00, 12, 0),
    (1, 8,  17.45, 10, 0),
    (2, 2,  19.00,  5, 0),
    (2, 4,  22.00,  9, 0.05),
    (3, 5,  21.00, 40, 0),
    (3, 10, 31.00, 15, 0.10),
    (4, 3,  10.00, 20, 0),
    (4, 7,  15.50, 24, 0),
    (5, 6,  23.25,  6, 0);
END
GO

-- =========================================================================
-- Bot login: contained database user with SQL authentication.
-- $(BotPassword) is passed at publish time (sqlpackage /v:BotPassword=...).
-- db_owner is deliberate: the bot inserts/updates/deletes mock rows in
-- every table — scoped to this mock database only (contained user, no
-- server-level rights).
-- =========================================================================
IF NOT EXISTS (SELECT 1 FROM [sys].[database_principals] WHERE [name] = N'clawmockbot')
BEGIN
    CREATE USER [clawmockbot] WITH PASSWORD = N'$(BotPassword)';
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM [sys].[database_role_members] rm
    JOIN [sys].[database_principals] r ON rm.[role_principal_id] = r.[principal_id]
    JOIN [sys].[database_principals] m ON rm.[member_principal_id] = m.[principal_id]
    WHERE r.[name] = N'db_owner' AND m.[name] = N'clawmockbot'
)
BEGIN
    ALTER ROLE [db_owner] ADD MEMBER [clawmockbot];
END
GO
