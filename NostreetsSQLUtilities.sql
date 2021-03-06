
/*

Nostreets SQL Utility Functions and Stored Procedures

	Author: Nile Overstreet

*/

--#region CheckIfTablesAreEmtpy
CREATE Proc [dbo].[CheckIfTablesAreEmtpy]
AS
BEGIN

	exec sp_msforeachtable "IF EXISTS (select * from ?) begin print('? has rows') end else begin print('? NO rows'); end;"

END
--#endregion

--#region EnableOrDisableConstrants
CREATE PROC	[dbo].[EnableOrDisableConstrants]
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
			EXEC sp_msforeachtable "CREATE TABLE ? NOCHECK CONSTRAINT all" 

		END

	IF(@Enable = 1)	
		BEGIN
		-- Enable all constraints for database
			EXEC sp_msforeachtable "CREATE TABLE ? WITH CHECK CHECK CONSTRAINT all"  
		END

		print('SUCCESS')

END
--#endregion

--#region GetAllJobs
CREATE Proc [dbo].[GetAllJobs]
AS
BEGIN
/*
TEST 
EXEC amk_GetAllJobs
*/
	SELECT RS.ScheduleId       AS ScheduleId_JobName
	,  S.[SubscriptionID] 
	,  CASE WHEN S.Description != ''
		    THEN S.Description
		    Else 'N/A' END AS Description
	,  S.EventType        
	,  S.LastStatus    

	FROM               [ReportServer].[dbo].[Subscriptions] AS S 
			INNER JOIN [ReportServer].[dbo].ReportSchedule  AS RS
					ON RS.SubscriptionID = S.SubscriptionID

	  --WHERE S.Description like '%month%'
	  --WHERE S.Description  like '%AMCAD%'
	  --WHERE Description not like '%Quarterly%'
	  --EXEC [MSDB].[DBO].SP_START_JOB    @job_name = '8A76F1F1-A38A-47C9-A5AA-5D0BB0339884' ,@step_name= '8A76F1F1-A38A-47C9-A5AA-5D0BB0339884_step_1'
	  --EXEC ReportServer.dbo.AddEvent @EventType='TimedSubscription', @EventData='8A76F1F1-A38A-47C9-A5AA-5D0BB0339884'
 

END
--#endregion

--#region GetCountOfRows
CREATE Proc [dbo].[GetCountOfRows]
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
END
--#endregion

--#region GetFKTree
CREATE PROC [dbo].[GetFKTree] (
  @TABLE VARCHAR(256) -- USE TWO PART NAME CONVENTION
, @LVL INT=0 -- DO NOT CHANGE
, @PARENTTABLE VARCHAR(256)='' -- DO NOT CHANGE
, @DEBUG bit = 1
)
AS
/*
exec dbo.amk_GetFKTree 'dbo.Trading_Partner'
*/
BEGIN
       SET NOCOUNT ON;
       DECLARE @DBG BIT;
       SET @DBG=@DEBUG;
       IF OBJECT_ID('TEMPDB..#TBL', 'U') IS NULL
             CREATE TABLE  #TBL  ([ID] INT IDENTITY, [TABLENAME] VARCHAR(256), [LVL] INT, [PARENTTABLE] VARCHAR(256));
             --DECLARE @TBL TABLE    (ID INT IDENTITY, TABLENAME VARCHAR(256), LVL INT, PARENTTABLE VARCHAR(256));

       DECLARE @CURS CURSOR;
       IF @LVL = 0
             INSERT INTO #TBL (TABLENAME, LVL, PARENTTABLE)
             SELECT @TABLE, @LVL, NULL;
       ELSE
             INSERT INTO #TBL (TABLENAME, LVL, PARENTTABLE)
             SELECT @TABLE, @LVL, @PARENTTABLE;
       IF @DBG=1    
             PRINT REPLICATE('----', @LVL) + 'LVL ' + CAST(@LVL AS VARCHAR(10)) + ' = ' + @TABLE;
       
       IF EXISTS (SELECT * FROM SYS.FOREIGN_KEYS WHERE REFERENCED_OBJECT_ID = OBJECT_ID(@TABLE))
	   BEGIN
			 SET @PARENTTABLE = @TABLE;
             SET @CURS = CURSOR FOR
             SELECT TABLENAME = OBJECT_SCHEMA_NAME(PARENT_OBJECT_ID)+'.'+OBJECT_NAME(PARENT_OBJECT_ID)
             FROM SYS.FOREIGN_KEYS 
             WHERE REFERENCED_OBJECT_ID = OBJECT_ID(@TABLE)
             AND PARENT_OBJECT_ID <> REFERENCED_OBJECT_ID; -- ADD THIS TO PREVENT SELF-REFERENCING WHICH CAN CREATE A INDEFINITIVE LOOP;

             OPEN @CURS;
             FETCH NEXT FROM @CURS INTO @TABLE;

             WHILE @@FETCH_STATUS = 0
             BEGIN --WHILE
                    SET @LVL = @LVL+1;
                    -- RECURSIVE CALL
                    EXEC DBO.[GetFKTree] @TABLE, @LVL, @PARENTTABLE, @DBG;
                    --SET @RESULT =  ( SELECT * FROM DBO.AMK_GETFKTREE (@TABLE, @LVL, @PARENTTABLE, @DBG))
                    SET @LVL = @LVL-1;
                    FETCH NEXT FROM @CURS INTO @TABLE;
             END --WHILE
             CLOSE @CURS;
             DEALLOCATE @CURS;
	   END
       IF @LVL = 0
             SELECT  ROW_NUMBER() OVER(ORDER BY LVL DESC) [INDEX], * FROM #TBL;
       RETURN;
END
--#endregion

--#region GET ALL REFERRED TABLES

SELECT 
   OBJECT_NAME(f.parent_object_id) TableName,
   COL_NAME(fc.parent_object_id,fc.parent_column_id) ColName,
   OBJECT_NAME (f.referenced_object_id) ReferredTableName
FROM 
   sys.foreign_keys AS f
INNER JOIN 
   sys.foreign_key_columns AS fc 
      ON f.OBJECT_ID = fc.constraint_object_id
INNER JOIN 
   sys.tables t 
      ON t.OBJECT_ID = fc.referenced_object_id
