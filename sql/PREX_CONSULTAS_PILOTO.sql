-- =========================================================
-- 0) Base y esquema
-- =========================================================
CREATE DATABASE IF NOT EXISTS prex;
USE prex;

-- =========================================================
-- 1) Tablas (moneda local)
-- =========================================================

-- Transacciones
DROP TABLE IF EXISTS fact_txn;
CREATE TABLE fact_txn (
  date DATE,
  country_id VARCHAR(3),
  product VARCHAR(20),
  txn_amount_local DECIMAL(18,2),
  fee_bps INT,
  cost_bps INT,
  topup_fee_fixed DECIMAL(18,2),
  channel VARCHAR(30),
  KEY idx_txn_date_country (date, country_id),
  KEY idx_txn_product (product)
);

-- Dimensiones
DROP TABLE IF EXISTS dim_calendar;
CREATE TABLE dim_calendar (
  month DATE,
  year INT,
  month_num INT,
  PRIMARY KEY (month)
);

DROP TABLE IF EXISTS dim_country;
CREATE TABLE dim_country (
  country_id VARCHAR(3) PRIMARY KEY,
  country_name VARCHAR(50),
  currency VARCHAR(10)
);

DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
  product_id INT PRIMARY KEY,
  product_name VARCHAR(20),
  category VARCHAR(20)
);

-- FX (local por USD)
DROP TABLE IF EXISTS fx_history;
CREATE TABLE fx_history (
  month DATE,                 -- 1er día del mes
  country_id VARCHAR(3),
  fx_rate_usd DECIMAL(18,6),  -- cuántas unidades locales = 1 USD
  KEY idx_fx (country_id, month)
);

-- Marketing (real)
DROP TABLE IF EXISTS fact_marketing_spend;
CREATE TABLE fact_marketing_spend (
  month DATE,
  country_id VARCHAR(3),
  channel VARCHAR(50),
  spend_local DECIMAL(18,2),
  KEY idx_mkt (country_id, month)
);

-- Payroll (real)
DROP TABLE IF EXISTS fact_headcount_payroll;
CREATE TABLE fact_headcount_payroll (
  month DATE,
  country_id VARCHAR(3),
  area VARCHAR(50),
  headcount INT,
  payroll_local DECIMAL(18,2),
  KEY idx_pay (country_id, month)
);

-- Presupuesto (budget)
DROP TABLE IF EXISTS fact_budget;
CREATE TABLE fact_budget (
  month DATE,
  country_id VARCHAR(3),
  product VARCHAR(20),
  revenue_local DECIMAL(18,2),
  cogs_local DECIMAL(18,2),
  opex_local DECIMAL(18,2),
  marketing_local DECIMAL(18,2),
  KEY idx_budget (country_id, month, product)
);

-- =========================================================
-- 2) Fix menor + validaciones
-- =========================================================

-- Fix acentos Perú si hiciera falta (solo si ves 'PerÃº')
UPDATE dim_country
SET country_name = REPLACE(country_name, 'PerÃº', 'Perú')
WHERE country_name LIKE '%PerÃº';

-- Conteo rápido por tabla
SELECT 'fact_txn' AS tabla, COUNT(*) AS filas FROM fact_txn
UNION ALL SELECT 'fact_budget', COUNT(*) FROM fact_budget
UNION ALL SELECT 'fact_headcount_payroll', COUNT(*) FROM fact_headcount_payroll
UNION ALL SELECT 'fact_marketing_spend', COUNT(*) FROM fact_marketing_spend
UNION ALL SELECT 'fx_history', COUNT(*) FROM fx_history
UNION ALL SELECT 'dim_country', COUNT(*) FROM dim_country
UNION ALL SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_calendar', COUNT(*) FROM dim_calendar;

-- =========================================================
-- 3) Vistas en USD (todas con month_date = DATE)
--     NOTA: 1 USD = fx_rate_usd unidades locales  → USD = local / fx
-- =========================================================

-- 3.1 TPV mensual en USD
CREATE OR REPLACE VIEW v_tpv_mensual_usd AS
SELECT
  DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY) AS month_date,  -- DATE (1er día de mes)
  txn.country_id,
  TRIM(txn.product) AS product,
  SUM(txn.txn_amount_local / fx.fx_rate_usd) AS tpv_usd
