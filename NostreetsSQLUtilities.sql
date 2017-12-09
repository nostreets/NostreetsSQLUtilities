
/*

Nostreets SQL Utility Functions and Stored Procedures

	Author: Nile Overstreet

*/
----------------------------------------------------------------------------------------------------------------------------------

ALTER Proc [dbo].[CheckIfTablesAreEmtpy]
AS
	BEGIN

	exec  sp_msforeachtable "IF EXISTS (select * from ?) begin print('? has rows') end else begin print('? NO rows'); end;"

	END

----------------------------------------------------------------------------------------------------------------------------------

ALTER Function [dbo].[IsLastDayOfMonth](
	@Date datetime = null
)
Returns bit
/*
Select dbo.IsLastDayOfMonth('5/31/17')

select DATEADD(dd, 1, '5/31/17') 
select DATEPART(dd, DATEADD(dd, 1, GETDATE()) )

select DATEPART( mm, '5/31/17') 
*/
AS

BEGIN
		IF @Date is null
			BEGIN
			IF (DATEPART(dd, DATEADD(dd, 1, GETDATE()) ) = 1)
				BEGIN
					RETURN 1
				END

			END
		ELSE
			BEGIN
				IF (DATEPART(dd, DATEADD(dd, 1, @Date ) ) = 1)
					BEGIN
						RETURN 1
					END

			END
	RETURN 0 
END

----------------------------------------------------------------------------------------------------------------------------------

ALTER Function [dbo].[FindLastDayOfMonth](
	@Date datetime 
)
Returns datetime
/*

select dbo.FindLastDayOfMonth(NULL)

DECLARE @D DATETIME = '12/03/2017'
SET @D = DATEADD(MM, 1, @D)
SET @D = Convert(varchar(12), DATEPART(mm, @D), 110) + '/1/' + Convert(varchar(12), DATEPART(yy, @D), 110) + ' 23:59:59.99' 
SET @D = DATEADD(DD, -1, @D)
SELECT @D
*/
AS

BEGIN

if @Date is null
	BEGIN
		SET @Date = GETDATE()
	END
SET @Date= DATEADD(MM, 1, @Date)
SET @Date= Convert(varchar(12), DATEPART(mm, @Date), 110) + '/1/' + Convert(varchar(12), DATEPART(yy, @Date), 110) + ' 23:59:59.99' 
SET @Date = DATEADD(DD, -1, @Date)

--DECLARE @isLastDay BIT = dbo.IsLastDayOfMonth(@Date) 

--WHILE @isLastDay = 0
--	BEGIN
--		SET @isLastDay = dbo.IsLastDayOfMonth(@Date) 
--		IF @isLastDay = 0
--		BEGIN
--			Set @Date = DATEADD(dd, 1, @Date) 
--		END
		
--	END
--	SET @Date = CONVERT(NVARCHAR(12), @Date, 110) + ' 23:59:59.99'
	RETURN @Date
END

----------------------------------------------------------------------------------------------------------------------------------

ALTER  Function [dbo].[FindFirstDayOfMonth](
	@Date dateTIME 
)
Returns datetime
/*---------------- TEST CODE-------------
Select dbo.IsLastDayOfMonth('5/31/17')

select dbo.FindFirstDayOfMonth(NUlL)
*/
AS

BEGIN
	if @Date is null
	Begin
		Set @Date = GETDATE()
	End
	
	Set @Date = Convert(varchar(12), DATEPART(mm, @Date), 110) + '/1/' + Convert(varchar(12), DATEPART(yy, @Date), 110) + ' 00:00:00' 

	RETURN  @Date
END

----------------------------------------------------------------------------------------------------------------------------------

