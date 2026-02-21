-- National distribution of star ratings
SELECT
    overall_rating,
    COUNT(*) AS hospitals
FROM dbo.fact_overall_rating
WHERE is_available = 1
GROUP BY overall_rating
ORDER BY overall_rating;

-- Average rating by state
SELECT
    h.state,
    COUNT(*) AS hospitals_with_rating,
    ROUND(AVG(CAST(r.overall_rating AS FLOAT)), 2) AS avg_rating
FROM dbo.dim_hospital h
JOIN dbo.fact_overall_rating r
    ON r.facility_id = h.facility_id
WHERE r.is_available = 1
GROUP BY h.state
ORDER BY avg_rating DESC;

-- Average rating by ownership
SELECT
    h.ownership_group,
    COUNT(*) AS hospitals_with_rating,
    ROUND(AVG(CAST(r.overall_rating AS FLOAT)), 2) AS avg_rating
FROM dbo.dim_hospital h
JOIN dbo.fact_overall_rating r
    ON r.facility_id = h.facility_id
WHERE r.is_available = 1
GROUP BY h.ownership_group
ORDER BY hospitals_with_rating DESC;

-- Ownership x Type
SELECT
    h.hospital_type_group,
    h.ownership_group,
    COUNT(*) AS hospitals_with_rating,
    ROUND(AVG(CAST(r.overall_rating AS FLOAT)), 2) AS avg_rating
FROM dbo.dim_hospital h
JOIN dbo.fact_overall_rating r
    ON r.facility_id = h.facility_id
WHERE r.is_available = 1
GROUP BY
    h.hospital_type_group,
    h.ownership_group
HAVING COUNT(*) >= 10
ORDER BY
    h.hospital_type_group,
    h.ownership_group;

-- Emergency services vs rating
SELECT
    h.has_emergency_services,
    COUNT(*) AS hospitals_with_rating,
    ROUND(AVG(CAST(r.overall_rating AS FLOAT)), 2) AS avg_rating
FROM dbo.dim_hospital h
JOIN dbo.fact_overall_rating r
    ON r.facility_id = h.facility_id
WHERE r.is_available = 1
GROUP BY h.has_emergency_services
ORDER BY h.has_emergency_services DESC;


-- Hospital rating vs patient rating
;WITH avg_patient_rating AS (
    SELECT
        facility_id,
        ROUND(AVG(CAST(patient_survey_star_rating AS FLOAT)), 2) AS avg_patient_rating,
        SUM(TRY_CONVERT(INT, NULLIF(number_of_completed_surveys, ''))) / 11
            AS total_completed_surveys,
        COUNT(*) AS rows_included
    FROM dbo.fact_patients_rating
    GROUP BY facility_id
)
SELECT
    h.facility_id,
    h.facility_name,
    h.state,
    h.hospital_type_group,
    h.ownership_group,
    r.overall_rating AS overall_hospital_rating,
    a.avg_patient_rating,
    a.total_completed_surveys
FROM avg_patient_rating a
JOIN dbo.dim_hospital h
    ON h.facility_id = a.facility_id
JOIN dbo.fact_overall_rating r
    ON r.facility_id = a.facility_id
   AND r.is_available = 1
ORDER BY a.avg_patient_rating DESC;


-- STD DEV of ratings
-- Faster STD DEV query (filters to latest per measure early)
;WITH latest_per_measure AS (
    SELECT
        hcahps_measure_id,
        MAX(TRY_CONVERT(DATE, LTRIM(RTRIM(end_date)), 23)) AS max_end_dt
    FROM dbo.fact_patients_rating
    WHERE end_date IS NOT NULL
      AND TRY_CONVERT(INT, patient_survey_star_rating) IS NOT NULL
    GROUP BY hcahps_measure_id
),
filtered AS (
    SELECT
        f.facility_id,
        f.hcahps_measure_id,
        REPLACE(LTRIM(RTRIM(f.hcahps_question)), ' - star rating', '') AS aspect,
        TRY_CONVERT(INT, f.patient_survey_star_rating) AS rating,
        TRY_CONVERT(DATE, LTRIM(RTRIM(f.end_date)), 23) AS end_dt
    FROM dbo.fact_patients_rating f
    JOIN latest_per_measure l
      ON l.hcahps_measure_id = f.hcahps_measure_id
     AND l.max_end_dt = TRY_CONVERT(DATE, LTRIM(RTRIM(f.end_date)), 23)
    WHERE TRY_CONVERT(INT, f.patient_survey_star_rating) IS NOT NULL
)
SELECT
    hcahps_measure_id,
    aspect,
    end_dt,
    COUNT(*) AS n_rows,
    ROUND(AVG(CAST(rating AS FLOAT)), 2) AS avg_rating,
    ROUND(STDEV(CAST(rating AS FLOAT)), 3) AS rating_stddev
