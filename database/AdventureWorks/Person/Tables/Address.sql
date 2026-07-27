CREATE TABLE [Person].[Address] (
    [AddressID]       INT            NOT NULL IDENTITY(1,1),
    [AddressLine1]    NVARCHAR(60)   NOT NULL,
    [AddressLine2]    NVARCHAR(60)   NULL,
    [City]            NVARCHAR(30)   NOT NULL,
    [StateProvinceID] INT            NOT NULL,
    [PostalCode]      NVARCHAR(15)   NOT NULL,
    [rowguid]         UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_Address_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]    DATETIME2      NOT NULL CONSTRAINT [DF_Address_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Address_AddressID] PRIMARY KEY CLUSTERED ([AddressID] ASC),
    CONSTRAINT [FK_Address_StateProvince] FOREIGN KEY ([StateProvinceID])
        REFERENCES [Person].[StateProvince] ([StateProvinceID])
);
GO
