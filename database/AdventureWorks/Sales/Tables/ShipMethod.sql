CREATE TABLE [Sales].[ShipMethod] (
    [ShipMethodID] INT            NOT NULL IDENTITY(1,1),
    [Name]         NVARCHAR(50)   NOT NULL,
    [ShipBase]     MONEY          NOT NULL CONSTRAINT [DF_ShipMethod_ShipBase] DEFAULT (0),
    [ShipRate]     MONEY          NOT NULL CONSTRAINT [DF_ShipMethod_ShipRate] DEFAULT (0),
    [rowguid]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_ShipMethod_rowguid] DEFAULT (NEWID()),
    [ModifiedDate] DATETIME2      NOT NULL CONSTRAINT [DF_ShipMethod_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_ShipMethod_ShipMethodID] PRIMARY KEY CLUSTERED ([ShipMethodID] ASC)
);
GO
