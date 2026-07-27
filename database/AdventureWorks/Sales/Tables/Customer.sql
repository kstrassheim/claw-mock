CREATE TABLE [Sales].[Customer] (
    [CustomerID]    INT            NOT NULL IDENTITY(1,1),
    [PersonID]      INT            NULL,
    [StoreID]       INT            NULL,
    [TerritoryID]   INT            NULL,
    [AccountNumber] NVARCHAR(10)   NOT NULL,
    [rowguid]       UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_Customer_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]  DATETIME2      NOT NULL CONSTRAINT [DF_Customer_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Customer_CustomerID] PRIMARY KEY CLUSTERED ([CustomerID] ASC),
    CONSTRAINT [FK_Customer_Person] FOREIGN KEY ([PersonID])
        REFERENCES [Person].[Person] ([BusinessEntityID]),
    CONSTRAINT [FK_Customer_Store] FOREIGN KEY ([StoreID])
        REFERENCES [Sales].[Store] ([StoreID]),
    CONSTRAINT [FK_Customer_SalesTerritory] FOREIGN KEY ([TerritoryID])
        REFERENCES [Sales].[SalesTerritory] ([TerritoryID])
);
GO
