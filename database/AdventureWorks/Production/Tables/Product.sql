CREATE TABLE [Production].[Product] (
    [ProductID]           INT            NOT NULL IDENTITY(1,1),
    [Name]                NVARCHAR(50)   NOT NULL,
    [ProductNumber]       NVARCHAR(25)   NOT NULL,
    [Color]               NVARCHAR(15)   NULL,
    [StandardCost]        MONEY          NOT NULL,
    [ListPrice]           MONEY          NOT NULL,
    [Size]                NVARCHAR(5)    NULL,
    [Weight]              DECIMAL(8,2)   NULL,
    [ProductSubcategoryID] INT           NULL,
    [SellStartDate]       DATETIME2      NOT NULL,
    [SellEndDate]         DATETIME2      NULL,
    [rowguid]             UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_Product_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]        DATETIME2      NOT NULL CONSTRAINT [DF_Product_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Product_ProductID] PRIMARY KEY CLUSTERED ([ProductID] ASC),
    CONSTRAINT [FK_Product_ProductSubcategory] FOREIGN KEY ([ProductSubcategoryID])
        REFERENCES [Production].[ProductSubcategory] ([ProductSubcategoryID])
);
GO
