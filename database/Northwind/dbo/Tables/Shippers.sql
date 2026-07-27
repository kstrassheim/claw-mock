CREATE TABLE [dbo].[Shippers] (
    [ShipperID]   INT          NOT NULL IDENTITY(1,1),
    [CompanyName] NVARCHAR(40) NOT NULL,
    [Phone]       NVARCHAR(24) NULL,
    CONSTRAINT [PK_Shippers] PRIMARY KEY CLUSTERED ([ShipperID] ASC)
);
GO
