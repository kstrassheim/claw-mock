CREATE TABLE [Sales].[Store] (
    [StoreID]      INT            NOT NULL IDENTITY(1,1),
    [Name]         NVARCHAR(50)   NOT NULL,
    [SalesPersonID] INT           NULL,
    [rowguid]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_Store_rowguid] DEFAULT (NEWID()),
    [ModifiedDate] DATETIME2      NOT NULL CONSTRAINT [DF_Store_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Store_StoreID] PRIMARY KEY CLUSTERED ([StoreID] ASC)
);
GO
