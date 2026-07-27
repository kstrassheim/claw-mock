CREATE TABLE [dbo].[Suppliers] (
    [SupplierID]   INT           NOT NULL IDENTITY(1,1),
    [CompanyName]  NVARCHAR(40)  NOT NULL,
    [ContactName]  NVARCHAR(30)  NULL,
    [ContactTitle] NVARCHAR(30)  NULL,
    [City]         NVARCHAR(15)  NULL,
    [Country]      NVARCHAR(15)  NULL,
    [Phone]        NVARCHAR(24)  NULL,
    CONSTRAINT [PK_Suppliers] PRIMARY KEY CLUSTERED ([SupplierID] ASC)
);
GO
