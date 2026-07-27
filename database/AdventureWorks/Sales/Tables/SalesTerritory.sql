CREATE TABLE [Sales].[SalesTerritory] (
    [TerritoryID]       INT            NOT NULL IDENTITY(1,1),
    [Name]              NVARCHAR(50)   NOT NULL,
    [CountryRegionCode] NVARCHAR(3)    NOT NULL,
    [Group]             NVARCHAR(50)   NOT NULL,
    [SalesYTD]          MONEY          NOT NULL CONSTRAINT [DF_SalesTerritory_SalesYTD] DEFAULT (0),
    [CostYTD]           MONEY          NOT NULL CONSTRAINT [DF_SalesTerritory_CostYTD] DEFAULT (0),
    [rowguid]           UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_SalesTerritory_rowguid] DEFAULT (NEWID()),
    [ModifiedDate]      DATETIME2      NOT NULL CONSTRAINT [DF_SalesTerritory_ModifiedDate] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_SalesTerritory_TerritoryID] PRIMARY KEY CLUSTERED ([TerritoryID] ASC)
);
GO
