CREATE TABLE [Person].[StateProvince] (
    [StateProvinceID]   INT            NOT NULL IDENTITY(1,1),
    [StateProvinceCode] NCHAR(3)       NOT NULL,
    [CountryRegionCode] NVARCHAR(3)    NOT NULL,
    [Name]              NVARCHAR(50)   NOT NULL,
    [TerritoryID]       INT            NOT NULL,
    [rowguid]           UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_StateProvince_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]      DATETIME2      NOT NULL CONSTRAINT [DF_StateProvince_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_StateProvince_StateProvinceID] PRIMARY KEY CLUSTERED ([StateProvinceID] ASC)
);
GO
