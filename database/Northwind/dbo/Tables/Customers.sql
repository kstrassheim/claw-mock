CREATE TABLE [dbo].[Customers] (
    [CustomerID]   NCHAR(5)     NOT NULL,
    [CompanyName]  NVARCHAR(40) NOT NULL,
    [ContactName]  NVARCHAR(30) NULL,
    [ContactTitle] NVARCHAR(30) NULL,
    [City]         NVARCHAR(15) NULL,
    [Country]      NVARCHAR(15) NULL,
    [Phone]        NVARCHAR(24) NULL,
    CONSTRAINT [PK_Customers] PRIMARY KEY CLUSTERED ([CustomerID] ASC)
);
GO
