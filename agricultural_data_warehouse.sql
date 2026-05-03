-- =========================================================================
-- AGRICULTURAL DATA WAREHOUSE — SQL SCHEMA & PIPELINE QUERIES
-- =========================================================================
-- Portfolio Project: Data/BI Analyst & Agricultural Planner
-- Organisation: Workforce Group (Nigeria)
-- Database: PostgreSQL 15 (compatible with SQL Server / MySQL with minor mods)
-- Author: [Candidate Name]
-- =========================================================================


-- =========================================================================
-- SECTION 1: SCHEMA CREATION — DIMENSION & FACT TABLES
-- =========================================================================

-- Drop and recreate for clean state
DROP TABLE IF EXISTS fact_yield CASCADE;
DROP TABLE IF EXISTS fact_inputs CASCADE;
DROP TABLE IF EXISTS dim_farm CASCADE;
DROP TABLE IF EXISTS dim_crop CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;
DROP TABLE IF EXISTS dim_input_type CASCADE;

-- ── DIMENSION: Farms / Subsidiaries ──────────────────────────────────────────
CREATE TABLE dim_farm (
    farm_id         SERIAL PRIMARY KEY,
    farm_code       VARCHAR(10) NOT NULL UNIQUE,
    farm_name       VARCHAR(100) NOT NULL,
    state           VARCHAR(50) NOT NULL,
    region          VARCHAR(50),
    area_ha         NUMERIC(8,2),          -- total farmland in hectares
    gis_lat         NUMERIC(9,6),
    gis_lng         NUMERIC(9,6),
    established_yr  SMALLINT,
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO dim_farm (farm_code, farm_name, state, region, area_ha, gis_lat, gis_lng, established_yr)
VALUES
    ('FA001', 'Farm A — Okpe Plantation',    'Delta State',     'South-South', 2400.00,  5.6037,  5.8987, 2010),
    ('FB002', 'Farm B — Obanliku Estate',    'Cross River',     'South-South', 1980.50,  6.5762,  9.2083, 2013),
    ('FC003', 'Farm C — Ijebu Plantation',   'Ogun State',      'South-West',  2150.00,  6.8228,  3.9262, 2011),
    ('FD004', 'Farm D — Ondo North Estate',  'Ondo State',      'South-West',  1760.75,  7.2501,  5.2103, 2015);

-- ── DIMENSION: Crops ──────────────────────────────────────────────────────────
CREATE TABLE dim_crop (
    crop_id             SERIAL PRIMARY KEY,
    crop_code           VARCHAR(10) NOT NULL UNIQUE,
    crop_name           VARCHAR(60) NOT NULL,
    crop_type           VARCHAR(40),          -- Annual / Perennial
    avg_maturity_days   SMALLINT,
    target_yield_mt_ha  NUMERIC(6,2),         -- benchmark yield per ha
    notes               TEXT
);

INSERT INTO dim_crop (crop_code, crop_name, crop_type, avg_maturity_days, target_yield_mt_ha)
VALUES
    ('OPM', 'Oil Palm',  'Perennial', NULL, 20.00),
    ('MZE', 'Maize',     'Annual',     90,   3.50),
    ('CSV', 'Cassava',   'Annual',    270,   25.00),
    ('SBN', 'Soybean',   'Annual',    100,   1.80);

-- ── DIMENSION: Date (calendar table) ─────────────────────────────────────────
CREATE TABLE dim_date (
    date_id     INTEGER PRIMARY KEY,  -- YYYYMMDD integer key
    full_date   DATE NOT NULL UNIQUE,
    year        SMALLINT NOT NULL,
    quarter     SMALLINT NOT NULL,
    quarter_str VARCHAR(6),           -- e.g. 'Q1 2025'
    month_num   SMALLINT NOT NULL,
    month_name  VARCHAR(12) NOT NULL,
    week_num    SMALLINT,
    day_of_week SMALLINT,
    is_weekend  BOOLEAN
);

-- Populate dim_date for 2022–2026
INSERT INTO dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT          AS date_id,
    d                                     AS full_date,
    EXTRACT(YEAR FROM d)::SMALLINT        AS year,
    EXTRACT(QUARTER FROM d)::SMALLINT     AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)::TEXT || ' ' || EXTRACT(YEAR FROM d)::TEXT AS quarter_str,
    EXTRACT(MONTH FROM d)::SMALLINT       AS month_num,
    TO_CHAR(d, 'Month')                   AS month_name,
    EXTRACT(WEEK FROM d)::SMALLINT        AS week_num,
    EXTRACT(DOW FROM d)::SMALLINT         AS day_of_week,
    EXTRACT(DOW FROM d) IN (0, 6)         AS is_weekend