ALTER FUNCTION [dbo].[SDF_SplitString]
(
    @sString nvarchar(MAX),
    @cDelimiter nchar(1)
)
RETURNS @tParts TABLE ( part nvarchar(2048) )
/* -------- Test Code ----------------
		DECLARE @example VARCHAR(120) = 'able,word,stuff'
		SELECT SUBSTRING(@example, 1, 1)
		SELECT *  FROM SDF_SplitString (@example , ',')
*/
AS
BEGIN
    IF @sString IS NULL RETURN

    DECLARE @iStart INT
	, @iPos INT

    IF SUBSTRING( @sString, 1, 1 ) = @cDelimiter 
    BEGIN
        SET @iStart = 2
        INSERT INTO @tParts
        VALUES( NULL )
    END
    ELSE 
		BEGIN
			SET @iStart = 1
		END

    WHILE 1=1
		BEGIN
			SET @iPos = CHARINDEX( @cDelimiter, @sString, @iStart )
			IF @iPos = 0
				SET @iPos = LEN( @sString )+1
			IF @iPos - @iStart > 0          
				INSERT INTO @tParts
				VALUES  ( SUBSTRING( @sString, @iStart, @iPos-@iStart ))
			ELSE
				INSERT INTO @tParts
				VALUES( NULL )
			SET @iStart = @iPos+1
			IF @iStart > LEN( @sString ) 
				BREAK
		END
    RETURN

END

----------------------------------------------------------------------------------------------------------------------------------

ALTER PROC	[dbo].[EnableOrDisableConstrants]
	@Disable BIT = 0,
	@Enable	BIT = 0
AS
/*
TEST CODE

EXEC [amk_EnableOrDisableConstrants] 1

EXEC [amk_EnableOrDisableConstrants] 0,1

select * from sys.foreign_keys
*/

BEGIN

IF(@Disable = 1)
	BEGIN
		-- Disable all constraints for database
		EXEC sp_msforeachtable "ALTER TABLE ? NOCHECK CONSTRAINT all" 

	END

IF(@Enable = 1)	
	BEGIN
	-- Enable all constraints for database
		EXEC sp_msforeachtable "ALTER TABLE ? WITH CHECK CHECK CONSTRAINT all"  
	END

	print('SUCCESS')

END


----------------------------------------------------------------------------------------------------------------------------------

ALTER Proc [dbo].[GetAllJobs]
AS
BEGIN
/*
TEST 
EXEC amk_GetAllJobs
*/
SELECT 
	RS.ScheduleId AS ScheduleId_JobName
	, S.[SubscriptionID]
      ,  CASE WHEN S.Description != ''
         THEN S.Description 
         Else  'N/A' 
         END AS Description
     
  FROM [ReportServer].[dbo].[Subscriptions] AS S
  INNER JOIN [ReportServer].[dbo].ReportSchedule AS RS
  ON RS.SubscriptionID = S.SubscriptionID
  --WHERE S.Description  like '%WEEKLY%'
   --WHERE S.Description  like '%AMCAD%'
  --WHERE Description not like '%Quarterly%'
  --exec [MSDB].[DBO].SP_START_JOB    @job_name = 'C27BF464-A7FA-486D-A505-9BFAA49C8139' ,@step_name= 'C27BF464-A7FA-486D-A505-9BFAA49C8139_step_1'
 

END

----------------------------------------------------------------------------------------------------------------------------------

ALTER Proc [dbo].[GetCountOfRows]
AS
BEGIN
/*
TEST 
EXEC amk_GetAllJobs
*/
SELECT
      QUOTENAME(SCHEMA_NAME(sOBJ.schema_id)) + '.' + QUOTENAME(sOBJ.name) AS [TableName]
      , SUM(sPTN.Rows) AS [RowCount]
FROM 
      sys.objects AS sOBJ
      INNER JOIN sys.partitions AS sPTN
            ON sOBJ.object_id = sPTN.object_id
WHERE
      sOBJ.type = 'U'
      AND sOBJ.is_ms_shipped = 0x0
      AND index_id < 2 -- 0:Heap, 1:Clustered
GROUP BY 
      sOBJ.schema_id
      , sOBJ.name
ORDER BY [TableName]

---------------------------------------------------------------------------------------------------------------------------------------------