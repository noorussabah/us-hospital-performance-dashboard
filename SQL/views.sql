-- View: Average rating by state
CREATE OR ALTER VIEW dbo.vw_avg_rating_by_state
AS
SELECT
    h.state,
    COUNT(*) AS hospitals_with_rating,
    ROUND(AVG(CAST(r.overall_rating AS FLOAT)), 2) AS avg_rating
FROM dbo.dim_hospital h
JOIN dbo.fact_overall_rating r
    ON r.facility_id = h.facility_id
WHERE r.is_available = 1
GROUP BY h.state;
GO



-- View: Ownership x Type 
CREATE OR ALTER VIEW dbo.vw_avg_rating_by_type_ownership
AS
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
GO

-- Overall rating vs patient satisfaction
CREATE OR ALTER VIEW dbo.vw_patient_vs_overall_rating
AS
WITH avg_patient_rating AS (
    SELECT
        facility_id,
        ROUND(AVG(CAST(patient_survey_star_rating AS FLOAT)), 2) AS avg_patient_rating,
        SUM(TRY_CONVERT(INT, NULLIF(number_of_completed_surveys, ''))) / 11 AS total_completed_surveys,
        COUNT(*) AS rows_included
    FROM dbo.fact_patients_rating
    GROUP BY facility_id
)
SELECT
    h.facility_id,
    h.facility_name,
    h.state,
    h.city_town,
    h.county_parish,
    h.hospital_type_group,
    h.ownership_group,
    h.has_emergency_services,

    r.overall_rating AS overall_hospital_rating,
    a.avg_patient_rating,
    a.total_completed_surveys,
    a.rows_included
FROM avg_patient_rating a
JOIN dbo.dim_hospital h
    ON h.facility_id = a.facility_id
JOIN dbo.fact_overall_rating r
    ON r.facility_id = a.facility_id
   AND r.is_available = 1;
GO


-- STD DEV by aspect
CREATE OR ALTER VIEW dbo.vw_hcahps_aspect_variation
AS
WITH latest_per_measure AS (
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
HAVING COUNT(*) >= 2;
GO

-- Mismatch flag categories
CREATE OR ALTER VIEW dbo.vw_patient_rating_mismatch
AS
WITH base AS (
    SELECT *
    FROM dbo.vw_patient_vs_overall_rating
),
flagged AS (
    SELECT
        b.*,
        CASE
            WHEN b.overall_hospital_rating >= 4 AND b.avg_patient_rating <= 2.5
                THEN 'High overall / Low patient'
            WHEN b.overall_hospital_rating <= 2 AND b.avg_patient_rating >= 3.5
                THEN 'Low overall / High patient'
            WHEN ABS(b.avg_patient_rating - b.overall_hospital_rating) >= 1.5
                THEN 'Large gap (>= 1.5 stars)'
            ELSE 'Aligned / moderate gap'
        END AS mismatch_flag
    FROM base b
)
SELECT * FROM flagged;
GO


-- ED (Emergency Department) Performance
CREATE OR ALTER VIEW dbo.vw_ed_performance_unified
AS
WITH base AS (
    SELECT
        LTRIM(RTRIM(t.Facility_ID)) AS facility_id,
        LTRIM(RTRIM(t.Measure_ID))  AS measure_id,
        MAX(LTRIM(RTRIM(t.Measure_Name))) AS measure_name,

        TRY_CONVERT(float, LTRIM(RTRIM(t.Score)))  AS score_num,
        TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))) AS sample_num,

        TRY_CONVERT(
            date,
            LTRIM(RTRIM(REPLACE(REPLACE(t.End_Date, CHAR(13), ''), CHAR(10), ''))),
            23
        ) AS end_date
    FROM dbo.raw_timely_effective_care_hospital t
    WHERE LTRIM(RTRIM(t.[Condition])) = 'Emergency Department'
      AND LTRIM(RTRIM(t.Measure_ID)) <> 'EDV'         -- exclude volume
    GROUP BY
        LTRIM(RTRIM(t.Facility_ID)),
        LTRIM(RTRIM(t.Measure_ID)),
        TRY_CONVERT(float, LTRIM(RTRIM(t.Score))),
        TRY_CONVERT(float, LTRIM(RTRIM(t.Sample))),
        TRY_CONVERT(
            date,
            LTRIM(RTRIM(REPLACE(REPLACE(t.End_Date, CHAR(13), ''), CHAR(10), ''))),
            23
        )
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
        s.sample_num,
        s.end_date,
        -- higher = better performance (lower score minutes -> better)
        1.0 - PERCENT_RANK() OVER (PARTITION BY s.measure_id ORDER BY s.score_num ASC) AS perf_percentile
    FROM scored s
),
hospital_rollup AS (
    SELECT
        facility_id,
        COUNT(DISTINCT measure_id) AS ed_measures_included,
        ROUND(AVG(perf_percentile), 4) AS ed_performance_index,
        ROUND(AVG(score_num), 2) AS avg_ed_minutes
    FROM ranked
    GROUP BY facility_id
),
state_rollup AS (
    SELECT
        h.state,
        COUNT(DISTINCT r.facility_id) AS state_hospitals,
        ROUND(AVG(hr.ed_performance_index), 4) AS avg_state_ed_performance_index
    FROM hospital_rollup hr
    JOIN dbo.dim_hospital h
      ON h.facility_id = hr.facility_id
    JOIN ranked r
      ON r.facility_id = hr.facility_id
    GROUP BY h.state
),
measure_rollup AS (
    SELECT
        measure_id,
        MAX(measure_name) AS measure_name,
        COUNT(*) AS hospitals_reporting_measure,
        ROUND(AVG(score_num), 2) AS measure_avg_score,
        ROUND(STDEV(score_num), 2) AS measure_stddev_score
    FROM ranked
    GROUP BY measure_id
)
SELECT
    -- slicer-friendly hospital attributes
    h.facility_id,
    h.facility_name,
    h.city_town,
    h.state,
    h.county_parish,
    h.hospital_type_group,
    h.ownership_group,
    h.has_emergency_services,

    -- ED measure grain (1 row per hospital per ED measure)
    r.measure_id,
    r.measure_name,
    r.score_num,
    r.sample_num,
    r.end_date,
    r.perf_percentile,

    -- hospital-level composite metrics (repeat per row)
    hr.ed_measures_included,
    hr.ed_performance_index,
    hr.avg_ed_minutes,

    -- state-level metrics (repeat per row)
    sr.state_hospitals,
    sr.avg_state_ed_performance_index,

    -- measure-level distribution stats (repeat per row)
    mr.hospitals_reporting_measure,
    mr.measure_avg_score,
    mr.measure_stddev_score

FROM ranked r
JOIN dbo.dim_hospital h
  ON h.facility_id = r.facility_id
JOIN hospital_rollup hr
  ON hr.facility_id = r.facility_id
JOIN state_rollup sr
  ON sr.state = h.state
JOIN measure_rollup mr
  ON mr.measure_id = r.measure_id;
GO

