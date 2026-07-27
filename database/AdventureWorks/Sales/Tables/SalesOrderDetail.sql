CREATE TABLE [Sales].[SalesOrderDetail] (
    [SalesOrderID]       INT           NOT NULL,
    [SalesOrderDetailID] INT           NOT NULL IDENTITY(1,1),
    [OrderQty]           SMALLINT      NOT NULL,
    [ProductID]          INT           NOT NULL,
    [UnitPrice]          MONEY         NOT NULL,
    [UnitPriceDiscount]  MONEY         NOT NULL CONSTRAINT [DF_SalesOrderDetail_UnitPriceDiscount] DEFAULT (0),
    [LineTotal]          MONEY         NOT NULL CONSTRAINT [DF_SalesOrderDetail_LineTotal] DEFAULT (0),
    [rowguid]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_SalesOrderDetail_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]       DATETIME2     NOT NULL CONSTRAINT [DF_SalesOrderDetail_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_SalesOrderDetail_SalesOrderID_SalesOrderDetailID] PRIMARY KEY CLUSTERED
        ([SalesOrderID] ASC, [SalesOrderDetailID] ASC),
    CONSTRAINT [FK_SalesOrderDetail_SalesOrderHeader] FOREIGN KEY ([SalesOrderID])
        REFERENCES [Sales].[SalesOrderHeader] ([SalesOrderID])
        ON DELETE CASCADE,
    CONSTRAINT [FK_SalesOrderDetail_Product] FOREIGN KEY ([ProductID])
        REFERENCES [Production].[Product] ([ProductID])
);
GO