FROM fact_txn txn
JOIN fx_history fx
  ON fx.country_id = txn.country_id
 AND fx.month      = DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY)
GROUP BY month_date, txn.country_id, TRIM(txn.product);

-- 3.2 Revenue & COGS reales en USD (desde transacciones)
CREATE OR REPLACE VIEW v_revenue_cogs_usd AS
SELECT
  DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY) AS month_date,
  txn.country_id,
  TRIM(txn.product) AS product,
  SUM(
    CASE WHEN TRIM(txn.product) = 'TopUp'
         THEN COALESCE(txn.topup_fee_fixed,0) / fx.fx_rate_usd
         ELSE (txn.txn_amount_local * COALESCE(txn.fee_bps,0)/10000) / fx.fx_rate_usd
    END
  ) AS revenue_usd,
  SUM(
    CASE WHEN TRIM(txn.product) = 'TopUp'
         THEN 0
         ELSE (txn.txn_amount_local * COALESCE(txn.cost_bps,0)/10000) / fx.fx_rate_usd
    END
  ) AS cogs_usd
FROM fact_txn txn
JOIN fx_history fx
  ON fx.country_id = txn.country_id
 AND fx.month      = DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY)
GROUP BY month_date, txn.country_id, TRIM(txn.product);

-- 3.3 Budget en USD (por mes–país–producto)
CREATE OR REPLACE VIEW v_budget_usd AS
SELECT
  b.month AS month_date,                    -- DATE mensual ya normalizado
  b.country_id,
  TRIM(b.product) AS product,
  b.revenue_local   / fx.fx_rate_usd AS revenue_budget_usd,
  b.cogs_local      / fx.fx_rate_usd AS cogs_budget_usd,
  b.opex_local      / fx.fx_rate_usd AS opex_budget_usd,
  b.marketing_local / fx.fx_rate_usd AS marketing_budget_usd
FROM fact_budget b
JOIN fx_history fx
  ON fx.country_id = b.country_id
 AND fx.month      = b.month;

-- 3.4 Marketing real en USD (por canal)
CREATE OR REPLACE VIEW v_marketing_spend_usd AS
SELECT
  ms.month AS month_date,
  ms.country_id,
  ms.channel,
  SUM(ms.spend_local / fx.fx_rate_usd) AS spend_usd
FROM fact_marketing_spend ms
JOIN fx_history fx
  ON fx.country_id = ms.country_id
 AND fx.month      = ms.month
GROUP BY ms.month, ms.country_id, ms.channel;

-- 3.5 Payroll en USD (y headcount)
CREATE OR REPLACE VIEW v_payroll_usd AS
SELECT
  pay.month AS month_date,
  pay.country_id,
  pay.area,
  SUM(pay.headcount) AS headcount_total,
  SUM(pay.payroll_local / fx.fx_rate_usd) AS payroll_usd
FROM fact_headcount_payroll pay
JOIN fx_history fx
  ON fx.country_id = pay.country_id
 AND fx.month      = pay.month
GROUP BY pay.month, pay.country_id, pay.area;

-- 3.6 Budget vs Real en USD (Revenue)
CREATE OR REPLACE VIEW v_budget_vs_real_usd AS
WITH real_rev_usd AS (
  SELECT
    DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY) AS month_date,
    txn.country_id,
    TRIM(txn.product) AS product,
    SUM(
      CASE WHEN TRIM(txn.product)='TopUp'
           THEN COALESCE(txn.topup_fee_fixed,0) / fx.fx_rate_usd
           ELSE (txn.txn_amount_local * COALESCE(txn.fee_bps,0)/10000) / fx.fx_rate_usd
      END
    ) AS revenue_real_usd
  FROM fact_txn txn
  JOIN fx_history fx
    ON fx.country_id = txn.country_id
   AND fx.month      = DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY)
  GROUP BY month_date, txn.country_id, TRIM(txn.product)
)
SELECT
  b.month AS month_date,
  b.country_id,
  TRIM(b.product) AS product,
  (b.revenue_local / fx.fx_rate_usd) AS revenue_budget_usd,
  r.revenue_real_usd,
  (r.revenue_real_usd - (b.revenue_local / fx.fx_rate_usd)) AS delta_revenue_usd,
  ROUND(
    (r.revenue_real_usd - (b.revenue_local / fx.fx_rate_usd))
    / NULLIF((b.revenue_local / fx.fx_rate_usd), 0) * 100, 2
  ) AS delta_revenue_pct
