USE gold_taxi_dw;
GO

CREATE VIEW dbo.fact_trips AS
SELECT * FROM OPENROWSET(
    BULK 'fact_trips/',
    DATA_SOURCE = 'gold_lake',
    FORMAT = 'DELTA'
) AS result;
GO

CREATE VIEW dbo.dim_date AS
SELECT * FROM OPENROWSET(BULK 'dim_date/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO

CREATE VIEW dbo.dim_time AS
SELECT * FROM OPENROWSET(BULK 'dim_time/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO

CREATE VIEW dbo.dim_location AS
SELECT * FROM OPENROWSET(BULK 'dim_location/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO

CREATE VIEW dbo.dim_vendor AS
SELECT * FROM OPENROWSET(BULK 'dim_vendor/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO

CREATE VIEW dbo.dim_ratecode AS
SELECT * FROM OPENROWSET(BULK 'dim_ratecode/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO

CREATE VIEW dbo.dim_payment_type AS
SELECT * FROM OPENROWSET(BULK 'dim_payment_type/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS result;
GO