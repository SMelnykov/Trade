/*

Create database

*/
SET ANSI_NULLS,ANSI_PADDING,ANSI_WARNINGS,ARITHABORT,CONCAT_NULL_YIELDS_NULL,QUOTED_IDENTIFIER ON
SET NUMERIC_ROUNDABORT OFF
SET XACT_ABORT ON
SET NOCOUNT ON

Declare @DbName sysname = '$(Database_Name)'

if exists(Select * from sys.databases Where name = @DbName)
  begin
    RaisError ('Database %s already exists', 10, 10, @DbName)
  end
  else
  begin  
    CREATE DATABASE $(Database_Name) COLLATE Latin1_General_CI_AS
  end  
