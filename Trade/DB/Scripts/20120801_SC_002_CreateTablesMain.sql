/*
  Create loaded tables
*/

USE $(Database_Name)

SET ANSI_NULLS,ANSI_PADDING,ANSI_WARNINGS,ARITHABORT,CONCAT_NULL_YIELDS_NULL,QUOTED_IDENTIFIER ON
SET NUMERIC_ROUNDABORT OFF
SET XACT_ABORT ON


if object_id(N'dbo.Loaded_Ticker', 'U') is not null
begin
   print 'Table Loaded_Ticker already exists'
end
else
begin
   BEGIN TRANSACTION

    CREATE TABLE [dbo].[Loaded_Ticker](
        [TICKER] [varchar](10) NOT NULL,
        [PER] [varchar](3) NOT NULL,
        [DATE] [datetime] NOT NULL,
        [OPEN] [money] NOT NULL,
        [HIGH] [money] NOT NULL,
        [LOW] [money] NOT NULL,
        [CLOSE] [money] NOT NULL,
        [VOL] [int] NOT NULL,
        [OPENINT] [int] NOT NULL,
        [id] [int] IDENTITY(1,1) NOT NULL
) ON [PRIMARY]

   COMMIT TRANSACTION
end

