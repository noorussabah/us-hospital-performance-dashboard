-- ------------------------------------------------------------
-- DIMENSION TABLES
-- ------------------------------------------------------------

-- Hospital table 

IF OBJECT_ID('dbo.dim_hospital', 'U') IS NOT NULL
    DROP TABLE dbo.dim_hospital;
GO

CREATE TABLE dbo.dim_hospital (
  facility_id        NVARCHAR(20)  NOT NULL,
  facility_name      NVARCHAR(255) NULL,
  address            NVARCHAR(255) NULL,
  city_town          NVARCHAR(100) NULL,
  state              NCHAR(2)      NULL,
  zip_code           NVARCHAR(15)  NULL,
  county_parish      NVARCHAR(120) NULL,
  telephone_number   NVARCHAR(30)  NULL,

  hospital_type      NVARCHAR(120) NULL,
  hospital_ownership NVARCHAR(120) NULL,
  emergency_services NVARCHAR(50)  NULL,

  -- convenience flags
  has_emergency_services TINYINT NULL,

  load_ts DATETIME2 NOT NULL CONSTRAINT DF_dim_hospital_loadts DEFAULT SYSDATETIME(),

  CONSTRAINT PK_dim_hospital PRIMARY KEY (facility_id)
);
GO

CREATE INDEX idx_dim_hosp_state ON dbo.dim_hospital(state);
GO
CREATE INDEX idx_dim_hosp_type  ON dbo.dim_hospital(hospital_type);
GO
CREATE INDEX idx_dim_hosp_owner ON dbo.dim_hospital(hospital_ownership);
GO


;WITH ranked AS (
  SELECT
    LTRIM(RTRIM(Facility_ID)) AS facility_id,
    NULLIF(LTRIM(RTRIM(Facility_Name)), '') AS facility_name,
    NULLIF(LTRIM(RTRIM([Address])), '') AS address,
    NULLIF(LTRIM(RTRIM(City_Town)), '') AS city_town,
    NULLIF(LTRIM(RTRIM([State])), '') AS state,
    NULLIF(LTRIM(RTRIM(ZIP_Code)), '') AS zip_code,
    NULLIF(LTRIM(RTRIM(County_Parish)), '') AS county_parish,
    NULLIF(LTRIM(RTRIM(Telephone_Number)), '') AS telephone_number,
    NULLIF(LTRIM(RTRIM(Hospital_Type)), '') AS hospital_type,
    NULLIF(LTRIM(RTRIM(Hospital_Ownership)), '') AS hospital_ownership,
    NULLIF(LTRIM(RTRIM(Emergency_Services)), '') AS emergency_services,
    CASE
      WHEN UPPER(LTRIM(RTRIM(Emergency_Services))) IN ('YES','Y') THEN 1
      WHEN UPPER(LTRIM(RTRIM(Emergency_Services))) IN ('NO','N')  THEN 0
      ELSE NULL
    END AS has_emergency_services,
    ROW_NUMBER() OVER (
      PARTITION BY LTRIM(RTRIM(Facility_ID))
      ORDER BY Facility_ID DESC
    ) AS rn
  FROM dbo.raw_hospital_general_information
  WHERE Facility_ID IS NOT NULL AND LTRIM(RTRIM(Facility_ID)) <> ''
)
INSERT INTO dbo.dim_hospital (
  facility_id, facility_name, address, city_town, state, zip_code,
  county_parish, telephone_number, hospital_type, hospital_ownership,
  emergency_services, has_emergency_services
)
SELECT
  facility_id, facility_name, address, city_town, state, zip_code,
  county_parish, telephone_number, hospital_type, hospital_ownership,
  emergency_services, has_emergency_services
FROM ranked
WHERE rn = 1;
GO


-- Add grouped ownership columns
ALTER TABLE dbo.dim_hospital
ADD ownership_group NVARCHAR(50) NULL;
GO

UPDATE dbo.dim_hospital
SET ownership_group =
  CASE
    WHEN hospital_ownership LIKE 'Government%' THEN 'Government'
    WHEN hospital_ownership LIKE 'Voluntary non-profit%' THEN 'Nonprofit'
    WHEN hospital_ownership = 'Proprietary' THEN 'For-Profit'
    WHEN hospital_ownership = 'Physician' THEN 'Physician-Owned'
    WHEN hospital_ownership = 'Veterans Health Administration' THEN 'Veterans / Federal'
    ELSE 'Other / Unknown'
  END;
GO

--  Add grouped hospital type ownership column
ALTER TABLE dbo.dim_hospital
ADD hospital_type_group NVARCHAR(50) NULL;
GO

UPDATE dbo.dim_hospital
SET hospital_type_group =
  CASE
    WHEN hospital_type LIKE 'Acute Care%' THEN 'Acute Care'
    WHEN hospital_type = 'Critical Access Hospitals' THEN 'Critical Access'
    WHEN hospital_type = 'Childrens' THEN N'Children’s'
    WHEN hospital_type = 'Rural Emergency Hospital' THEN 'Rural Emergency'
    WHEN hospital_type = 'Psychiatric' THEN 'Psychiatric'
    WHEN hospital_type LIKE 'Long-term%' THEN 'Long-Term Care'
    WHEN hospital_type IS NULL OR LTRIM(RTRIM(hospital_type)) = '' THEN 'Other / Unknown'
    ELSE 'Other / Unknown'
  END;
