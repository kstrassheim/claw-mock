CREATE TABLE [Sales].[SalesOrderHeader] (
    [SalesOrderID]    INT            NOT NULL IDENTITY(1,1),
    [RevisionNumber]  TINYINT        NOT NULL CONSTRAINT [DF_SalesOrderHeader_RevisionNumber] DEFAULT (0),
    [OrderDate]       DATETIME2      NOT NULL CONSTRAINT [DF_SalesOrderHeader_OrderDate] DEFAULT (SYSUTCDATETIME()),
    [DueDate]         DATETIME2      NOT NULL,
    [ShipDate]        DATETIME2      NULL,
    [Status]          TINYINT        NOT NULL CONSTRAINT [DF_SalesOrderHeader_Status] DEFAULT (1),
    [OnlineOrderFlag] BIT            NOT NULL CONSTRAINT [DF_SalesOrderHeader_OnlineOrderFlag] DEFAULT (1),
    [CustomerID]      INT            NOT NULL,
    [TerritoryID]     INT            NULL,
    [BillToAddressID] INT            NOT NULL,
    [ShipToAddressID] INT            NOT NULL,
    [ShipMethodID]    INT            NOT NULL,
    [SubTotal]        MONEY          NOT NULL CONSTRAINT [DF_SalesOrderHeader_SubTotal] DEFAULT (0),
    [TaxAmt]          MONEY          NOT NULL CONSTRAINT [DF_SalesOrderHeader_TaxAmt] DEFAULT (0),
    [Freight]         MONEY          NOT NULL CONSTRAINT [DF_SalesOrderHeader_Freight] DEFAULT (0),
    [TotalDue]        MONEY          NOT NULL CONSTRAINT [DF_SalesOrderHeader_TotalDue] DEFAULT (0),
    [rowguid]         UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_SalesOrderHeader_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]    DATETIME2      NOT NULL CONSTRAINT [DF_SalesOrderHeader_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_SalesOrderHeader_SalesOrderID] PRIMARY KEY CLUSTERED ([SalesOrderID] ASC),
    CONSTRAINT [FK_SalesOrderHeader_Customer] FOREIGN KEY ([CustomerID])
        REFERENCES [Sales].[Customer] ([CustomerID]),
    CONSTRAINT [FK_SalesOrderHeader_SalesTerritory] FOREIGN KEY ([TerritoryID])
        REFERENCES [Sales].[SalesTerritory] ([TerritoryID]),
    CONSTRAINT [FK_SalesOrderHeader_BillToAddress] FOREIGN KEY ([BillToAddressID])
        REFERENCES [Person].[Address] ([AddressID]),
    CONSTRAINT [FK_SalesOrderHeader_ShipToAddress] FOREIGN KEY ([ShipToAddressID])
        REFERENCES [Person].[Address] ([AddressID]),
    CONSTRAINT [FK_SalesOrderHeader_ShipMethod] FOREIGN KEY ([ShipMethodID])
        REFERENCES [Sales].[ShipMethod] ([ShipMethodID])
);
GO
