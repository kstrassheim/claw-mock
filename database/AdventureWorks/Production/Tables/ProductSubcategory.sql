CREATE TABLE [Production].[ProductSubcategory] (
    [ProductSubcategoryID] INT            NOT NULL IDENTITY(1,1),
    [ProductCategoryID]    INT            NOT NULL,
    [Name]                 NVARCHAR(50)   NOT NULL,
    [rowguid]              UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_ProductSubcategory_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]         DATETIME2      NOT NULL CONSTRAINT [DF_ProductSubcategory_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_ProductSubcategory_ProductSubcategoryID] PRIMARY KEY CLUSTERED ([ProductSubcategoryID] ASC),
    CONSTRAINT [FK_ProductSubcategory_ProductCategory] FOREIGN KEY ([ProductCategoryID])
        REFERENCES [Production].[ProductCategory] ([ProductCategoryID])
);
GO
