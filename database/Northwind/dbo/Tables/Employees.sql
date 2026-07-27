CREATE TABLE [dbo].[Employees] (
    [EmployeeID] INT          NOT NULL IDENTITY(1,1),
    [LastName]   NVARCHAR(20) NOT NULL,
    [FirstName]  NVARCHAR(10) NOT NULL,
    [Title]      NVARCHAR(30) NULL,
    [HireDate]   DATETIME2    NULL,
    [City]       NVARCHAR(15) NULL,
    [Country]    NVARCHAR(15) NULL,
    CONSTRAINT [PK_Employees] PRIMARY KEY CLUSTERED ([EmployeeID] ASC)
);
GO
