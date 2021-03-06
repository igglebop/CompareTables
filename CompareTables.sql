/*@
    #Author:        Ryan Shepherd
    #Version:       1.9.0
    #Description:   Compare two tables with column names in common. Differences are flagged with a ****.
    #CreateDate:    2014-03-12
*/
CREATE PROCEDURE dbo.[CompareTables] (
    @table1 VARCHAR(100),
    @table2 VARCHAR(100),
    @pk VARCHAR(1000),                          -- Comma-delimited list of PK's allowed
    @topValue INT = 100,
    @includeColumns VARCHAR(1000) = '*',        -- Can list specific columns to compare, or simply put * or NULL for all columns
    @excludeColumns VARCHAR(1000) = NULL,       -- Can list specific columns to exclude.  Useful is using * above.
    @allowNoMatch BIT = 1,                      -- Toggle this to elliminate all records that don't have a match on PK
    @whereClause VARCHAR(1000) = NULL,          -- Need to specify T1.<column> AND T2.<COLUMN> in where clause
    @orderBy VARCHAR(100) = NULL,
    @includeStats BIT = 0,
    @caseSensitive BIT = 0,
    @debug BIT = 0
)
AS

/*
DECLARE
    @table1 VARCHAR(100)    = 'ProdDataTest.practitioner',
    @table2 VARCHAR(100)    = 'X_HR.V_PRACTITIONER',
    @pk VARCHAR(100)        = 'PRACTITIONER_ID',
    @topValue INT           = '100',
    @includeColumns VARCHAR(1000) = '*',        -- Can list specific columns to compare, or simply put * or NULL for all columns
    @excludeColumns VARCHAR(1000) = 'HR_ID'        -- Can list specific columns to exclude.  Useful is using * above.
*/

--------------------------------------------

-- Default values
IF LEN(@includeColumns) = 0 SET @includeColumns = '*';
IF LEN(@excludeColumns) = 0 SET @excludeColumns = NULL;
IF LEN(@orderBy) = 0 SET @orderBy = NULL;
IF LEN(@whereClause) = 0 SET @whereClause = NULL;

CREATE TABLE #COLUMNS_TABLE1 (COLUMN_NAME VARCHAR(200), DATA_TYPE VARCHAR(20), CHARACTER_MAXIMUM_LENGTH INT, ORDINAL_POSITION INT);
CREATE TABLE #COLUMNS_TABLE2 (COLUMN_NAME VARCHAR(200), DATA_TYPE VARCHAR(20), CHARACTER_MAXIMUM_LENGTH INT, ORDINAL_POSITION INT);

DECLARE
    @columns VARCHAR(MAX) = '',
    @where VARCHAR(MAX) = '',
    @whereDifferent VARCHAR(MAX) = '',
    @on VARCHAR(MAX) = '',
    @sql VARCHAR(MAX) = '',
    @flag VARCHAR(10) = '****',
    @NL CHAR(2) = CHAR(13) + CHAR(10);      -- Newline

-- Extract useful information about the columns
INSERT INTO #COLUMNS_TABLE1
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE
    TABLE_SCHEMA = ISNULL(PARSENAME(@table1, 2), 'dbo') AND
    TABLE_NAME = PARSENAME(@table1, 1);

INSERT INTO #COLUMNS_TABLE2
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE
    TABLE_SCHEMA = ISNULL(PARSENAME(@table2, 2), 'dbo') AND
    TABLE_NAME = PARSENAME(@table2, 1);

-- Build up the Columns assignments and Where clause for the select
SET @columns = '';
SET @whereDifferent = '';
SELECT
    @columns += REPLACE(REPLACE(
        '    ' +
        '{COLUMN_NAME} = ' +
        'CASE ' +
            'WHEN (T1.{COLUMN_NAME} {COLLATION} <> T2.{COLUMN_NAME} {COLLATION}) OR ' +
            '(T1.{COLUMN_NAME} IS NULL AND T2.{COLUMN_NAME} IS NOT NULL) OR ' +
            '(T2.{COLUMN_NAME} IS NULL AND T1.{COLUMN_NAME} IS NOT NULL) ' +
        'THEN ' +
            '''' + @flag + ''' + ' +        -- Add the flag
            'ISNULL(CAST(T1.{COLUMN_NAME} AS VARCHAR(500)), ''<NULL>'') + ''  ||  '' + ISNULL(CAST(T2.{COLUMN_NAME} AS VARCHAR(500)), ''<NULL>'') ' +

        'ELSE CAST(T1.{COLUMN_NAME} AS VARCHAR(200)) END,' + @NL,

        '{COLUMN_NAME}', '[' + COLUMN_NAME + ']'),
        '{COLLATION}', CASE WHEN DATA_TYPE LIKE '%CHAR' AND @caseSensitive = 1 THEN 'COLLATE SQL_Latin1_General_CP1_CS_AS' ELSE '' END),

    @whereDifferent += REPLACE(REPLACE(
        CHAR(9) +
        '(T1.{COLUMN_NAME} {COLLATION} <> T2.{COLUMN_NAME} {COLLATION}) OR ' +
        '(T1.{COLUMN_NAME} {COLLATION} IS NULL AND T2.{COLUMN_NAME} {COLLATION} IS NOT NULL) OR ' +
        '(T2.{COLUMN_NAME} {COLLATION} IS NULL AND T1.{COLUMN_NAME} {COLLATION} IS NOT NULL) OR' + @NL,

        '{COLUMN_NAME}', '[' + COLUMN_NAME + ']'),
        '{COLLATION}', CASE WHEN DATA_TYPE LIKE '%CHAR' AND @caseSensitive = 1 THEN 'COLLATE SQL_Latin1_General_CP1_CS_AS' ELSE '' END)
