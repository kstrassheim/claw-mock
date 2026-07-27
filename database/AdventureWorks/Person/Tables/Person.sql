CREATE TABLE [Person].[Person] (
    [BusinessEntityID] INT            NOT NULL IDENTITY(1,1),
    [PersonType]       NCHAR(2)       NOT NULL,
    [NameStyle]        BIT            NOT NULL CONSTRAINT [DF_Person_NameStyle] DEFAULT (0),
    [Title]            NVARCHAR(8)    NULL,
    [FirstName]        NVARCHAR(50)   NOT NULL,
    [MiddleName]       NVARCHAR(50)   NULL,
    [LastName]         NVARCHAR(50)   NOT NULL,
    [EmailPromotion]   INT            NOT NULL CONSTRAINT [DF_Person_EmailPromotion] DEFAULT (0),
    [rowguid]          UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_Person_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]     DATETIME2      NOT NULL CONSTRAINT [DF_Person_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Person_BusinessEntityID] PRIMARY KEY CLUSTERED ([BusinessEntityID] ASC)
);
GO
