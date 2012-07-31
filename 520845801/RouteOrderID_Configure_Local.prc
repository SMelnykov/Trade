SET QUOTED_IDENTIFIER, ANSI_NULLS ON
GO

IF NOT EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[dbo].[RouteOrderID_Configure_Local]') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
EXEC ('CREATE PROCEDURE [dbo].[RouteOrderID_Configure_Local]
AS
RETURN -1')
GO


ALTER PROCEDURE dbo.RouteOrderID_Configure_Local
   @ExecutionSystemRouteID int,
   @IgnoreInvalidRanges bit
/****************************************************************************************
Name of object: RouteOrderID_Configure_Local
DateCreated:    Apr 13 2010
CreatedBy:      Vladimir Davidenko
Application:    Gateway
Project:        Solution 3 Phase 2. Feature #887052
Location:       LDBs

Description:    Configurate RouteOrderIds of specified route on the current location

Modifications:
Apr 13 2010    vladd             Initial version
Jun 01 2010    valdd             GetRouteOrderIDLimit function is used for RouteOrderIDLimit reading
                                 DSI 247575209. Feature #958229.
Jun 17 2010    vladd             Solution 3 Phase 2. Implementation of DSI 247578308. Feature #958229
                                 SP is modified for using replication instead linked servers for transmission
                                 of RouteOrderID information.
Oct 21 2010    slava             Subroute support\1159574 RoutingCode -> ExecutionSystemRouteID
Nov 19 2010    slava             Subroute support\1159574 fill gaps between confirmed ranges by free ranges - small fix
Jun 27 2011    slava             DE 297385308 Small change to avoid int overflow
Mar 30 2011    vladd             Expirable range support was added.
                                 Resubmission & Exchange Disconnects project. Feature #904260.
Jul 23 2012    Melnykov          DSI 520845801. Add @IgnoreInvalidRanges parameter for dropping invalid ranges
****************************************************************************************/
as

set nocount on

declare @ErrorStr varchar(1024)  -- Error string definition

declare @FreeRange int
declare @ConfirmedRange int
select @FreeRange = 1         -- status ID of free range
     , @ConfirmedRange = 3    -- status ID of confirmed range

-- Start transaction for deleting old ranges and creating new
declare @TranCount int
set @TranCount = @@TRANCOUNT

if @TranCount > 0
begin
   save transaction ROID_Configure_LocalTrans
end
else
begin
   begin transaction ROID_Configure_LocalTrans
end

-- insert free ranges for routes which haven't 'ROID in use'
insert into dbo.RouteOrderID_Ranges(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, StatusID)
select esr.ID, 1, dbo.GetRouteOrderIDLimit(esr.ID), NULL, @FreeRange
from dbo.ExecutionSystemRoute as esr with (nolock)
where (@ExecutionSystemRouteID is NULL or @ExecutionSystemRouteID = esr.ID) and esr.LocationID = dbo.GetCurrentLocationID()
      and not exists (select * from dbo.RouteOrderID_Config_CDB_to_LDB roc where roc.ExecutionSystemRouteID = esr.ID)

if @@error <> 0
begin
   set @ErrorStr = 'Cannot insert free ranges for routes which haven''t ''ROID in use''.'
   goto HANDLE_ERROR
end

-- insert confirmed ranges
insert into dbo.RouteOrderID_Ranges(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, StatusID, tsExpiration)
select ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, @ConfirmedRange, tsExpiration
from dbo.RouteOrderID_Config_CDB_to_LDB
where @ExecutionSystemRouteID is NULL or ExecutionSystemRouteID = @ExecutionSystemRouteID

if @@error <> 0
begin
   set @ErrorStr = 'Cannot insert confirmed ranges.'
   goto HANDLE_ERROR
end

-- fill gaps between confirmed ranges by free ranges
insert into dbo.RouteOrderID_Ranges(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, StatusID)
select x.ExecutionSystemRouteID, x.MaxRouteOrderID + 1, y.MinRouteOrderID-1, NULL, @FreeRange
from dbo.RouteOrderID_Config_CDB_to_LDB as x
inner join dbo.RouteOrderID_Config_CDB_to_LDB as y on x.ExecutionSystemRouteID = y.ExecutionSystemRouteID
                                                      --casting to avoif int overflow
                                                      and cast(x.MaxRouteOrderID as bigint) + 1 < cast(y.MinRouteOrderID as bigint)
where (@ExecutionSystemRouteID is NULL or @ExecutionSystemRouteID = x.ExecutionSystemRouteID)
       and not exists(select * from RouteOrderID_Config_CDB_to_LDB
                      where ExecutionSystemRouteID = x.ExecutionSystemRouteID and MinRouteOrderID > x.MaxRouteOrderID
                            and MinRouteOrderID < y.MinRouteOrderID)

if @@error <> 0
begin
   set @ErrorStr = 'Cannot insert free ranges between confirmed ranges.'
   goto HANDLE_ERROR
end

-- insert first free range if it is required
insert into dbo.RouteOrderID_Ranges(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, StatusID)
select ExecutionSystemRouteID, 1, min(MinRouteOrderID) - 1, NULL, @FreeRange  from dbo.RouteOrderID_Config_CDB_to_LDB
where @ExecutionSystemRouteID is NULL or ExecutionSystemRouteID = @ExecutionSystemRouteID
group by ExecutionSystemRouteID
having min(MinRouteOrderID) > 1

if @@error <> 0
begin
   set @ErrorStr = 'Cannot insert free range before the first confirmed range.'
   goto HANDLE_ERROR
end

-- insert last free range if it is required
insert into dbo.RouteOrderID_Ranges(ExecutionSystemRouteID, MinRouteOrderID, MaxRouteOrderID, RSInstanceID, StatusID)
select ExecutionSystemRouteID, max(MaxRouteOrderID) + 1, dbo.GetRouteOrderIDLimit(ExecutionSystemRouteID), NULL, @FreeRange
from dbo.RouteOrderID_Config_CDB_to_LDB
where @ExecutionSystemRouteID is NULL or ExecutionSystemRouteID = @ExecutionSystemRouteID
group by ExecutionSystemRouteID
having max(MaxRouteOrderID) < dbo.GetRouteOrderIDLimit(ExecutionSystemRouteID)

if @@error <> 0
begin
   set @ErrorStr = 'Cannot insert free range after the latest confirmed range.'
   goto HANDLE_ERROR
end

-- Commit transaction
while @TranCount < @@TRANCOUNT
begin
   commit transaction
end

return 0

HANDLE_ERROR:

-- Rollback transaction
if @@TRANCOUNT > 0
begin
   rollback transaction ROID_Configure_LocalTrans
end

-- Log error
execute dbo.DoLogError
   @Num = 1,
   @Severity = 2,      -- Alert
   @TextMask = @ErrorStr,
   @SourceNumber = 40,
   @SP_ID= @@PROCID

raiserror(@ErrorStr, 16, 1)

return -1

GO

