SET QUOTED_IDENTIFIER, ANSI_NULLS ON
GO

IF NOT EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[dbo].[RouteOrderID_Configure]') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
EXEC ('CREATE PROCEDURE [dbo].[RouteOrderID_Configure]
AS
RETURN -1')
GO


ALTER PROCEDURE dbo.RouteOrderID_Configure
   @ExecutionSystemRouteID int = NULL,
   @IgnoreInvalidRanges bit = 0
/**********************************
Name of object: RouteOrderID_Configure
DateCreated:    Mar 04 2009
CreatedBy:      Vladimir Davidenko
Application:    Gateway
Project:        Solution 3 Phase 2. Feature #887052
Location:       CDB

hhhh
ggggg

Description:    Generates RouteOrderID ranges for specifed route and location

hhh

Modifications:
May 13 2009  vladd           DE 195824007 Refresh RouteOrderID_Excluded table from LocalDBs
Jun 12 2009  vladd           SU 196896101 Add @RoutingCode parameter for configuration of the specified route
Nov 27 2009  Ivan Tuzov      DE 230658301 reference to non existing column
Mar 01 2010  Yuriy Zubritsky SU 232296413. Ability to set per-route ROID maximum.
Mar 22 2010  SKanadin        DE 244631402. Procedure dbo.RouteOrderID_Configure fails, when Location is offline.
                             Added check on Locaion.IsOnline = 1 and changed logic, when found Offline server.
--------------------------------
  Apr 13 2010  vladd         Solution 3 Phase 2. Feature #887052
                             SP was completely rewritten for Solution 3 project. In this project we use completely
                             different way to allocate ROIDs, so original version cannot be used anymore
  May 05 2010  vladd         Solution 3 Phase 2. Feature #887052
                             @LocationID parameter is removed. LocationID from RoutingDefaults table is used by SP.
  May 21 2010  vladd         Solution 3 Phase 2. Feature #887052
                             PRINT statement is use for offline database error logging instead RAISERROR statement
  Jun 01 2010  vladd         Solution 3 Phase 2. Fix of DSI 247575209. Feature #958229
                             SP checks that all 'ROIDs in use' is less than or equal to RouteOrderIDLimit.
                             SP checks that route hasn't already been configured on other locations.
  Jun 16 2010  vladd         Solution 3 Phase 2. Implementation of DSI 247578308. Feature #958229
                             SP is modified for using replication instead linked servers for transmission
                             of RouteOrderID information.
--------------------------------
Jun 16 2010      Zyuzin      Added LocationID column (Defect #247917804).
Oct 21 2010      slava       Subroute support\1159574 RoutingCode -> ExecutionSystemRouteID
Mar 30 2011      vladd       Expirable range support was added.
                             Resubmission & Exchange Disconnects project. Feature #904260.
Apr 26 2011      vladd       tsExpirable field of RouteOrderID_... tables was replaced by tsExpiration.
                             DSI 286448401. Resubmission & Exchange Disconnects project. Feature #904260.
Jul 23 2012      Melnykov    DSI 520845801. Add @IgnoreInvalidRanges parameter for dropping invalid ranges
**********************************/
as

set nocount on

declare @ErrorStr varchar(1024)  -- Error string definition
declare @Result int

-- Ensure that SP is not running
declare @LockString nvarchar(255)
set @LockString = N'RouteOrderID_Configure_Lock'
exec @Result = sp_getapplock @Resource = @LockString, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0
if @Result < 0
begin
   set @ErrorStr = 'dbo.RouteOrderID_Configure is working already. Please wait till SP completion and try again.'
   goto HANDLE_ERROR
end

-- Check LocationID from ExecutionSystemRoute table
if exists(
   select *
   from (
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is NULL
      union all
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is not NULL
         and @ExecutionSystemRouteID = ID) x
   where LocationID = 0
   )
begin
   -- print warning
   -- Create cursor for routes with wrong 'ROIDs in use'
   declare RouteCursor cursor local static forward_only for
   select x.ID
   from (
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is NULL
      union all
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is not NULL
         and @ExecutionSystemRouteID = ID) x
   where LocationID = 0
   open RouteCursor

   declare @LocalExecutionSystemRouteID int

   fetch next from RouteCursor
   into @LocalExecutionSystemRouteID

   while @@FETCH_STATUS = 0
   begin
      set @ErrorStr = 'Execution system route ' + cast(@LocalExecutionSystemRouteID as nvarchar(11))
                      + ' is skipped because LocationID is not defined for the route.'

      -- Log error
      execute dbo.DoLogError
         @Num = 1,
         @Severity = 2,
         @TextMask = @ErrorStr,
         @SourceNumber = 40,
         @SP_ID= @@PROCID

      print @ErrorStr

      fetch next from RouteCursor
      into @LocalExecutionSystemRouteID
   end

   close RouteCursor
   deallocate RouteCursor

   set @ErrorStr = NULL
end

-- Check that we have at least one route for configuration
if not exists(
   select *
   from (
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is NULL
      union all
      select *
      from dbo.ExecutionSystemRoute
      where @ExecutionSystemRouteID is not NULL
         and @ExecutionSystemRouteID = ID) x
   where LocationID <> 0
   )
begin
      set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed, because LocationID for all specified'
                      + ' routes is not defined.'
      goto RELEASE_APPLOCK_AND_HANDLE_ERROR
end

-- Ensure that all local database are online
if exists(select LocationID from dbo.Location with (nolock) where IsCentralDB = 0 and IsOnline = 0)
begin
   declare @offline_servers varchar(128)
   set @offline_servers ='';

   select @offline_servers = @offline_servers + Name + '(ID ' + cast(LocationID as varchar(3)) + ') '
   from dbo.Location with (nolock)
   where IsCentralDB = 0 and IsOnline = 0

   set @ErrorStr = 'dbo.RouteOrderID_Configure skipped next LDBs, because locations are offline: '
                  + @offline_servers

   -- Log error
   execute dbo.DoLogError
      @Num = 1,
      @Severity = 2,
      @TextMask = @ErrorStr,
      @SourceNumber = 40,
      @SP_ID= @@PROCID

   print @ErrorStr
   -- clear error message
   set @ErrorStr = NULL
end

-- Create cursor for Location table
declare LocationCursor cursor local static forward_only for
select LS.LinkedServer, LS.RemoteDatabaseName, LS.LocationID
from dbo.Location L with (nolock)
   inner join dbo.LocationSite LS with (nolock) on L.LocationID = LS.LocationID
where L.IsCentralDB = 0
   and LS.LocationSiteDBStateID = 1  -- Active state
   and L.IsOnline = 1

declare @LinkedServerName nvarchar(64)
declare @RemoteDBName varchar(64)
declare @DBLocationID int

declare @SQLCommand nvarchar(512)
declare @ParmDefinition nvarchar(512)
declare @ExecuteResult int

open LocationCursor

fetch next from LocationCursor
into @LinkedServerName, @RemoteDBName, @DBLocationID

-- Run RouteOrderID_CollectRangesInUse SP on all local DBs
begin try
   while @@FETCH_STATUS = 0
   begin
      set @SQLCommand = N'exec @ResultOUT = ' + @LinkedServerName + N'.' + @RemoteDBName
                        + N'.dbo.RouteOrderID_CollectRangesInUse @ExecutionSystemRouteID = @ExecutionSystemRouteIDIN'
      set @ParmDefinition = N'@ResultOUT int OUTPUT, @ExecutionSystemRouteIDIN int'

      exec @ExecuteResult = sp_executesql @SQLCommand, @ParmDefinition,
                                          @ResultOUT = @Result OUTPUT, @ExecutionSystemRouteIDIN = @ExecutionSystemRouteID
      if @ExecuteResult <> 0 or @Result <> 0
      begin
         set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed properly, because'
                         + ' RouteOrderID_CollectRangesInUse SP of Location (LocationID = '
                         + cast(@DBLocationID as varchar(11))  + ') has failed.'
         goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
      end

      fetch next from LocationCursor
      into @LinkedServerName, @RemoteDBName, @DBLocationID
   end
end try
begin catch
   set @ErrorStr = 'dbo.RouteOrderID_Configure error while reading from remote linked server '
                   + @LinkedServerName
                   + '(Error ' + cast( ERROR_NUMBER() as varchar(10))
                   + ' ' + ERROR_MESSAGE()
                   + '). '

   goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
end catch

close LocationCursor

-- Wait till replication completion from LDBs to CDB
open LocationCursor

fetch next from LocationCursor
into @LinkedServerName, @RemoteDBName, @DBLocationID
while @@FETCH_STATUS = 0
begin

   exec @ExecuteResult = dbo.WaitForSync @LocationID = @DBLocationID, @Multiplier = 4
   if @ExecuteResult <> 0
   begin
      set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed properly, because data replication'
                      + ' from LDB(LocationID = '
                      + cast(@DBLocationID as varchar(11))  + ') has been delayed.'
      goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
   end

   fetch next from LocationCursor
   into @LinkedServerName, @RemoteDBName, @DBLocationID
end

close LocationCursor

-- prepare data for local configuration
delete from dbo.RouteOrderID_Config_CDB_to_LDB

if @@error <> 0
begin
   set @ErrorStr = 'dbo.RouteOrderID_Config_CDB_to_LDB table clearing has failed.'
   goto RELEASE_APPLOCK_AND_HANDLE_ERROR
end

insert into dbo.RouteOrderID_Config_CDB_to_LDB(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, LocationID, tsExpiration)
select ldb.ExecutionSystemRouteID, ldb.MinRouteOrderID, ldb.MaxRouteOrderID, ldb.RSInstanceID, esr.LocationID, ldb.tsExpiration
from dbo.RouteOrderID_Config_LDB_to_CDB as ldb
inner join dbo.ExecutionSystemRoute as esr on esr.ID = ldb.ExecutionSystemRouteID

if @@error <> 0
begin
   set @ErrorStr = 'Cannot copy ranges from dbo.RouteOrderID_Config_LDB_to_CDB table to dbo.RouteOrderID_Config_CDB_to_LDB.'
   goto RELEASE_APPLOCK_AND_HANDLE_ERROR
end

-- Run RouteOrderID_ClearRanges SP on all local DBs
open LocationCursor

fetch next from LocationCursor
into @LinkedServerName, @RemoteDBName, @DBLocationID

begin try
   while @@FETCH_STATUS = 0
   begin
      set @SQLCommand = N'exec @ResultOUT = ' + @LinkedServerName + N'.' + @RemoteDBName
                        + N'.dbo.RouteOrderID_ClearRanges @ExecutionSystemRouteID = @ExecutionSystemRouteIDIN'
      set @ParmDefinition = N'@ResultOUT int OUTPUT, @ExecutionSystemRouteIDIN int'

      exec @ExecuteResult = sp_executesql @SQLCommand, @ParmDefinition,
                                          @ResultOUT = @Result OUTPUT, @ExecutionSystemRouteIDIN = @ExecutionSystemRouteID
      if @ExecuteResult <> 0 or @Result <> 0
      begin
         set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed properly, because'
                         + ' RouteOrderID_ClearRanges SP of Location (LocationID = '
                         + cast(@DBLocationID as varchar(11))  + ') has failed.'
         goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
      end

      fetch next from LocationCursor
      into @LinkedServerName, @RemoteDBName, @DBLocationID
   end
end try
begin catch
   set @ErrorStr = 'dbo.RouteOrderID_Configure error while reading from remote linked server '
                   + @LinkedServerName
                   + '(Error ' + cast( ERROR_NUMBER() as varchar(10))
                   + ' ' + ERROR_MESSAGE()
                   + '). '

   goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
end catch

close LocationCursor

-- Wait till replication completion from CDB to LDBs
open LocationCursor

fetch next from LocationCursor
into @LinkedServerName, @RemoteDBName, @DBLocationID

while @@FETCH_STATUS = 0
begin

   exec @ExecuteResult = dbo.WaitForSync @LocationID = @DBLocationID, @Multiplier = 4
   if @ExecuteResult <> 0
   begin
      set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed properly, because data replication'
                      + ' to LDB(LocationID = '
                      + cast(@DBLocationID as varchar(11))  + ') has been delayed.'
      goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
   end

   fetch next from LocationCursor
   into @LinkedServerName, @RemoteDBName, @DBLocationID
end

close LocationCursor

-- Apply local configuration SP for all locations
open LocationCursor

fetch next from LocationCursor
into @LinkedServerName, @RemoteDBName, @DBLocationID

begin try
   while @@FETCH_STATUS = 0
   begin
      set @SQLCommand = N'exec @ResultOUT = ' + @LinkedServerName + N'.' + @RemoteDBName
                        + N'.dbo.RouteOrderID_Configure_Local @ExecutionSystemRouteID = @ExecutionSystemRouteIDIN'
      set @ParmDefinition = N'@ResultOUT int OUTPUT, @ExecutionSystemRouteIDIN int, @IgnoreInvalidRanges bit'

      exec @ExecuteResult = sp_executesql @SQLCommand, @ParmDefinition
                                         ,@ResultOUT                = @Result OUTPUT
                                         ,@ExecutionSystemRouteIDIN = @ExecutionSystemRouteID
                                         ,@IgnoreInvalidRanges      = @IgnoreInvalidRanges
      if @ExecuteResult <> 0 or @Result <> 0
      begin
         set @ErrorStr = 'dbo.RouteOrderID_Configure cannot be executed properly, because'
                         + ' RouteOrderID_Configure_Local SP of Location (LocationID = '
                         + cast(@DBLocationID as varchar(11))  + ') has failed.'
         goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
      end

      fetch next from LocationCursor
      into @LinkedServerName, @RemoteDBName, @DBLocationID
   end
end try
begin catch
   set @ErrorStr = 'dbo.RouteOrderID_Configure error while reading from remote linked server '
                   + @LinkedServerName
                   + '(Error ' + cast( ERROR_NUMBER() as varchar(10))
                   + ' ' + ERROR_MESSAGE()
                   + '). '

   goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
end catch

-- Clear temporary table on CDB
delete from dbo.RouteOrderID_Config_CDB_to_LDB

if @@error <> 0
begin
   set @ErrorStr = 'dbo.RouteOrderID_Config_CDB_to_LDB table clearing has failed.'
   goto CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR
end

-- the end
CLOSE_LOCATION_CURSOR_AND_HANDLE_ERROR:

close LocationCursor
deallocate LocationCursor

RELEASE_APPLOCK_AND_HANDLE_ERROR:

exec sp_releaseapplock @Resource = @LockString, @LockOwner = 'Session'

HANDLE_ERROR:

if @ErrorStr is not NULL
begin
   -- Log error
   execute dbo.DoLogError
      @Num = 1,
      @Severity = 2,      -- Alert
      @TextMask = @ErrorStr,
      @SourceNumber = 40,
      @SP_ID= @@PROCID

   raiserror(@ErrorStr, 16, 1)

   return -1
end

return 0

GO