WHERE 
   OBJECT_NAME (f.parent_object_id) = 'Users'

--#endregion GET ALL REFERRED TABLES

--#region TruncateWithReferredTables
CREATE PROC [dbo].[TruncateWithReferredTables]
@tableName varchar(250) = NULL
AS
/*
EXEC amk_TruncateAllTables '[dbo].[Ship_To_Address]'
*/
BEGIN

PRINT 'TABLE_NAME: ' + @tableName

DECLARE @TEMP TABLE ([INDEX] INT, ID INT, TABLENAME VARCHAR(256), LVL INT, PARENTTABLE VARCHAR(256))
DECLARE      @INDEX INT = 1

IF(@tableName IS NULL)
       BEGIN
             EXEC sp_MSforeachtable '
                         [dbo].[TruncateWithReferredTables] ''?''
                    '  
       END
ELSE
       BEGIN

             INSERT INTO @TEMP EXEC GetFKTree @tableName
             DECLARE @SIZE INT = (SELECT COUNT(*) FROM @TEMP) + 1
             PRINT 'SIZE: ' + CAST(@SIZE AS VARCHAR(15))
			 DECLARE @AddConstraintStatment VARCHAR(4000) = ''

             WHILE @INDEX < @SIZE       
             BEGIN
                    PRINT 'INDEX: ' + CAST(@INDEX AS VARCHAR(15))

                    DECLARE @Map Table([TBL_NAME] VARCHAR(250), [FK_NAME] VARCHAR(250), [COLUMN_NAME] VARCHAR(250), [IsFKHolder] BIT, [TBL_ID] INT, [FK_ID] INT, [COL_ID] INT) 
                    DECLARE @CurrentTable VARCHAR(250) = (SELECT TOP 1 TABLENAME FROM @TEMP WHERE [INDEX] = @INDEX)
                                 , @ParentTable VARCHAR(250) = (SELECT TOP 1 PARENTTABLE FROM @TEMP WHERE [INDEX] = @INDEX)
                                 , @DropConstraintStatment VARCHAR(4000) = ''
                                 , @TruncateStatment VARCHAR(4000) = ''

                    IF(@CurrentTable LIKE '%DBO%')
                           SET @CurrentTable = SUBSTRING(@CurrentTable, CHARINDEX('.', @CurrentTable, 0) + 1, LEN(@CurrentTable))

                    PRINT 'CURRENT TABLE: ' + @CurrentTable
                    PRINT 'PARENT TABLE: ' + @ParentTable

                    --GET RELATED FK NAMES
                    INSERT INTO @Map
                    SELECT * FROM GetFkMapping(@CurrentTable) FK

                    --SET SQL STATMENTS
                    SELECT @DropConstraintStatment += 'ALTER TABLE ' + M.TBL_NAME + ' DROP CONSTRAINT ' + M.FK_NAME + '; ' FROM @Map M WHERE M.IsFKHolder = 1 AND M.TBL_NAME LIKE @CurrentTable

                    SELECT @AddConstraintStatment += 'ALTER TABLE  ' +  M.TBL_NAME + ' ADD CONSTRAINT ' + M.FK_NAME + ' FOREIGN KEY(' 
                                                                      + M.COLUMN_NAME + ') ' 
                                                                      + ' REFERENCES '+ (SELECT TOP 1 _M.TBL_NAME FROM @Map _M WHERE _M.FK_ID = M.FK_ID AND _M.IsFKHolder = 0 ) + ' (' 
                                                                      + (SELECT TOP 1 _M.COLUMN_NAME FROM @Map _M WHERE _M.FK_ID = M.FK_ID AND _M.IsFKHolder = 0 ) 
                                                                      + ') ' 
                                                                      FROM @Map M WHERE M.IsFKHolder = 1
                    SET @TruncateStatment = 'TRUNCATE TABLE ' + @CurrentTable

                    
                    -- Empty Map Table Variable--
                    DELETE FROM   @Map

                    --EXECUTE GENERATED STATMENTS
                    
                    PRINT 'EXUCUTING ' + @DropConstraintStatment
                    EXEC sp_sqlexec @DropConstraintStatment

                    PRINT 'EXUCUTING ' + @TruncateStatment
                    EXEC sp_sqlexec @TruncateStatment                                                                          

                   

                    SET @INDEX += 1
             END

			 PRINT 'TRUNCATE COMPLETE'
			 PRINT 'EXUCUTING ' + @AddConstraintStatment
             EXEC sp_sqlexec @AddConstraintStatment
			 PRINT 'RESTORE COMPLETE'

       END
END
--#endregion

