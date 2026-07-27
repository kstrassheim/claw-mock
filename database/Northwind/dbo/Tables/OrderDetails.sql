CREATE TABLE [dbo].[Order Details] (
    [OrderID]   INT      NOT NULL,
    [ProductID] INT      NOT NULL,
    [UnitPrice] MONEY    NOT NULL CONSTRAINT [DF_OrderDetails_UnitPrice] DEFAULT (0),
    [Quantity]  SMALLINT NOT NULL CONSTRAINT [DF_OrderDetails_Quantity] DEFAULT (1),
    [Discount]  REAL     NOT NULL CONSTRAINT [DF_OrderDetails_Discount] DEFAULT (0),
    CONSTRAINT [PK_Order_Details] PRIMARY KEY CLUSTERED ([OrderID] ASC, [ProductID] ASC),
    CONSTRAINT [FK_Order_Details_Orders] FOREIGN KEY ([OrderID])
        REFERENCES [dbo].[Orders] ([OrderID]),
    CONSTRAINT [FK_Order_Details_Products] FOREIGN KEY ([ProductID])
        REFERENCES [dbo].[Products] ([ProductID])
);
GO