FROM
    #COLUMNS_TABLE1
WHERE
    COLUMN_NAME IN (SELECT COLUMN_NAME FROM #COLUMNS_TABLE2)
ORDER BY ORDINAL_POSITION

-- Cut off the last ' OR'
SET @columns = LEFT(@columns, LEN(@columns) - 3)
SET @whereDifferent = LEFT(@whereDifferent, LEN(@whereDifferent) - 4)

-- Add the user-specified where clause
SET @where = '(' + @NL + @whereDifferent + @NL + ')' + ISNULL(' AND (' + @whereClause + ')', '');

-- Split the PK to build the ON statement
SET @on = '';
SELECT
    @on += '    T1.' + LTRIM(RTRIM(Item)) + ' = T2.' + LTRIM(RTRIM(Item)) + ' AND ' + @NL
FROM
    dbo.SplitString(@pk, ',')
WHERE
    Item IS NOT NULL AND 
    LEN(Item) > 0;

SET @on = LEFT(@on, LEN(@on) - LEN(' AND ' + @NL));


DECLARE @joinType VARCHAR(100);
SET @joinType = CASE WHEN @allowNoMatch = 1 THEN 'FULL OUTER JOIN' ELSE 'INNER JOIN' END;

-- Stats
IF @includeStats = 1
BEGIN
    -- Need this for the where clause
    DECLARE @firstPKColumn VARCHAR(200)
    SET @firstPKColumn = (SELECT TOP 1 LTRIM(RTRIM(Item)) FROM dbo.SplitString(@pk, ',') WHERE Item IS NOT NULL AND LEN(Item) > 0);

    PRINT '';
    PRINT '';
    SET @sql = '
        DECLARE @T1Only INT, @T2Only INT, @TotalMatched INT, @MatchedAndDiff INT
        SELECT @T1Only = COUNT(*)
        FROM {TABLE1} T1
        LEFT JOIN {TABLE2} T2 ON {ON}
        WHERE
            T2.{FirstPK} IS NULL AND
            {UserWhereClause};

        SELECT @T2Only = COUNT(*)
        FROM {TABLE2} T2
        LEFT JOIN {TABLE1} T1 ON {ON}
        WHERE
            T1.{FirstPK} IS NULL AND
            {UserWhereClause};

        SELECT @TotalMatched = COUNT(*)
        FROM {TABLE1} T1
        INNER JOIN {TABLE2} T2 ON {ON}
        WHERE {UserWhereClause}

        SELECT @MatchedAndDiff = COUNT(*)
        FROM {TABLE1} T1
        INNER JOIN {TABLE2} T2
        ON {ON}
        WHERE
            {WHERE};

        PRINT       ''_____T1_Only______|_____Matched______|_____T2_Only______''
        PRINT STUFF(''                  |'', 7, LEN(CAST(@T1Only AS VARCHAR)), CAST(@T1Only AS VARCHAR)) +
              STUFF(''                  |'', 7, LEN(CAST(@TotalMatched AS VARCHAR)), CAST(@TotalMatched AS VARCHAR)) +
                    ''       '' + CAST(@T2Only AS VARCHAR);
        PRINT       ''                  |------------------|''
        PRINT       ''                  |'' +
              STUFF('' Same:            |'', 8, LEN(CAST(@TotalMatched - @MatchedAndDiff AS VARCHAR)), CAST(@TotalMatched - @MatchedAndDiff AS VARCHAR))
        PRINT       ''                  |'' +
              STUFF('' Diff:            |'', 8, LEN(CAST(@MatchedAndDiff AS VARCHAR)), CAST(@MatchedAndDiff AS VARCHAR))
        ';

    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@sql,
        '{TABLE1}', @table1),
        '{TABLE2}', @table2),
        '{ON}', @on),
        '{FirstPK}', @firstPKColumn),
        '{WHERE}', @where),
        '{UserWhereClause}', ISNULL(@whereClause, '1=1'));

    IF @debug = 1
        PRINT @sql;
    EXEC(@sql);
END;

-- Run the SQL
SET @sql =
    'SELECT ' + ISNULL('TOP ' + CAST(@topValue AS VARCHAR), '') + @NL +
        @columns                       + @NL +
    'FROM'                             + @NL +
        @table1 + ' T1'                + @NL +
    @joinType                          + @NL +
        @table2 + ' T2'                + @NL +
    'ON'                               + @NL +
        @on                            + @NL +
    'WHERE'                            + @NL +
        @where                         + @NL +
    ISNULL('ORDER BY ' + @orderBy, '')

IF @debug = 1
    PRINT @sql;
EXEC(@sql);

