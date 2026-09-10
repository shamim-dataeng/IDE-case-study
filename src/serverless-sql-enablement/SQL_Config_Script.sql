CREATE DATABASE gold_taxi_dw;
GO
USE gold_taxi_dw;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Str0ng!P@ssw0rd#2024';
GO

-- Credential using your Entra identity (since you already have Storage Blob Data Contributor)
CREATE DATABASE SCOPED CREDENTIAL synapse_managed_identity
WITH IDENTITY = 'Managed Identity';
GO

CREATE EXTERNAL DATA SOURCE gold_lake
WITH (
    LOCATION = 'abfss://gold@idestorageaccount.dfs.core.windows.net/',
    CREDENTIAL = synapse_managed_identity
);
GO