FROM filtered
GROUP BY hcahps_measure_id, aspect, end_dt
HAVING COUNT(*) >= 2   -- avoid NULL STDEV groups
ORDER BY rating_stddev DESC;


-- How does Emergency Department operational performance vary across hospitals and states?
;WITH base AS (
  SELECT
    LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
    LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
    MAX(LTRIM(RTRIM(t.Measure_Name))) AS measure_name,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score)))  AS score_num,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))) AS sample_num,
    TRY_CONVERT(date, LTRIM(RTRIM(REPLACE(REPLACE(t.End_Date, CHAR(13), ''), CHAR(10), ''))), 23) AS end_date
  FROM dbo.raw_timely_effective_care_hospital t
  WHERE LTRIM(RTRIM(t.[Condition])) = 'Emergency Department'
    AND LTRIM(RTRIM(t.Measure_ID)) <> 'EDV'   -- exclude volume
  GROUP BY
    LTRIM(RTRIM(t.Facility_ID)),
    LTRIM(RTRIM(t.Measure_ID)),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))),
    TRY_CONVERT(date, LTRIM(RTRIM(REPLACE(REPLACE(t.End_Date, CHAR(13), ''), CHAR(10), ''))), 23)
),
latest AS (
  SELECT MAX(end_date) AS max_end_date
  FROM base
  WHERE end_date IS NOT NULL
),
scored AS (
  SELECT *
  FROM base
  WHERE score_num IS NOT NULL
    AND end_date = (SELECT max_end_date FROM latest) 
),
ranked AS (
  SELECT
    s.facility_id,
    s.measure_id,
    s.measure_name,
    s.score_num,
    -- Percentile rank: higher = better performance 
    1.0 - PERCENT_RANK() OVER (PARTITION BY s.measure_id ORDER BY s.score_num ASC) AS perf_percentile
  FROM scored s
),
hospital_index AS (
  SELECT
    facility_id,
    COUNT(DISTINCT measure_id) AS ed_measures_included,
    ROUND(AVG(perf_percentile), 4) AS ed_performance_index,
    ROUND(AVG(score_num), 2) AS avg_ed_minutes
  FROM ranked
  GROUP BY facility_id
)
SELECT
  hi.facility_id,
  h.facility_name,
  h.city_town,
  h.state,
  h.county_parish,
  h.hospital_type_group,
  h.ownership_group,

  hi.ed_measures_included,
  hi.ed_performance_index,
  hi.avg_ed_minutes
FROM hospital_index hi
JOIN dbo.dim_hospital h ON h.facility_id = hi.facility_id
ORDER BY hi.ed_performance_index DESC, hi.avg_ed_minutes ASC;


;WITH hospital_index AS ( 
  SELECT
    facility_id,
    COUNT(DISTINCT measure_id) AS ed_measures_included,
    ROUND(AVG(perf_percentile), 4) AS ed_performance_index
  FROM (
    SELECT
      s.facility_id,
      s.measure_id,
      1.0 - PERCENT_RANK() OVER (PARTITION BY s.measure_id ORDER BY s.score_num ASC) AS perf_percentile
    FROM (
      SELECT
        LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
        LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
        TRY_CONVERT(float, LTRIM(RTRIM(t.Score)))  AS score_num,
        TRY_CONVERT(date, LTRIM(RTRIM(REPLACE(REPLACE(t.End_Date, CHAR(13), ''), CHAR(10), ''))), 23) AS end_date
      FROM dbo.raw_timely_effective_care_hospital t
      WHERE LTRIM(RTRIM(t.[Condition])) = 'Emergency Department'
        AND LTRIM(RTRIM(t.Measure_ID)) <> 'EDV'
    ) s
    WHERE s.score_num IS NOT NULL
      AND s.end_date = (
        SELECT MAX(
          TRY_CONVERT(date, LTRIM(RTRIM(REPLACE(REPLACE(End_Date, CHAR(13), ''), CHAR(10), ''))), 23)
        )
        FROM dbo.raw_timely_effective_care_hospital
        WHERE LTRIM(RTRIM([Condition])) = 'Emergency Department'
      )
  ) r
  GROUP BY facility_id
)
SELECT
  h.state,
  COUNT(*) AS hospitals,
  ROUND(AVG(hospital_index.ed_performance_index), 4) AS avg_state_ed_performance_index
FROM hospital_index
JOIN dbo.dim_hospital h ON h.facility_id = hospital_index.facility_id
GROUP BY h.state
ORDER BY avg_state_ed_performance_index DESC;


