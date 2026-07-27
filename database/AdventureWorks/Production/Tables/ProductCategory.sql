CREATE TABLE [Production].[ProductCategory] (
    [ProductCategoryID] INT            NOT NULL IDENTITY(1,1),
    [Name]              NVARCHAR(50)   NOT NULL,
    [rowguid]           UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_ProductCategory_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]      DATETIME2      NOT NULL CONSTRAINT [DF_ProductCategory_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_ProductCategory_ProductCategoryID] PRIMARY KEY CLUSTERED ([ProductCategoryID] ASC)
);
GO
