# CompareTables
A T-SQL script (for SQL Server) for identifying data differences in tables with similar structures.

There is one dependency that I pulled from another location: dbo.SplitString

Parameter       | Type    |Description
--------------- | ------- | ------------
@table1         | varchar | The left side of the comparison. One- or Two-part name.
@table2         | varchar | The right side of the comparison. One- or Two-part name.
@pk             | varchar | The Primary Key columns shared by the two tables. If multiple, separate with commas.
@topValue       | int     | Max number of rows to return. Useful for large tables.
@includeColumns | varchar | May choose specific columns to compare (separated by a comma), or simply put * or NULL for all columns
@excludeColumns | varchar | May choose specific columns to exclude (separated by a comma); useful when using * above.
@allowNoMatch   | bit     | Toggle this to ignore all records that don't have a match on the primary key
@whereClause    | varchar | Optionally specify where clauses on each table by using T1.<column> or T2.<column>
@orderBy        | varchar | Optionally order the results by a certain column
@includeStats   | bit     | Option to include 
@caseSensitive  | bit     | Toggle to check case when comparing
@debug          | bit     | Print out the dynamic SQL; toggle if you run into issues.
