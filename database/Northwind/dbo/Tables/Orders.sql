CREATE TABLE [dbo].[Orders] (
    [OrderID]      INT          NOT NULL IDENTITY(1,1),
    [CustomerID]   NCHAR(5)     NULL,
    [EmployeeID]   INT          NULL,
    [OrderDate]    DATETIME2    NULL,
    [RequiredDate] DATETIME2    NULL,
    [ShippedDate]  DATETIME2    NULL,
    [ShipVia]      INT          NULL,
    [Freight]      MONEY        NULL CONSTRAINT [DF_Orders_Freight] DEFAULT (0),
    [ShipName]     NVARCHAR(40) NULL,
    [ShipCity]     NVARCHAR(15) NULL,
    [ShipCountry]  NVARCHAR(15) NULL,
    CONSTRAINT [PK_Orders] PRIMARY KEY CLUSTERED ([OrderID] ASC),
    CONSTRAINT [FK_Orders_Customers] FOREIGN KEY ([CustomerID])
        REFERENCES [dbo].[Customers] ([CustomerID]),
    CONSTRAINT [FK_Orders_Employees] FOREIGN KEY ([EmployeeID])
        REFERENCES [dbo].[Employees] ([EmployeeID]),
    CONSTRAINT [FK_Orders_Shippers] FOREIGN KEY ([ShipVia])
        REFERENCES [dbo].[Shippers] ([ShipperID])
);
GO
