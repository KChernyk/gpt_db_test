IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ErrorLog')
BEGIN
    CREATE TABLE [ErrorLog](
        [ErrorID] INT IDENTITY(1,1) PRIMARY KEY,
        [ErrorNumber] INT,
        [ErrorSeverity] INT,
        [ErrorMessage] VARCHAR(255),
        [CustomerID] INT,
        [Period] VARCHAR(8),
        [CreatedAt] DATETIME DEFAULT GETDATE()
    );
END;

GO

CREATE PROCEDURE  sp_CalculateCustomerRevenue
    @FromYear INT = NULL,
    @ToYear INT = NULL,
    @Period VARCHAR(10) = 'Year',
    @CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Determine the FromYear and ToYear if they're not provided
        IF @FromYear IS NULL
            SET @FromYear = (SELECT MIN(YEAR([Invoice Date Key])) FROM [Fact].[Sale]);
        
        IF @ToYear IS NULL
            SET @ToYear = (SELECT MAX(YEAR([Invoice Date Key])) FROM [Fact].[Sale]);

		DECLARE @CustomerName NVARCHAR(200)

		SELECT @CustomerName =  IIF(@CustomerID IS NULL, 'All', Customer)
		FROM Dimension.Customer
		WHERE @CustomerID IS NULL OR [Customer Key] = @CustomerID

        DECLARE @TableName NVARCHAR(255) = CAST (@CustomerID AS NVARCHAR(50)) + '_' +
                                           + @CustomerName + '_' + CONVERT(NVARCHAR(4), @FromYear)
                                           + (CASE WHEN @FromYear <> @ToYear THEN '_' + CONVERT(NVARCHAR(4), @ToYear) ELSE '' END) 
                                           + '_' + LEFT(@Period, 1);  
        -- Drop the result table if it exists and then recreate it
        DECLARE @SQL NVARCHAR(MAX) = 'IF OBJECT_ID(''' + @TableName + ''', ''U'') IS NOT NULL DROP TABLE [' + @TableName + ']';
        EXEC sp_executesql @SQL;

        -- Now create the new table
        SET @SQL = 'CREATE TABLE [' + @TableName + ']' +' (
            [CustomerID] INT, 
            [CustomerName] NVARCHAR(50), 
            [Period] VARCHAR(8),
            [Revenue] NUMERIC(19,2)
        );';
        EXEC sp_executesql @SQL;

        DECLARE @DynamicSQL NVARCHAR(MAX);
        DECLARE @ParamDefinition NVARCHAR(1000);

		DECLARE @schema NVARCHAR(20)

        SELECT @schema = s.name
        FROM sys.tables o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE o.name = @TableName;

        SET @ParamDefinition = '@Period NVARCHAR(10), @FromYear INT, @ToYear INT, @CustomerID INT';

        SET @DynamicSQL = N'INSERT INTO ['+ @schema + '].['  + @TableName + ']' + ' (CustomerID, CustomerName, Period, Revenue) ' +
	    ' SELECT s.[Customer Key],
				Customer,
				CASE WHEN @Period IN (''Month'', ''M'') THEN FORMAT([Invoice Date Key], ''MMM yyyy'')
                     WHEN @Period IN (''Quarter'', ''Q'') THEN ''Q'' + CAST(DATEPART(QUARTER, [Invoice Date Key]) AS NVARCHAR) + '' '' + CAST(YEAR([Invoice Date Key]) AS NVARCHAR)
                     WHEN @Period IN (''Year'', ''Y'') THEN CAST(YEAR([Invoice Date Key]) AS NVARCHAR)
                END AS Period,
				SUM(Quantity*[Unit Price])'+
		'FROM Fact.Sale s ' +
		'JOIN Dimension.Customer c ON s.[Customer Key] = c.[Customer Key]' +
		'WHERE YEAR([Invoice Date Key]) BETWEEN @FromYear AND @ToYear
		AND (@CustomerID IS NULL OR s.[Customer Key] = @CustomerID)' +
		'GROUP BY s.[Customer Key],
				Customer,
				CASE WHEN @Period IN (''Month'', ''M'') THEN FORMAT([Invoice Date Key], ''MMM yyyy'')
                     WHEN @Period IN (''Quarter'', ''Q'') THEN ''Q'' + CAST(DATEPART(QUARTER, [Invoice Date Key]) AS NVARCHAR) + '' '' + CAST(YEAR([Invoice Date Key]) AS NVARCHAR)
                     WHEN @Period IN (''Year'', ''Y'') THEN CAST(YEAR([Invoice Date Key]) AS NVARCHAR)
                END'; 

        EXEC sp_executesql @DynamicSQL, @ParamDefinition, @Period = @Period, @FromYear = @FromYear, @ToYear = @ToYear, @CustomerID = @CustomerID;
		--print @DynamicSQL
    END TRY
    BEGIN CATCH
        INSERT INTO [ErrorLog]([ErrorNumber], [ErrorSeverity], [ErrorMessage], [CustomerID], [Period])
        VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_MESSAGE(), @CustomerID, @Period);
    END CATCH;
END;

GO
