CREATE TABLE [dbo].[Categories] (
    [CategoryID]   INT           NOT NULL IDENTITY(1,1),
    [CategoryName] NVARCHAR(15)  NOT NULL,
    [Description]  NVARCHAR(MAX) NULL,
    CONSTRAINT [PK_Categories] PRIMARY KEY CLUSTERED ([CategoryID] ASC)
);
GO
