CREATE TABLE [dbo].[Products] (
    [ProductID]       INT          NOT NULL IDENTITY(1,1),
    [ProductName]     NVARCHAR(40) NOT NULL,
    [SupplierID]      INT          NULL,
    [CategoryID]      INT          NULL,
    [QuantityPerUnit] NVARCHAR(20) NULL,
    [UnitPrice]       MONEY        NULL CONSTRAINT [DF_Products_UnitPrice] DEFAULT (0),
    [UnitsInStock]    SMALLINT     NULL CONSTRAINT [DF_Products_UnitsInStock] DEFAULT (0),
    [UnitsOnOrder]    SMALLINT     NULL CONSTRAINT [DF_Products_UnitsOnOrder] DEFAULT (0),
    [ReorderLevel]    SMALLINT     NULL CONSTRAINT [DF_Products_ReorderLevel] DEFAULT (0),
    [Discontinued]    BIT          NOT NULL CONSTRAINT [DF_Products_Discontinued] DEFAULT (0),
    CONSTRAINT [PK_Products] PRIMARY KEY CLUSTERED ([ProductID] ASC),
    CONSTRAINT [FK_Products_Suppliers] FOREIGN KEY ([SupplierID])
        REFERENCES [dbo].[Suppliers] ([SupplierID]),
    CONSTRAINT [FK_Products_Categories] FOREIGN KEY ([CategoryID])
        REFERENCES [dbo].[Categories] ([CategoryID])
);
GO