--Average delays by group (State / Type / Ownership)
;WITH base AS (
  SELECT
    LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
    LTRIM(RTRIM(t.[Condition])) AS [condition],
    LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
    MAX(LTRIM(RTRIM(t.Measure_Name))) AS measure_name,

    TRY_CONVERT(float, LTRIM(RTRIM(t.Score)))  AS score_num,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))) AS sample_num,

    TRY_CONVERT(date, LTRIM(RTRIM(t.Start_Date)), 23) AS start_date,
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23)   AS end_date
  FROM dbo.raw_timely_effective_care_hospital t
  GROUP BY
    LTRIM(RTRIM(t.Facility_ID)),
    LTRIM(RTRIM(t.[Condition])),
    LTRIM(RTRIM(t.Measure_ID)),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))),
    TRY_CONVERT(date, LTRIM(RTRIM(t.Start_Date)), 23),
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23)
),
latest AS (
  SELECT MAX(end_date) AS max_end_date
  FROM base
  WHERE end_date IS NOT NULL
),
scored AS (
  SELECT *
  FROM base
  WHERE score_num IS NOT NULL
    AND end_date = (SELECT max_end_date FROM latest)
)
SELECT
  s.facility_id,
  h.state,
  h.hospital_type_group,
  h.ownership_group,
  h.has_emergency_services,
  s.[condition],
  s.measure_id,
  s.measure_name,
  s.score_num,
  s.sample_num,
  s.start_date,
  s.end_date
FROM scored s
JOIN dbo.dim_hospital h
  ON h.facility_id = s.facility_id;


-- Within-state ranking  
;WITH base AS (
  SELECT
    LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
    LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
    MAX(LTRIM(RTRIM(t.Measure_Name))) AS measure_name,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))) AS score_num,
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23) AS end_date
  FROM dbo.raw_timely_effective_care_hospital t
  GROUP BY
    LTRIM(RTRIM(t.Facility_ID)),
    LTRIM(RTRIM(t.Measure_ID)),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))),
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23)
),
latest AS (
  SELECT MAX(end_date) AS max_end_date
  FROM base
  WHERE end_date IS NOT NULL
),
scored AS (
  SELECT *
  FROM base
  WHERE score_num IS NOT NULL
    AND end_date = (SELECT max_end_date FROM latest)
)
SELECT
  h.state,
  s.measure_id,
  MAX(s.measure_name) AS measure_name,
  COUNT(*) AS hospitals_reporting,
  ROUND(AVG(s.score_num), 2) AS avg_score,
  ROUND(STDEV(s.score_num), 2) AS stddev_score
FROM scored s
JOIN dbo.dim_hospital h ON h.facility_id = s.facility_id
GROUP BY h.state, s.measure_id
HAVING COUNT(*) >= 15
ORDER BY s.measure_id, avg_score;


-- Ownership / Hospital Type Effects
;WITH base AS (
  SELECT
    LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
    LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))) AS score_num,
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23) AS end_date
  FROM dbo.raw_timely_effective_care_hospital t
),
latest AS (
  SELECT MAX(end_date) AS max_end_date
  FROM base
  WHERE end_date IS NOT NULL
),
scored AS (
  SELECT *
  FROM base
  WHERE score_num IS NOT NULL
    AND end_date = (SELECT max_end_date FROM latest)
),
joined AS (
  SELECT
    s.facility_id,
    h.state,
    s.measure_id,
    s.score_num
  FROM scored s
  JOIN dbo.dim_hospital h ON h.facility_id = s.facility_id
)
SELECT
  facility_id,
  state,
  measure_id,
  score_num,
  PERCENT_RANK() OVER (
    PARTITION BY state, measure_id
    ORDER BY score_num ASC
  ) AS percentile_within_state
FROM joined;

DECLARE @condition NVARCHAR(120) = 'Emergency Department';

;WITH base AS (
  SELECT
    LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
    LTRIM(RTRIM(t.[Condition])) AS [condition],
    LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
    MAX(LTRIM(RTRIM(t.Measure_Name))) AS measure_name,
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))) AS score_num,
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23) AS end_date
  FROM dbo.raw_timely_effective_care_hospital t
  WHERE LTRIM(RTRIM(t.[Condition])) = @condition
  GROUP BY
    LTRIM(RTRIM(t.Facility_ID)),
    LTRIM(RTRIM(t.[Condition])),
    LTRIM(RTRIM(t.Measure_ID)),
    TRY_CONVERT(float, LTRIM(RTRIM(t.Score))),
    TRY_CONVERT(date, LTRIM(RTRIM(t.End_Date)), 23)
),
latest AS (
  SELECT MAX(end_date) AS max_end_date
  FROM base
  WHERE end_date IS NOT NULL
),
scored AS (
  SELECT *
  FROM base
  WHERE score_num IS NOT NULL
    AND end_date = (SELECT max_end_date FROM latest)
)
SELECT
  h.ownership_group,
  s.measure_id,
  MAX(s.measure_name) AS measure_name,
  COUNT(*) AS hospitals_reporting,
  ROUND(AVG(s.score_num), 2) AS avg_score,
  ROUND(STDEV(s.score_num), 2) AS stddev_score
FROM scored s
JOIN dbo.dim_hospital h ON h.facility_id = s.facility_id
GROUP BY h.ownership_group, s.measure_id
HAVING COUNT(*) >= 15
ORDER BY s.measure_id, avg_score;