GO

SELECT * FROM dbo.dim_hospital;
GO
 

-- ------------------------------------------------------------
-- FACT TABLES
-- ------------------------------------------------------------

-- Overall Rating of hospitals 
IF OBJECT_ID('dbo.fact_overall_rating', 'U') IS NOT NULL
    DROP TABLE dbo.fact_overall_rating;
GO

CREATE TABLE dbo.fact_overall_rating (
  facility_id        NVARCHAR(20) NOT NULL,
  overall_rating     TINYINT NULL,           -- 1..5
  rating_text        NVARCHAR(50) NULL,      -- original
  rating_footnote    NVARCHAR(MAX) NULL,
  is_available       TINYINT NOT NULL,       -- 1 if rating present, else 0
  load_ts            DATETIME2 NOT NULL CONSTRAINT DF_fact_overall_rating_loadts DEFAULT SYSDATETIME(),

  CONSTRAINT PK_fact_overall_rating PRIMARY KEY (facility_id),
  CONSTRAINT fk_fact_rating_hosp
    FOREIGN KEY (facility_id) REFERENCES dbo.dim_hospital(facility_id)
);
GO

;WITH ranked AS (
  SELECT
    LTRIM(RTRIM(r.Facility_ID)) AS facility_id,
    NULLIF(LTRIM(RTRIM(r.Hospital_Overall_Rating)), '') AS rating_text,
    NULLIF(LTRIM(RTRIM(r.Hospital_Overall_Rating_Footnote)), '') AS rating_footnote,
    ROW_NUMBER() OVER (
      PARTITION BY LTRIM(RTRIM(r.Facility_ID))
      ORDER BY r.Facility_ID DESC
    ) AS rn
  FROM dbo.raw_hospital_general_information r
  WHERE r.Facility_ID IS NOT NULL
    AND LTRIM(RTRIM(r.Facility_ID)) <> ''
)
INSERT INTO dbo.fact_overall_rating (
  facility_id, overall_rating, rating_text, rating_footnote, is_available
)
SELECT
  ranked.facility_id,
  TRY_CONVERT(TINYINT, ranked.rating_text) AS overall_rating,
  ranked.rating_text,
  ranked.rating_footnote,
  CASE WHEN TRY_CONVERT(TINYINT, ranked.rating_text) IS NOT NULL THEN 1 ELSE 0 END AS is_available
FROM ranked
INNER JOIN dbo.dim_hospital h
  ON h.facility_id = ranked.facility_id
WHERE ranked.rn = 1;
GO

SELECT * FROM dbo.fact_overall_rating;
GO



-- HCAHPS (Hospital Consumer Assessment of Healthcare Providers and Systems) Patient Survey 
IF OBJECT_ID('dbo.fact_patients_rating', 'U') IS NOT NULL
    DROP TABLE dbo.fact_patients_rating;
GO

CREATE TABLE dbo.fact_patients_rating (
  facility_id NVARCHAR(20) NULL,

  hcahps_measure_id NVARCHAR(50) NULL,
  hcahps_question NVARCHAR(MAX) NULL,
  hcahps_answer_description NVARCHAR(MAX) NULL,

  patient_survey_star_rating NVARCHAR(50) NULL,

  number_of_completed_surveys NVARCHAR(50) NULL,

  start_date NVARCHAR(25) NULL,
  end_date   NVARCHAR(25) NULL,

  load_ts DATETIME2 NOT NULL CONSTRAINT DF_fact_patients_rating_loadts DEFAULT SYSDATETIME()
);
GO

CREATE INDEX idx_fpr_facility ON dbo.fact_patients_rating(facility_id);
GO
CREATE INDEX idx_fpr_measure  ON dbo.fact_patients_rating(hcahps_measure_id);
GO

INSERT INTO dbo.fact_patients_rating (
  facility_id,
  hcahps_measure_id,
  hcahps_question,
  hcahps_answer_description,
  patient_survey_star_rating,
  number_of_completed_surveys,
  start_date,
  end_date
)
SELECT
  LTRIM(RTRIM(r.Facility_ID)) AS facility_id,
  LTRIM(RTRIM(r.HCAHPS_Measure_ID)) AS hcahps_measure_id,
  r.HCAHPS_Question,
  r.HCAHPS_Answer_Description,
  LTRIM(RTRIM(r.Patient_Survey_Star_Rating)) AS patient_survey_star_rating,
  LTRIM(RTRIM(r.Number_of_Completed_Surveys)) AS number_of_completed_surveys,
  LTRIM(RTRIM(r.Start_Date)) AS start_date,
  LTRIM(RTRIM(r.End_Date)) AS end_date
FROM dbo.raw_hcahps_hospital r
INNER JOIN dbo.dim_hospital h
  ON h.facility_id = LTRIM(RTRIM(r.Facility_ID))
WHERE
  r.Patient_Survey_Star_Rating IS NOT NULL
  AND TRY_CONVERT(INT, LTRIM(RTRIM(r.Patient_Survey_Star_Rating))) IS NOT NULL;
GO

SELECT * FROM dbo.fact_patients_rating;
GO