--#region IsLastDayOfMonth
CREATE Function [dbo].[IsLastDayOfMonth](
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
--#endregion

--#region FindLastDayOfMonth
CREATE Function [dbo].[FindLastDayOfMonth](
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
--#endregion

--#region FindFirstDayOfMonth
CREATE FUNCTION [dbo].[FindFirstDayOfMonth](
	@Date DATETIME 
)
RETURNS DATETIME
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
--#endregion

--#region SDF_SplitString
CREATE FUNCTION [dbo].[SDF_SplitString]
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
--#endregion

--#region GetFKMapping
CREATE FUNCTION [dbo].[GetFKMapping]
(
@tblName varchar(250)
)
RETURNS @RESULT TABLE ( [TBL_NAME] VARCHAR(250), [FK_NAME] VARCHAR(250), [COLUMN_NAME] VARCHAR(250), [IsFKHolder] BIT, [TBL_ID] INT, [FK_ID] INT, [COL_ID] INT )
/*
SELECT * FROM  dbo.amk_GetFKMapping( 'dbo.Trading_Partner_Contact')
*/
AS
BEGIN

IF(@tblName like '%dbo%')
	SET @tblName = SUBSTRING(@tblName, CHARINDEX('.', @tblName, 0) + 1, LEN(@tblName)) 

INSERT INTO @RESULT
SELECT DISTINCT
		 T.name				[TBL_NAME]
		,F.name				[FK_NAME]
		,C.name				[COLUMN_NAME]
		,CASE 
			WHEN SUB.parent_object_id = T.object_id
			THEN 1
			ELSE 0
		END AS				[IsFKHolder]
		,T.object_id		[TBL_ID]
		,F.object_id		[FK_ID]
		,C.column_id		[COL_ID]
FROM
(
	SELECT _FKC.*
	FROM sys.tables _T
	JOIN sys.foreign_keys _F ON _F.parent_object_id = _T.object_id
	JOIN sys.foreign_key_columns _FKC ON _FKC.constraint_object_id = _F.object_id
	WHERE _T.NAME = @tblName
) SUB

JOIN sys.tables T
	ON SUB.parent_object_id = T.object_id
	OR SUB.referenced_object_id = T.object_id
	

JOIN sys.foreign_keys F
	ON F.object_id = SUB.constraint_object_id


JOIN SYS.columns C
	ON 
		SUB.parent_column_id = C.column_id AND SUB.parent_object_id = C.object_id
 
 
 RETURN 

END
--#endregion

--#region GetColumnDependencies

ALTER PROC [dbo].[GetColumnDependencies]
		@column VARCHAR(128)
AS
/*----------------------- Test Code --------------------------------------
 
	EXEC amk_GetColumnDependencies 'sTran_Group_CD'
	
	EXEC amk_GetColumnDependencies 'sOrder_Type'

*/
BEGIN
	SELECT DISTINCT
	NAME 
--SELECT *
	FROM syscomments C
	INNER JOIN sysobjects O
		ON	C.id = O.id
	WHERE TEXT LIKE '%' + @column  + '%'
	AND NAME <> 'amk_GetColumnDependencies'

END
--#endregion

--#region DropAllTriggers
ALTER PROC [dbo].[DropAllTriggers]
AS
BEGIN
	DECLARE @sql NVARCHAR(MAX) = N'';

	SELECT @sql += 
		N'DROP TRIGGER ' + 
		QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) + N'.' + 
		QUOTENAME(t.name) + N'; ' + NCHAR(13)
	FROM sys.triggers AS t
	WHERE t.is_ms_shipped = 0
	  AND t.parent_class_desc = N'OBJECT_OR_COLUMN';

	PRINT @sql

	EXEC sp_sqlexec @sql             
END
--#endregion

--#region DropAllTriggers
CREATE FUNCTION [dbo].[TableColumns]
(
	@TableName VARCHAR(50)
)
RETURNS @columns TABLE ( [column] nvarchar(2048) ) 
AS
BEGIN
	
	INSERT INTO @columns 
	SELECT COLUMN_NAME 
	FROM INFORMATION_SCHEMA.COLUMNS 
	WHERE TABLE_NAME = @TableName--'TRADE'
	
	RETURN           
END
--#endregion

--#region GetTimeZoneOffset

ALTER FUNCTION [dbo].[GetTimeZoneOffset]
(
	@timezone VARCHAR(6)
)
	RETURNS NUMERIC(4,2)
AS
BEGIN
	DECLARE @offset NUMERIC(4,2) = 0

	SET @offset = 
	 CASE
	  WHEN @timezone ='ACDT'	THEN  10.3
 
	  WHEN @timezone ='ACST'	THEN  9.3
 
	  WHEN @timezone ='ACT'		THEN  -5
 
	  --WHEN @timezone ='ACT'	THEN  -6.3
 
	  WHEN @timezone ='ACWST'	THEN  8.45
 
	  WHEN @timezone ='ADT'		THEN  -3
 
	  WHEN @timezone ='AEDT'	THEN  11
 
	  WHEN @timezone ='AEST'	THEN  10
 
	  WHEN @timezone ='AFT'		THEN  4.3
 
	  WHEN @timezone ='AKDT'	THEN  -8
 
	  WHEN @timezone ='AKST'	THEN  -9
 
	  WHEN @timezone ='AMST'	THEN  -3
 
	  WHEN @timezone ='AMT'		THEN  4
 
	  WHEN @timezone ='ART'		THEN  -3
 
	  WHEN @timezone ='AST'		THEN  3
 
	  --WHEN @timezone ='AST'		THEN  -4

	  WHEN @timezone ='AWST'	THEN  8

	  WHEN @timezone ='AZOST'	THEN  0

	  WHEN @timezone ='AZOT'	THEN  -1

	  WHEN @timezone ='AZT'		THEN  4

	  WHEN @timezone ='BRAZIL'	THEN  -4
 
	  WHEN @timezone ='BDT'		THEN  8
 
	  WHEN @timezone ='BIOT'	THEN  6
 
	  WHEN @timezone ='BIT'		THEN  -12
 
	  WHEN @timezone ='BOT'		THEN  -4
 
	  WHEN @timezone ='BRST'	THEN  -2

	  WHEN @timezone ='BRT'		THEN  -3
 
	  WHEN @timezone ='BST'		THEN  6
 
	  --WHEN @timezone ='BST'		THEN  1
 
	  WHEN @timezone ='BTT'		THEN  6

	  WHEN @timezone ='CAT'		THEN  2

	  WHEN @timezone ='CCT'		THEN  6.3
 
	  WHEN @timezone ='CDT'		THEN  -5
 
	  --WHEN @timezone ='CDT'		THEN  -4
 
	  WHEN @timezone ='CEST'	THEN  2

	  WHEN @timezone ='CET'		THEN  1

	  WHEN @timezone ='CHADT'	THEN  13.45
 
	  WHEN @timezone ='CHAST'	THEN  12.45
 
	  WHEN @timezone ='CHOST'	THEN  9
 
	  WHEN @timezone ='CHOT'	THEN  8
 
	  WHEN @timezone ='CHST'	THEN  10

	  WHEN @timezone ='CHUT'	THEN  10

	  WHEN @timezone ='CIST'	THEN  -8

	  WHEN @timezone ='CIT'		THEN  8

	  WHEN @timezone ='CKT'		THEN  -10

	  WHEN @timezone ='CLST'	THEN  -3
 
	  WHEN @timezone ='CLT'		THEN  -4

	  WHEN @timezone ='COST'	THEN  -4

	  WHEN @timezone ='COT'		THEN  -5

	  WHEN @timezone ='CST'		THEN  -6

	  --WHEN @timezone ='CST'		THEN  8

	  --WHEN @timezone ='CST'		THEN  -5
 
	  WHEN @timezone ='CT'		THEN  8
 
	  WHEN @timezone ='CWST'	THEN  8.45

	  WHEN @timezone ='CXT'		THEN  7
 
	  WHEN @timezone ='DAVT'	THEN  7
 
	  WHEN @timezone ='DDUT'	THEN  10
 
	  WHEN @timezone ='DFT'		THEN  1
 
	  WHEN @timezone ='EASST'	THEN  -5

	  WHEN @timezone ='EAST'	THEN  -6

	  WHEN @timezone ='EAT'		THEN  3

	  WHEN @timezone ='ECT'		THEN  -4

	  --WHEN @timezone ='ECT'		THEN  -5
 
	  WHEN @timezone ='EDT'		THEN  -4
 
	  WHEN @timezone ='EEST'	THEN  3
 
	  WHEN @timezone ='EET'		THEN  2
 
	  WHEN @timezone ='EGST'	THEN  0
 
	  WHEN @timezone ='EGT'		THEN  -1
 
	  WHEN @timezone ='EIT'		THEN  9
 
	  WHEN @timezone ='EST'		THEN  -5
 
	  WHEN @timezone ='FET'		THEN  3
 
	  WHEN @timezone ='FJT'		THEN  12
 
	  WHEN @timezone ='FKST'	THEN  -3
 
	  WHEN @timezone ='FKT'		THEN  -4
 
	  WHEN @timezone ='FNT'		THEN  -2
 
	  WHEN @timezone ='GALT'	THEN  -6
 
	  WHEN @timezone ='GAMT'	THEN  -9
 
	  WHEN @timezone ='GET'		THEN  4
 
	  WHEN @timezone ='GFT'		THEN  -3
 
	  WHEN @timezone ='GILT'	THEN  12
 
	  WHEN @timezone ='GIT'		THEN  -9
 
	  WHEN @timezone ='GMT'		THEN  0
 
	  WHEN @timezone ='GST'		THEN  -2

	  WHEN @timezone ='GST'		THEN  4
 
	  WHEN @timezone ='GYT'		THEN  -4
 
	  WHEN @timezone ='HAEC'	THEN  2
 
	  WHEN @timezone ='HDT'		THEN  -9
 
	  WHEN @timezone ='HKT'		THEN  8
 
	  WHEN @timezone ='HMT'		THEN  5
 
	  WHEN @timezone ='HOVST'	THEN  8
 
	  WHEN @timezone ='HST'		THEN  -10
 
	  WHEN @timezone ='ICT'		THEN  7
 
	  WHEN @timezone ='IDT'		THEN  3
 
	  WHEN @timezone ='IOT'		THEN  3
 
	  WHEN @timezone ='IRDT'	THEN  4.3
 
	  WHEN @timezone ='IRKT'	THEN  8
 
	  WHEN @timezone ='IRST'	THEN  3.3
 
	  WHEN @timezone ='IST'		THEN  5.3
 
	  --WHEN @timezone ='IST'		THEN  1
 
	  --WHEN @timezone ='IST'		THEN  2
 
	  WHEN @timezone ='JST'		THEN  9
 
	  WHEN @timezone ='KGT'		THEN  6
 
	  WHEN @timezone ='KOST'	THEN  11

	  WHEN @timezone ='KRAT'	THEN  7

	  WHEN @timezone ='KST'		THEN  9

	  WHEN @timezone ='LHST'	THEN  10.3

	  --WHEN @timezone ='LHST'	THEN  11
 
	  WHEN @timezone ='LINT'	THEN  14

	  WHEN @timezone ='MART'	THEN  -9.3

	  WHEN @timezone ='MAWT'	THEN  5

	  WHEN @timezone ='MDT'		THEN  -6
 
	  WHEN @timezone ='MEST'	THEN  2

	  WHEN @timezone ='MET'		THEN  1
 
	  WHEN @timezone ='MHT'		THEN  12
 
	  WHEN @timezone ='MIST'	THEN  11
 
	  WHEN @timezone ='MIT'		THEN  -9.3
 
	  WHEN @timezone ='MMT'		THEN  6.3
 
	  WHEN @timezone ='MSK'		THEN  3
 
	  WHEN @timezone ='MST'		THEN  8
 
	  --WHEN @timezone ='MST'		THEN  -7
 
	  WHEN @timezone ='MUT'		THEN  4
 
	  WHEN @timezone ='MVT'		THEN  5
 
	  WHEN @timezone ='MYT'		THEN  8
 
	  WHEN @timezone ='NCT'		THEN  11

	  WHEN @timezone ='NDT'		THEN  -2.3

	  WHEN @timezone ='NFT'		THEN  11
 
	  WHEN @timezone ='NPT'		THEN  5.45
 
	  WHEN @timezone ='NST'		THEN  -3.3
 
	  WHEN @timezone ='NT'		THEN  -3.3
 
	  WHEN @timezone ='NUT'		THEN  -11
 
	  WHEN @timezone ='NZDT'	THEN  13
 
	  WHEN @timezone ='NZST'	THEN  12
 
	  WHEN @timezone ='OMST'	THEN  6

	  WHEN @timezone ='ORAT'	THEN  5
 
	  WHEN @timezone ='PDT'		THEN  -7
 
	  WHEN @timezone ='PET'		THEN  -5
 
	  WHEN @timezone ='PETT'	THEN  12
 
	  WHEN @timezone ='PGT'		THEN  10
 
	  WHEN @timezone ='PHOT'	THEN  13

	  WHEN @timezone ='PHT'		THEN  8

	  WHEN @timezone ='PKT'		THEN  5

	  WHEN @timezone ='PMDT'	THEN  -2
 
	  WHEN @timezone ='PMST'	THEN  -3
 
	  WHEN @timezone ='PONT'	THEN  11
 
	  WHEN @timezone ='PST'		THEN  -8
 
	  WHEN @timezone ='PYST'	THEN  -3
 
	  WHEN @timezone ='PYT'		THEN  -4
 
	  WHEN @timezone ='RET'		THEN  4
 
	  WHEN @timezone ='ROTT'	THEN  -3
 
	  WHEN @timezone ='SAKT'	THEN  11

	  WHEN @timezone ='SAMT'	THEN  4
 
	  WHEN @timezone ='SAST'	THEN  2
 
	  WHEN @timezone ='SBT'		THEN  11

	  WHEN @timezone ='SCT'		THEN  4
 
	  WHEN @timezone ='SDT'		THEN  -10
 
	  WHEN @timezone ='SGT'		THEN  8
 
	  WHEN @timezone ='SLST'	THEN  5.3
 
	  WHEN @timezone ='SRET'	THEN  11
 
	  WHEN @timezone ='SRT'		THEN  -3
 
	  WHEN @timezone ='SST'		THEN  -11
 
	  --WHEN @timezone ='SST'		THEN  8
 
	  WHEN @timezone ='SYOT'	THEN  3
 
	  WHEN @timezone ='TAHT'	THEN  -10

	  WHEN @timezone ='TFT'		THEN  5
 
	  WHEN @timezone ='THA'		THEN  7

	  WHEN @timezone ='TJT'		THEN  5

	  WHEN @timezone ='TKT'		THEN  13
 
	  WHEN @timezone ='TLT'		THEN  9

	  WHEN @timezone ='TMT'		THEN  5

	  WHEN @timezone ='TOT'		THEN  13
 
	  WHEN @timezone ='TRT'		THEN  3
 
	  WHEN @timezone ='TVT'		THEN  12
 
	  WHEN @timezone ='ULAST'	THEN  9

	  WHEN @timezone ='ULAT'	THEN  8
 
	  WHEN @timezone ='USZ1'	THEN  2
 
	  WHEN @timezone ='UTC'		THEN  0
 
	  WHEN @timezone ='UYST'	THEN  -2

	  WHEN @timezone ='UYT'		THEN  -3

	  WHEN @timezone ='UZT'		THEN  5

	  WHEN @timezone ='VET'		THEN  -4

	  WHEN @timezone ='VLAT'	THEN  10

	  WHEN @timezone ='VOST'	THEN  6

	  WHEN @timezone ='VUT'		THEN  11
 
	  WHEN @timezone ='WAKT'	THEN  12
 
	  WHEN @timezone ='WAST'	THEN  2
 
	  WHEN @timezone ='WAT'		THEN  1
 
	  WHEN @timezone ='WEST'	THEN  1
 
	  WHEN @timezone ='WET'		THEN  0

	  WHEN @timezone ='WIT'		THEN  7

	  WHEN @timezone ='WST'		THEN  8
 
	  WHEN @timezone ='YAKT'	THEN  9

	  WHEN @timezone ='YEKT'	THEN  5
	END

	RETURN @offset
END

--#endregion

--#region GetColumnInfo

SELECT col.* from sys.objects obj 
inner join sys.columns col 
on obj.object_Id = col.object_Id 
and obj.Name = @tableName

--#endregion GetColumnInfo

--#region GetEditsDates

ALTER PROC [dbo].[GetEditsDates]

AS

BEGIN
		SELECT * 
		FROM sys.objects
		WHERE type = 'P'
		AND [name] IN 
		(
				'insert'
				,'procs'
				,'here'
		)

END


--#endregion GetEditsDates

--#region GetColumnGrowth

CREATE PROC GetColumnGrowth
	@tableName varchar(100),
	@tagetColumn varchar(100),
	@dateColumn varchar(100)
AS
/*
	@tableName varchar(100) = 'ORDER_HDR',
	@tagetColumn varchar(100) = 'ITRADING_PARTNER_ID',
	@dateColumn varchar(100) = 'dtLastUpdate_DT'


	SELECT    (1 - GROWTH.ITRADING_PARTNER_ID * 1.0 / TBL.ITRADING_PARTNER_ID) monthly_change
			, GROWTH.ITRADING_PARTNER_ID[1ST ID] 
			, TBL.ITRADING_PARTNER_ID [2ND ID]
			, TBL.*
	FROM ORDER_HDR TBL 
	OUTER APPLY (
		SELECT TOP 1 TBL2.*
		FROM ORDER_HDR TBL2
		WHERE TBL2.dtLastUpdate_DT < TBL.dtLastUpdate_DT
		ORDER BY dtLastUpdate_DT DESC
	) GROWTH
	ORDER BY ITRADING_PARTNER_ID, 1
*/
BEGIN

	
	DECLARE @tableName varchar(100) = 'ORDER_HDR',
			@tagetColumn varchar(100) = 'ITRADING_PARTNER_ID',
			@dateColumn varchar(100) = 'dtLastUpdate_DT'
	DECLARE @STATEMENT varchar(MAX) = '
				SELECT    (1 - GROWTH.' + @tagetColumn + ' * 1.0 / TBL.' + @tagetColumn + ') monthly_change
						, GROWTH.' + @tagetColumn + '[1ST ID] 
						, TBL.' + @tagetColumn + ' [2ND ID]
						, TBL.*
				FROM ' + @tableName + ' TBL 
				OUTER APPLY (
					SELECT TOP 1 TBL2.*
					FROM ' + @tableName + ' TBL2
					WHERE TBL2.' + @dateColumn + ' < TBL.' + @dateColumn + '
					ORDER BY ' + @dateColumn + ' DESC
				 ) GROWTH
				ORDER BY ' + @tagetColumn + ', 1'

	EXEC sp_sqlexec @STATEMENT

END

--#endregion GetColumnGrowth

--#region Global_ExecuteSQL

CREATE PROCEDURE dbo.Global_ExecuteSQL
(
    @sql NVARCHAR(MAX),
    @dbname NVARCHAR(MAX) = NULL
)
AS BEGIN
    /*
        PURPOSE
            Runs SQL statements in this database or another database.
            You can use parameters.

        TEST
            EXEC dbo.Infrastructure_ExecuteSQL 'SELECT @@version, db_name();', 'master';

    */

    /* For testing.
    DECLARE @sql NVARCHAR(MAX) = 'SELECT @@version, db_name();';
    DECLARE @dbname NVARCHAR(MAX) = 'msdb';
    --*/

    DECLARE @proc NVARCHAR(MAX) = 'sys.sp_executeSQL';
    IF (@dbname IS NOT NULL) SET @proc = @dbname + '.' + @proc;

    EXEC @proc @sql;

END;

--#endregion Global_ExecuteSQL

--#region DoesColumnExists

CREATE FUNCTION dbo.DoesColumnExists
(
    @COLUMN NVARCHAR(MAX),
    @TABLE NVARCHAR(MAX)
)
	RETURNS BIT
AS
BEGIN
   DECLARE @RESULT BIT = 0
   IF COL_LENGTH('DBO.' + @TABLE, @COLUMN) IS NOT NULL
		SET @RESULT = 1

	RETURN @RESULT
END

--#endregion Global_ExecuteSQL

--#region TRUNCATE / FK MAPPING QUERY

DECLARE @tblName Varchar(100) = 'dbo.Online_Request_Hdr'

IF (@tblName like '%dbo%')
	SET @tblName = SUBSTRING(@tblName, CHARINDEX('.', @tblName, 0) + 1, LEN(@tblName))

SELECT DISTINCT ROW_NUMBER() OVER(ORDER BY T.object_id)                    [ROW]
,               T.name                                                     [TBL_NAME]
,               F.name                                                     [FK_NAME]
,               FKC.name                                                   [FK_COLUMN_NAME]
,               PKC.name                                                   [PK_COLUMN_NAME]
,               CASE WHEN SUB.parent_object_id = T.object_id THEN 1
                                                             ELSE 0 END AS [IsFKHolder]
,               T.object_id                                                [TBL_ID]
,               F.object_id                                                [FK_ID]
,               FKC.column_id                                              [FK_COL_ID]
,               PKC.column_id                                              [PK_COL_ID]

	INTO #RESULT

FROM (
	SELECT _FKC.*
	FROM sys.tables              _T  
	JOIN sys.foreign_keys        _F   ON _F.parent_object_id = _T.object_id OR _F.referenced_object_id = _T.object_id
	JOIN sys.foreign_key_columns _FKC ON _FKC.constraint_object_id = _F.object_id
	WHERE _T.NAME like	@tblName
)                     SUB

JOIN sys.tables			T   ON SUB.parent_object_id = T.object_id OR SUB.referenced_object_id = T.object_id

JOIN sys.foreign_keys	F   ON F.object_id = SUB.constraint_object_id

JOIN SYS.columns		FKC   ON SUB.parent_column_id = FKC.column_id AND SUB.parent_object_id = FKC.object_id

JOIN SYS.columns		PKC   ON SUB.referenced_column_id = PKC.column_id AND SUB.referenced_object_id = PKC.object_id


SELECT * FROM #RESULT


	SELECT 'GENERATING CONSTRAINT STATEMENTS'

--#region GENERATE STATEMENTS

	DECLARE   @mapMax INT = (SELECT COUNT(*) FROM #RESULT)
			, @mapIndex INT = 1
						
	WHILE @mapIndex <= @mapMax
	BEGIN  

		SELECT 'ALTER TABLE '			+ M.TBL_NAME
										+ ' DROP CONSTRAINT ' + M.FK_NAME + '; ' 
										FROM #RESULT M
										WHERE M.IsFKHolder = 1 
										AND @mapIndex = M.ROW

		SELECT 'ALTER TABLE  '			+  M.TBL_NAME 
										+ ' ADD CONSTRAINT ' + M.FK_NAME 
										+ ' FOREIGN KEY(' + M.FK_COLUMN_NAME + ') ' 
										+ ' REFERENCES ' 
										+ (SELECT TOP 1 _M.TBL_NAME FROM #RESULT _M WHERE _M.FK_ID = M.FK_ID AND _M.IsFKHolder = 0 ) 
										+ ' (' 
										+ (SELECT TOP 1 _M.PK_COLUMN_NAME FROM #RESULT _M WHERE _M.FK_ID = M.FK_ID AND _M.IsFKHolder = 1 ) 
										+ '); ' 
										FROM #RESULT M
										WHERE M.IsFKHolder = 1 
										AND @mapIndex = M.ROW
		SET @mapIndex += 1		
	END 


DROP TABLE #RESULT


--#endregion TRUNCATE / FK MAPPING QUERY

--#endregion REMIGRATION

--#region SEARCH FOR OBJECTS WITH TEXT
DECLARE @TextToSearch VARCHAR(MAX) = 'WebSpotPrices'

SELECT *
FROM sys.sql_modules
WHERE definition LIKE '%' + @TextToSearch + '%'

--#endregion SEARCH FOR OBJECTS WITH TEXT

--#region GET ROW COUNT OF ANY TABLE

DECLARE @TABLENAME VARCHAR(MAX) = 'API_Callbacks'
EXEC ('SELECT COUNT(ROW) FROM (SELECT ROW_NUMBER() OVER (PARTITION BY ID ORDER BY ID) [ROW], * FROM ' + @TABLENAME + ') Q')


--#endregion GET ROW COUNT OF ANY TABLE

--#region PARSE JSON

CREATE FUNCTION dbo.parseJSON( @JSON NVARCHAR(MAX))
	RETURNS @hierarchy TABLE
	  (
	   element_id INT IDENTITY(1, 1) NOT NULL, /* internal surrogate primary key gives the order of parsing and the list order */
	   sequenceNo [int] NULL, /* the place in the sequence for the element */
	   parent_ID INT,/* if the element has a parent then it is in this column. The document is the ultimate parent, so you can get the structure from recursing from the document */
	   Object_ID INT,/* each list or object has an object id. This ties all elements to a parent. Lists are treated as objects here */
	   NAME NVARCHAR(2000),/* the name of the object */
	   StringValue NVARCHAR(MAX) NOT NULL,/*the string representation of the value of the element. */
	   ValueType VARCHAR(10) NOT null /* the declared type of the value represented as a string in StringValue*/
	  )
	AS
	BEGIN
	  DECLARE
	    @FirstObject INT, --the index of the first open bracket found in the JSON string
	    @OpenDelimiter INT,--the index of the next open bracket found in the JSON string
	    @NextOpenDelimiter INT,--the index of subsequent open bracket found in the JSON string
	    @NextCloseDelimiter INT,--the index of subsequent close bracket found in the JSON string
	    @Type NVARCHAR(10),--whether it denotes an object or an array
	    @NextCloseDelimiterChar CHAR(1),--either a '}' or a ']'
	    @Contents NVARCHAR(MAX), --the unparsed contents of the bracketed expression
	    @Start INT, --index of the start of the token that you are parsing
	    @end INT,--index of the end of the token that you are parsing
	    @param INT,--the parameter at the end of the next Object/Array token
	    @EndOfName INT,--the index of the start of the parameter at end of Object/Array token
	    @token NVARCHAR(200),--either a string or object
	    @value NVARCHAR(MAX), -- the value as a string
	    @SequenceNo int, -- the sequence number within a list
	    @name NVARCHAR(200), --the name as a string
	    @parent_ID INT,--the next parent ID to allocate
	    @lenJSON INT,--the current length of the JSON String
	    @characters NCHAR(36),--used to convert hex to decimal
	    @result BIGINT,--the value of the hex symbol being parsed
	    @index SMALLINT,--used for parsing the hex value
	    @Escape INT --the index of the next escape character
	    
	  DECLARE @Strings TABLE /* in this temporary table we keep all strings, even the names of the elements, since they are 'escaped' in a different way, and may contain, unescaped, brackets denoting objects or lists. These are replaced in the JSON string by tokens representing the string */
	    (
	     String_ID INT IDENTITY(1, 1),
	     StringValue NVARCHAR(MAX)
	    )
	  SELECT--initialise the characters to convert hex to ascii
	    @characters='0123456789abcdefghijklmnopqrstuvwxyz',
	    @SequenceNo=0, --set the sequence no. to something sensible.
	  /* firstly we process all strings. This is done because [{} and ] aren't escaped in strings, which complicates an iterative parse. */
	    @parent_ID=0;
	  WHILE 1=1 --forever until there is nothing more to do
	    BEGIN
	      SELECT
	        @start=PATINDEX('%[^a-zA-Z]["]%', @json collate SQL_Latin1_General_CP850_Bin);--next delimited string
	      IF @start=0 BREAK --no more so drop through the WHILE loop
	      IF SUBSTRING(@json, @start+1, 1)='"' 
	        BEGIN --Delimited Name
	          SET @start=@Start+1;
	          SET @end=PATINDEX('%[^\]["]%', RIGHT(@json, LEN(@json+'|')-@start) collate SQL_Latin1_General_CP850_Bin);
	        END
	      IF @end=0 --no end delimiter to last string
	        BREAK --no more
	      SELECT @token=SUBSTRING(@json, @start+1, @end-1)
	      --now put in the escaped control characters
	      SELECT @token=REPLACE(@token, FROMString, TOString)
	      FROM
	        (SELECT
	          '\"' AS FromString, '"' AS ToString
	         UNION ALL SELECT '\\', '\'
	         UNION ALL SELECT '\/', '/'
	         UNION ALL SELECT '\b', CHAR(08)
	         UNION ALL SELECT '\f', CHAR(12)
	         UNION ALL SELECT '\n', CHAR(10)
	         UNION ALL SELECT '\r', CHAR(13)
	         UNION ALL SELECT '\t', CHAR(09)
	        ) substitutions
	      SELECT @result=0, @escape=1
	  --Begin to take out any hex escape codes
	      WHILE @escape>0
	        BEGIN
	          SELECT @index=0,
	          --find the next hex escape sequence
	          @escape=PATINDEX('%\x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%', @token collate SQL_Latin1_General_CP850_Bin)
	          IF @escape>0 --if there is one
	            BEGIN
	              WHILE @index<4 --there are always four digits to a \x sequence   
	                BEGIN
	                  SELECT --determine its value
	                    @result=@result+POWER(16, @index)
	                    *(CHARINDEX(SUBSTRING(@token, @escape+2+3-@index, 1),
	                                @characters)-1), @index=@index+1 ;
	         
	                END
	                -- and replace the hex sequence by its unicode value
	              SELECT @token=STUFF(@token, @escape, 6, NCHAR(@result))
	            END
	        END
	      --now store the string away 
	      INSERT INTO @Strings (StringValue) SELECT @token
	      -- and replace the string with a token
	      SELECT @JSON=STUFF(@json, @start, @end+1,
	                    '@string'+CONVERT(NVARCHAR(5), @@identity))
	    END
	  -- all strings are now removed. Now we find the first leaf.  
	  WHILE 1=1  --forever until there is nothing more to do
	  BEGIN
	 
	  SELECT @parent_ID=@parent_ID+1
	  --find the first object or list by looking for the open bracket
	  SELECT @FirstObject=PATINDEX('%[{[[]%', @json collate SQL_Latin1_General_CP850_Bin)--object or array
	  IF @FirstObject = 0 BREAK
	  IF (SUBSTRING(@json, @FirstObject, 1)='{') 
	    SELECT @NextCloseDelimiterChar='}', @type='object'
	  ELSE 
	    SELECT @NextCloseDelimiterChar=']', @type='array'
	  SELECT @OpenDelimiter=@firstObject
	  WHILE 1=1 --find the innermost object or list...
	    BEGIN
	      SELECT
	        @lenJSON=LEN(@JSON+'|')-1
	  --find the matching close-delimiter proceeding after the open-delimiter
	      SELECT
	        @NextCloseDelimiter=CHARINDEX(@NextCloseDelimiterChar, @json,
	                                      @OpenDelimiter+1)
	  --is there an intervening open-delimiter of either type
	      SELECT @NextOpenDelimiter=PATINDEX('%[{[[]%',
	             RIGHT(@json, @lenJSON-@OpenDelimiter)collate SQL_Latin1_General_CP850_Bin)--object
	      IF @NextOpenDelimiter=0 
	        BREAK
	      SELECT @NextOpenDelimiter=@NextOpenDelimiter+@OpenDelimiter
	      IF @NextCloseDelimiter<@NextOpenDelimiter 
	        BREAK
	      IF SUBSTRING(@json, @NextOpenDelimiter, 1)='{' 
	        SELECT @NextCloseDelimiterChar='}', @type='object'
	      ELSE 
	        SELECT @NextCloseDelimiterChar=']', @type='array'
	      SELECT @OpenDelimiter=@NextOpenDelimiter
	    END
	  ---and parse out the list or name/value pairs
	  SELECT
	    @contents=SUBSTRING(@json, @OpenDelimiter+1,
	                        @NextCloseDelimiter-@OpenDelimiter-1)
	  SELECT
	    @JSON=STUFF(@json, @OpenDelimiter,
	                @NextCloseDelimiter-@OpenDelimiter+1,
	                '@'+@type+CONVERT(NVARCHAR(5), @parent_ID))
	  WHILE (PATINDEX('%[A-Za-z0-9@+.e]%', @contents collate SQL_Latin1_General_CP850_Bin))<>0 
	    BEGIN
	      IF @Type='Object' --it will be a 0-n list containing a string followed by a string, number,boolean, or null
	        BEGIN
	          SELECT
	            @SequenceNo=0,@end=CHARINDEX(':', ' '+@contents)--if there is anything, it will be a string-based name.
	          SELECT  @start=PATINDEX('%[^A-Za-z@][@]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)--AAAAAAAA
	          SELECT @token=SUBSTRING(' '+@contents, @start+1, @End-@Start-1),
	            @endofname=PATINDEX('%[0-9]%', @token collate SQL_Latin1_General_CP850_Bin),
	            @param=RIGHT(@token, LEN(@token)-@endofname+1)
	          SELECT
	            @token=LEFT(@token, @endofname-1),
	            @Contents=RIGHT(' '+@contents, LEN(' '+@contents+'|')-@end-1)
	          SELECT  @name=stringvalue FROM @strings
	            WHERE string_id=@param --fetch the name
	        END
	      ELSE 
	        SELECT @Name=null,@SequenceNo=@SequenceNo+1 
	      SELECT
	        @end=CHARINDEX(',', @contents)-- a string-token, object-token, list-token, number,boolean, or null
                IF @end=0
	        --HR Engineering notation bugfix start
	          IF ISNUMERIC(@contents) = 1
		    SELECT @end = LEN(@contents) + 1
	          Else
	        --HR Engineering notation bugfix end 
		  SELECT  @end=PATINDEX('%[A-Za-z0-9@+.e][^A-Za-z0-9@+.e]%', @contents+' ' collate SQL_Latin1_General_CP850_Bin) + 1
	       SELECT
	        @start=PATINDEX('%[^A-Za-z0-9@+.e][A-Za-z0-9@+.e]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)
	      --select @start,@end, LEN(@contents+'|'), @contents  
	      SELECT
	        @Value=RTRIM(SUBSTRING(@contents, @start, @End-@Start)),
	        @Contents=RIGHT(@contents+' ', LEN(@contents+'|')-@end)
	      IF SUBSTRING(@value, 1, 7)='@object' 
	        INSERT INTO @hierarchy
	          (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	          SELECT @name, @SequenceNo, @parent_ID, SUBSTRING(@value, 8, 5),
	            SUBSTRING(@value, 8, 5), 'object' 
	      ELSE 
	        IF SUBSTRING(@value, 1, 6)='@array' 
	          INSERT INTO @hierarchy
	            (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	            SELECT @name, @SequenceNo, @parent_ID, SUBSTRING(@value, 7, 5),
	              SUBSTRING(@value, 7, 5), 'array' 
	        ELSE 
	          IF SUBSTRING(@value, 1, 7)='@string' 
	            INSERT INTO @hierarchy
	              (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	              SELECT @name, @SequenceNo, @parent_ID, stringvalue, 'string'
	              FROM @strings
	              WHERE string_id=SUBSTRING(@value, 8, 5)
	          ELSE 
	            IF @value IN ('true', 'false') 
	              INSERT INTO @hierarchy
	                (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                SELECT @name, @SequenceNo, @parent_ID, @value, 'boolean'
	            ELSE
	              IF @value='null' 
	                INSERT INTO @hierarchy
	                  (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                  SELECT @name, @SequenceNo, @parent_ID, @value, 'null'
	              ELSE
	                IF PATINDEX('%[^0-9]%', @value collate SQL_Latin1_General_CP850_Bin)>0 
	                  INSERT INTO @hierarchy
	                    (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                    SELECT @name, @SequenceNo, @parent_ID, @value, 'real'
	                ELSE
	                  INSERT INTO @hierarchy
	                    (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                    SELECT @name, @SequenceNo, @parent_ID, @value, 'int'
	      if @Contents=' ' Select @SequenceNo=0
	    END
	  END
	INSERT INTO @hierarchy (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	  SELECT '-',1, NULL, '', @parent_id-1, @type
	--
	   RETURN
	END
GO

--#endregion PARSE JSON

--#region TABLE TO C# CLASS

declare @TableName sysname = 'TableName'
declare @Result varchar(max) = 'public class ' + @TableName + '
{'

select @Result = @Result + '
    public ' + ColumnType + NullableSign + ' ' + ColumnName + ' { get; set; }
'
from
(
    select 
        replace(col.name, ' ', '_') ColumnName,
        column_id ColumnId,
        case typ.name 
            when 'bigint' then 'long'
            when 'binary' then 'byte[]'
            when 'bit' then 'bool'
            when 'char' then 'string'
            when 'date' then 'DateTime'
            when 'datetime' then 'DateTime'
            when 'datetime2' then 'DateTime'
            when 'datetimeoffset' then 'DateTimeOffset'
            when 'decimal' then 'decimal'
            when 'float' then 'double'
            when 'image' then 'byte[]'
            when 'int' then 'int'
            when 'money' then 'decimal'
            when 'nchar' then 'string'
            when 'ntext' then 'string'
            when 'numeric' then 'decimal'
            when 'nvarchar' then 'string'
            when 'real' then 'float'
            when 'smalldatetime' then 'DateTime'
            when 'smallint' then 'short'
            when 'smallmoney' then 'decimal'
            when 'text' then 'string'
            when 'time' then 'TimeSpan'
            when 'timestamp' then 'long'
            when 'tinyint' then 'byte'
            when 'uniqueidentifier' then 'Guid'
            when 'varbinary' then 'byte[]'
            when 'varchar' then 'string'
            else 'UNKNOWN_' + typ.name
        end ColumnType,
        case 
            when col.is_nullable = 1 and typ.name in ('bigint', 'bit', 'date', 'datetime', 'datetime2', 'datetimeoffset', 'decimal', 'float', 'int', 'money', 'numeric', 'real', 'smalldatetime', 'smallint', 'smallmoney', 'time', 'tinyint', 'uniqueidentifier') 
            then '?' 
            else '' 
        end NullableSign
    from sys.columns col
        join sys.types typ on
            col.system_type_id = typ.system_type_id AND col.user_type_id = typ.user_type_id
    where object_id = object_id(@TableName)
) t
order by ColumnId

set @Result = @Result  + '
}'

print @Result

--#endregion TABLE TO C# CLASS

--#region Get Tables By Name

SELECT * FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME LIKE '%temp%'

--#endregion Get Tables By Name