FROM generate_series('2022-01-01'::DATE, '2026-12-31'::DATE, '1 day'::INTERVAL) AS d;

-- ── DIMENSION: Input Types ────────────────────────────────────────────────────
CREATE TABLE dim_input_type (
    input_id    SERIAL PRIMARY KEY,
    input_code  VARCHAR(10) NOT NULL UNIQUE,
    input_name  VARCHAR(80) NOT NULL,
    unit        VARCHAR(20),
    category    VARCHAR(40)   -- Fertilizer / Agrochemical / Labour / Seed
);

INSERT INTO dim_input_type (input_code, input_name, unit, category)
VALUES
    ('NPK',    'NPK 20-10-10 Fertilizer',    'kg',       'Fertilizer'),
    ('UREA',   'Urea Fertilizer',             'kg',       'Fertilizer'),
    ('HERB',   'Herbicide (Glyphosate)',       'litres',   'Agrochemical'),
    ('FUNG',   'Fungicide (Copper-based)',     'litres',   'Agrochemical'),
    ('SEED',   'Certified Seedlings/Seeds',   'units',    'Seed'),
    ('LAB',    'Farm Labour',                  'man-days', 'Labour'),
    ('IRR',    'Irrigation Water',             'cubic-m',  'Resource');

-- ── FACT: Yield Records ───────────────────────────────────────────────────────
CREATE TABLE fact_yield (
    yield_id            BIGSERIAL PRIMARY KEY,
    date_id             INTEGER NOT NULL REFERENCES dim_date(date_id),
    farm_id             INTEGER NOT NULL REFERENCES dim_farm(farm_id),
    crop_id             INTEGER NOT NULL REFERENCES dim_crop(crop_id),
    period_type         VARCHAR(10) NOT NULL CHECK (period_type IN ('DAILY','WEEKLY','MONTHLY')),
    area_planted_ha     NUMERIC(8,2),
    area_harvested_ha   NUMERIC(8,2),
    yield_mt            NUMERIC(10,2) NOT NULL,       -- actual yield
    target_yield_mt     NUMERIC(10,2),                 -- planned target
    yield_per_ha        NUMERIC(8,3) GENERATED ALWAYS AS (
                            CASE WHEN area_harvested_ha > 0
                            THEN yield_mt / area_harvested_ha ELSE NULL END
                        ) STORED,
    attainment_pct      NUMERIC(6,2) GENERATED ALWAYS AS (
                            CASE WHEN target_yield_mt > 0
                            THEN (yield_mt / target_yield_mt) * 100 ELSE NULL END
                        ) STORED,
    rainfall_mm         NUMERIC(7,2),
    avg_temp_c          NUMERIC(5,2),
    data_source         VARCHAR(40),                   -- e.g. 'field_app', 'manual_entry'
    is_verified         BOOLEAN DEFAULT FALSE,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ── FACT: Input Usage ─────────────────────────────────────────────────────────
CREATE TABLE fact_inputs (
    input_usage_id      BIGSERIAL PRIMARY KEY,
    date_id             INTEGER NOT NULL REFERENCES dim_date(date_id),
    farm_id             INTEGER NOT NULL REFERENCES dim_farm(farm_id),
    crop_id             INTEGER NOT NULL REFERENCES dim_crop(crop_id),
    input_id            INTEGER NOT NULL REFERENCES dim_input_type(input_id),
    planned_qty         NUMERIC(12,2),
    actual_qty          NUMERIC(12,2),
    unit_cost_ngn       NUMERIC(10,2),
    total_cost_ngn      NUMERIC(14,2) GENERATED ALWAYS AS (actual_qty * unit_cost_ngn) STORED,
    utilisation_pct     NUMERIC(6,2) GENERATED ALWAYS AS (
                            CASE WHEN planned_qty > 0
                            THEN (actual_qty / planned_qty) * 100 ELSE NULL END
                        ) STORED,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXES for query performance ─────────────────────────────────────────────
CREATE INDEX idx_yield_date    ON fact_yield(date_id);
CREATE INDEX idx_yield_farm    ON fact_yield(farm_id);
CREATE INDEX idx_yield_crop    ON fact_yield(crop_id);
CREATE INDEX idx_yield_period  ON fact_yield(period_type, date_id);
CREATE INDEX idx_inputs_date   ON fact_inputs(date_id);
CREATE INDEX idx_inputs_farm   ON fact_inputs(farm_id);


-- =========================================================================
-- SECTION 2: DATA GOVERNANCE VIEWS
-- =========================================================================

-- ── View: Clean monthly yield with all dimensions resolved ───────────────────
CREATE OR REPLACE VIEW vw_monthly_yield AS
SELECT
    dd.full_date::DATE                          AS report_month,
    dd.year,
    dd.quarter_str,
    df.farm_code,
    df.farm_name,
    df.state,
    dc.crop_name,
    dc.crop_type,
    fy.area_planted_ha,
    fy.area_harvested_ha,
    fy.yield_mt,
    fy.target_yield_mt,
    fy.yield_per_ha,
    ROUND(fy.attainment_pct, 1)                AS attainment_pct,
    fy.rainfall_mm,
    fy.is_verified,
    CASE
        WHEN fy.attainment_pct >= 95 THEN 'On Track'
        WHEN fy.attainment_pct >= 80 THEN 'At Risk'
        ELSE 'Below Target'
    END                                         AS performance_flag,
    fy.data_source
FROM fact_yield fy
JOIN dim_date    dd ON fy.date_id  = dd.date_id
JOIN dim_farm    df ON fy.farm_id  = df.farm_id
JOIN dim_crop    dc ON fy.crop_id  = dc.crop_id
WHERE fy.period_type = 'MONTHLY';

-- ── View: Input utilisation summary ──────────────────────────────────────────
CREATE OR REPLACE VIEW vw_input_utilisation AS
SELECT
    dd.year,
    dd.quarter_str,
    df.farm_name,
    dc.crop_name,
    dit.input_name,
    dit.category                                AS input_category,
    dit.unit,
    SUM(fi.planned_qty)                         AS total_planned,
    SUM(fi.actual_qty)                          AS total_actual,
    ROUND(SUM(fi.actual_qty) / NULLIF(SUM(fi.planned_qty),0) * 100, 1) AS utilisation_pct,
    SUM(fi.total_cost_ngn)                      AS total_cost_ngn
FROM fact_inputs fi
JOIN dim_date      dd  ON fi.date_id  = dd.date_id
JOIN dim_farm      df  ON fi.farm_id  = df.farm_id
JOIN dim_crop      dc  ON fi.crop_id  = dc.crop_id
JOIN dim_input_type dit ON fi.input_id = dit.input_id
GROUP BY dd.year, dd.quarter_str, df.farm_name, dc.crop_name, dit.input_name, dit.category, dit.unit;


-- =========================================================================
-- SECTION 3: ANALYTICAL QUERIES — BI & REPORTING USE CASES
-- =========================================================================

-- ── Query 1: Quarterly KPI scorecard (for Power BI table visual) ──────────────
-- Returns one row per farm per quarter with key metrics consolidated
SELECT
    year,
    quarter_str,
    farm_name,
    state,
    crop_name,
    COUNT(*)                                    AS months_reported,
    ROUND(SUM(yield_mt), 0)                     AS total_yield_mt,
    ROUND(SUM(target_yield_mt), 0)              AS total_target_mt,
    ROUND(AVG(yield_per_ha), 2)                 AS avg_yield_per_ha,
    ROUND(SUM(yield_mt) / NULLIF(SUM(target_yield_mt),0) * 100, 1) AS quarterly_attainment_pct,
    ROUND(AVG(rainfall_mm), 1)                  AS avg_rainfall_mm,
    MAX(CASE WHEN performance_flag = 'Below Target' THEN 1 ELSE 0 END) AS had_underperformance,
    STRING_AGG(DISTINCT performance_flag, ' / ' ORDER BY performance_flag) AS status_flags
FROM vw_monthly_yield
GROUP BY year, quarter_str, farm_name, state, crop_name
ORDER BY year, quarter_str, farm_name;


-- ── Query 2: Month-over-month yield trend (for line chart) ───────────────────
SELECT
    report_month,
    farm_name,
    crop_name,
    yield_mt,
    LAG(yield_mt) OVER (PARTITION BY farm_name ORDER BY report_month)     AS prev_month_yield,
    ROUND(
        (yield_mt - LAG(yield_mt) OVER (PARTITION BY farm_name ORDER BY report_month))
        / NULLIF(LAG(yield_mt) OVER (PARTITION BY farm_name ORDER BY report_month), 0) * 100,
    2)                                          AS mom_change_pct,
    AVG(yield_mt) OVER (
        PARTITION BY farm_name
        ORDER BY report_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )                                           AS rolling_3m_avg,
    SUM(yield_mt) OVER (
        PARTITION BY farm_name, EXTRACT(YEAR FROM report_month)
        ORDER BY report_month
    )                                           AS ytd_yield_mt
FROM vw_monthly_yield
ORDER BY farm_name, report_month;


-- ── Query 3: Cross-subsidiary performance ranking ──────────────────────────────
-- Ranks farms by attainment each quarter to identify leaders and laggards
WITH quarterly_perf AS (
    SELECT
        year,
        quarter_str,
        farm_name,
        crop_name,
        ROUND(SUM(yield_mt) / NULLIF(SUM(target_yield_mt),0) * 100, 1) AS attainment_pct,
        ROUND(SUM(yield_mt), 0)  AS total_yield_mt
    FROM vw_monthly_yield
    GROUP BY year, quarter_str, farm_name, crop_name
)
SELECT
    year,
    quarter_str,
    RANK() OVER (PARTITION BY year, quarter_str ORDER BY attainment_pct DESC) AS rank_position,
    farm_name,
    crop_name,
    attainment_pct,
    total_yield_mt,
    attainment_pct - AVG(attainment_pct) OVER (PARTITION BY year, quarter_str) AS vs_group_avg
FROM quarterly_perf
ORDER BY year, quarter_str, rank_position;


-- ── Query 4: Yield forecasting baseline — rolling average method ───────────────
-- Generates a simple forecast for the next 3 months based on seasonal patterns
WITH monthly_avg AS (
    SELECT
        crop_name,
        EXTRACT(MONTH FROM report_month)::INT  AS calendar_month,
        ROUND(AVG(yield_mt), 1)                AS historical_avg_yield,
        ROUND(STDDEV(yield_mt), 1)             AS yield_std_dev
    FROM vw_monthly_yield
    GROUP BY crop_name, EXTRACT(MONTH FROM report_month)
),
latest_year_factor AS (
    SELECT
        crop_name,
        ROUND(SUM(CASE WHEN year = EXTRACT(YEAR FROM NOW()) THEN yield_mt ELSE 0 END)
            / NULLIF(SUM(CASE WHEN year = EXTRACT(YEAR FROM NOW())-1 THEN yield_mt ELSE 0 END), 0), 4)
            AS yoy_growth_factor
    FROM vw_monthly_yield
    GROUP BY crop_name
)
SELECT
    ma.crop_name,
    ma.calendar_month,
    TO_CHAR(TO_DATE(ma.calendar_month::TEXT, 'MM'), 'Month') AS month_name,
    ma.historical_avg_yield,
    ma.yield_std_dev,
    ROUND(ma.historical_avg_yield * COALESCE(lyf.yoy_growth_factor, 1.05), 1) AS forecast_yield,
    ROUND(ma.historical_avg_yield * COALESCE(lyf.yoy_growth_factor, 1.05) - 1.96 * ma.yield_std_dev, 1) AS ci_lower_95,
    ROUND(ma.historical_avg_yield * COALESCE(lyf.yoy_growth_factor, 1.05) + 1.96 * ma.yield_std_dev, 1) AS ci_upper_95
FROM monthly_avg ma
LEFT JOIN latest_year_factor lyf ON ma.crop_name = lyf.crop_name
ORDER BY ma.crop_name, ma.calendar_month;


-- ── Query 5: Data quality & governance audit ──────────────────────────────────
-- Identifies reporting gaps and data integrity issues across subsidiaries
WITH expected_months AS (
    SELECT
        df.farm_id, df.farm_name,
        dc.crop_id, dc.crop_name,
        dd.date_id, dd.full_date, dd.year, dd.month_num
    FROM dim_farm df
    CROSS JOIN dim_crop dc
    CROSS JOIN dim_date dd
    WHERE dd.full_date = DATE_TRUNC('month', dd.full_date)  -- first day of each month
      AND dd.year BETWEEN 2023 AND 2025
      AND dc.crop_name IN ('Oil Palm', 'Maize', 'Cassava')
      AND df.is_active = TRUE
),
reported AS (
    SELECT
        farm_id, crop_id, date_id,
        is_verified,
        yield_mt
    FROM fact_yield
    WHERE period_type = 'MONTHLY'
)
SELECT
    em.farm_name,
    em.crop_name,
    COUNT(*)                                                        AS expected_records,
    COUNT(r.date_id)                                                AS records_submitted,
    COUNT(*) - COUNT(r.date_id)                                     AS missing_records,
    ROUND(COUNT(r.date_id)::NUMERIC / COUNT(*) * 100, 1)            AS completeness_pct,
    SUM(CASE WHEN r.is_verified = TRUE THEN 1 ELSE 0 END)           AS verified_records,
    SUM(CASE WHEN r.yield_mt IS NOT NULL AND r.yield_mt < 0 THEN 1 ELSE 0 END) AS negative_yield_flags
FROM expected_months em
LEFT JOIN reported r ON em.farm_id = r.farm_id
                    AND em.crop_id = r.crop_id
                    AND em.date_id = r.date_id
GROUP BY em.farm_name, em.crop_name
ORDER BY completeness_pct ASC, em.farm_name;


-- ── Query 6: Input vs yield correlation (for regression in SQL) ────────────────
-- Supports fertilizer planning decisions by quantifying input-yield linkage
SELECT
    dc.crop_name,
    df.state,
    dd.year,
    dd.quarter_str,
    ROUND(AVG(CASE WHEN dit.input_code = 'NPK' THEN fi.actual_qty END), 1) AS avg_npk_kg,
    ROUND(AVG(CASE WHEN dit.input_code = 'LAB' THEN fi.actual_qty END), 1) AS avg_labour_days,
    ROUND(AVG(fy.yield_mt), 1)                                             AS avg_yield_mt,
    ROUND(AVG(fy.rainfall_mm), 1)                                          AS avg_rainfall_mm,
    -- Pearson-equivalent: CORR() function (PostgreSQL built-in)
    ROUND(CORR(fi.actual_qty, fy.yield_mt)::NUMERIC, 4)                    AS input_yield_corr
FROM fact_inputs fi
JOIN fact_yield    fy  ON fi.farm_id = fy.farm_id AND fi.date_id = fy.date_id AND fi.crop_id = fy.crop_id
JOIN dim_date      dd  ON fi.date_id  = dd.date_id
JOIN dim_farm      df  ON fi.farm_id  = df.farm_id
JOIN dim_crop      dc  ON fi.crop_id  = dc.crop_id
JOIN dim_input_type dit ON fi.input_id = dit.input_id
WHERE fy.period_type = 'MONTHLY'
GROUP BY dc.crop_name, df.state, dd.year, dd.quarter_str
ORDER BY dc.crop_name, dd.year, dd.quarter_str;


-- ── Query 7: Stored procedure — automated weekly KPI refresh ──────────────────
-- Upserts latest weekly data into a summary table for dashboard refresh
CREATE OR REPLACE PROCEDURE sp_refresh_weekly_kpi_summary()
LANGUAGE plpgsql AS $$
DECLARE
    v_rows_processed INT := 0;
    v_start_time     TIMESTAMPTZ := NOW();
BEGIN
    -- Create summary table if not exists
    CREATE TABLE IF NOT EXISTS weekly_kpi_summary (
        summary_id      SERIAL PRIMARY KEY,
        week_start_date DATE,
        farm_name       VARCHAR(100),
        crop_name       VARCHAR(60),
        week_yield_mt   NUMERIC(10,2),
        week_target_mt  NUMERIC(10,2),
        attainment_pct  NUMERIC(6,2),
        performance_flag VARCHAR(20),
        refreshed_at    TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (week_start_date, farm_name, crop_name)
    );

    -- Upsert latest week's data
    INSERT INTO weekly_kpi_summary (
        week_start_date, farm_name, crop_name,
        week_yield_mt, week_target_mt, attainment_pct, performance_flag
    )
    SELECT
        DATE_TRUNC('week', dd.full_date)::DATE,
        df.farm_name,
        dc.crop_name,
        ROUND(SUM(fy.yield_mt), 2),
        ROUND(SUM(fy.target_yield_mt), 2),
        ROUND(SUM(fy.yield_mt) / NULLIF(SUM(fy.target_yield_mt), 0) * 100, 1),
        CASE
            WHEN SUM(fy.yield_mt) / NULLIF(SUM(fy.target_yield_mt),0) >= 0.95 THEN 'On Track'
            WHEN SUM(fy.yield_mt) / NULLIF(SUM(fy.target_yield_mt),0) >= 0.80 THEN 'At Risk'
            ELSE 'Below Target'
        END
    FROM fact_yield fy
    JOIN dim_date dd ON fy.date_id = dd.date_id
    JOIN dim_farm df ON fy.farm_id = df.farm_id
    JOIN dim_crop dc ON fy.crop_id = dc.crop_id
    WHERE fy.period_type = 'WEEKLY'
      AND dd.full_date >= NOW() - INTERVAL '14 days'
    GROUP BY DATE_TRUNC('week', dd.full_date), df.farm_name, dc.crop_name
    ON CONFLICT (week_start_date, farm_name, crop_name)
    DO UPDATE SET
        week_yield_mt    = EXCLUDED.week_yield_mt,
        week_target_mt   = EXCLUDED.week_target_mt,
        attainment_pct   = EXCLUDED.attainment_pct,
        performance_flag = EXCLUDED.performance_flag,
        refreshed_at     = NOW();

    GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
    RAISE NOTICE 'KPI refresh complete: % rows processed in %ms',
        v_rows_processed, EXTRACT(EPOCH FROM (NOW() - v_start_time)) * 1000;
END;
$$;


-- =========================================================================
-- SECTION 4: SAMPLE DATA INSERTION (for testing/demo)
-- =========================================================================

INSERT INTO fact_yield (date_id, farm_id, crop_id, period_type, area_planted_ha,
                        area_harvested_ha, yield_mt, target_yield_mt, rainfall_mm,
                        avg_temp_c, data_source, is_verified)
VALUES
    (20250101, 1, 1, 'MONTHLY', 520.00, 515.00, 1642.5, 1560.0, 138.2, 28.4, 'field_app', TRUE),
    (20250101, 2, 2, 'MONTHLY', 460.00, 455.00, 1038.2,  980.0, 142.1, 29.1, 'field_app', TRUE),
    (20250101, 3, 1, 'MONTHLY', 505.00, 500.00, 1700.0, 1560.0, 135.8, 28.7, 'field_app', TRUE),
    (20250101, 4, 3, 'MONTHLY', 430.00, 428.00,  669.4,  720.0, 130.5, 30.2, 'field_app', FALSE),
    (20250201, 1, 1, 'MONTHLY', 520.00, 518.00, 1558.3, 1560.0, 102.4, 28.9, 'field_app', TRUE),
    (20250201, 2, 2, 'MONTHLY', 460.00, 456.00,  992.1,  980.0, 108.7, 29.5, 'field_app', TRUE),
    (20250201, 3, 1, 'MONTHLY', 505.00, 503.00, 1625.0, 1560.0,  99.1, 29.0, 'manual_entry', TRUE),
    (20250201, 4, 3, 'MONTHLY', 430.00, 425.00,  631.8,  720.0, 110.2, 30.8, 'field_app', FALSE);

-- =========================================================================
-- END OF SCRIPT
-- =========================================================================
-- Usage:
--   psql -U agro_user -d agro_db -f agricultural_data_warehouse.sql
--   CALL sp_refresh_weekly_kpi_summary();
--   SELECT * FROM vw_monthly_yield WHERE year = 2025;
-- =========================================================================