FROM fact_budget b
LEFT JOIN real_rev_usd r
  ON r.month_date = b.month
 AND r.country_id = b.country_id
 AND r.product    = TRIM(b.product)
JOIN fx_history fx
  ON fx.country_id = b.country_id
 AND fx.month      = b.month;

-- 3.7 P&L mensual en USD (Revenue, COGS, OPEX asignado, EBITDA)
CREATE OR REPLACE VIEW v_pnl_mensual_usd AS
WITH
-- Revenue y COGS reales (USD) por mes–país–producto
rev_cogs_usd AS (
  SELECT
    DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY) AS month_date,
    txn.country_id,
    TRIM(txn.product) AS product,
    SUM(
      CASE WHEN TRIM(txn.product)='TopUp'
           THEN COALESCE(txn.topup_fee_fixed,0) / fx.fx_rate_usd
           ELSE (txn.txn_amount_local * COALESCE(txn.fee_bps,0)/10000) / fx.fx_rate_usd
      END
    ) AS revenue_real_usd,
    SUM(
      CASE WHEN TRIM(txn.product)='TopUp'
           THEN 0
           ELSE (txn.txn_amount_local * COALESCE(txn.cost_bps,0)/10000) / fx.fx_rate_usd
      END
    ) AS cogs_real_usd
  FROM fact_txn txn
  JOIN fx_history fx
    ON fx.country_id = txn.country_id
   AND fx.month      = DATE_SUB(txn.date, INTERVAL DAY(txn.date)-1 DAY)
  GROUP BY month_date, txn.country_id, TRIM(txn.product)
),

-- Revenue total país/mes (USD)
rev_country_usd AS (
  SELECT month_date, country_id, SUM(revenue_real_usd) AS revenue_country_usd
  FROM rev_cogs_usd
  GROUP BY month_date, country_id
),

-- Payroll USD por país/mes
payroll_country_usd AS (
  SELECT
    pay.month AS month_date,
    pay.country_id,
    SUM(pay.payroll_local / fx.fx_rate_usd) AS payroll_country_usd
  FROM fact_headcount_payroll pay
  JOIN fx_history fx
    ON fx.country_id = pay.country_id
   AND fx.month      = pay.month
  GROUP BY pay.month, pay.country_id
),

-- Marketing USD por país/mes
mkt_country_usd AS (
  SELECT
    ms.month AS month_date,
    ms.country_id,
    SUM(ms.spend_local / fx.fx_rate_usd) AS marketing_country_usd
  FROM fact_marketing_spend ms
  JOIN fx_history fx
    ON fx.country_id = ms.country_id
   AND fx.month      = ms.month
  GROUP BY ms.month, ms.country_id
),

-- OPEX total USD por país/mes (payroll + marketing)
opex_total_usd AS (
  SELECT
    p.month_date,
    p.country_id,
    COALESCE(p.payroll_country_usd,0) + COALESCE(m.marketing_country_usd,0) AS opex_country_total_usd
  FROM payroll_country_usd p
  LEFT JOIN mkt_country_usd m
    ON m.month_date = p.month_date
   AND m.country_id = p.country_id
)

-- Resultado final: P&L USD por mes–país–producto
SELECT
  r.month_date,
  r.country_id,
  r.product,
  r.revenue_real_usd,
  r.cogs_real_usd,
  (r.revenue_real_usd / NULLIF(rc.revenue_country_usd,0)) AS rev_share,
  ROUND(
    COALESCE(ot.opex_country_total_usd,0) * (r.revenue_real_usd / NULLIF(rc.revenue_country_usd,0))
  , 2) AS opex_asignado_usd,
  ROUND(
    r.revenue_real_usd - r.cogs_real_usd
    - COALESCE(ot.opex_country_total_usd,0) * (r.revenue_real_usd / NULLIF(rc.revenue_country_usd,0))
  , 2) AS ebitda_usd
FROM rev_cogs_usd r
LEFT JOIN rev_country_usd rc
  ON rc.month_date = r.month_date
 AND rc.country_id = r.country_id
LEFT JOIN opex_total_usd ot
  ON ot.month_date = r.month_date
 AND ot.country_id = r.country_id;
