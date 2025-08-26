
# 🚀 Proyecto PREX – Simulación de FP&A en una Fintech

## 📌 Propósito
Este proyecto busca **simular un caso real de Planificación y Análisis Financiero (FP&A)** en una fintech regional.  
El objetivo es **recrear el ciclo completo de análisis financiero** que realizaría un equipo de *Strategic & Financial Planning*:

1. **Generar datos** (transacciones, FX, marketing, payroll, presupuesto).  
2. **Modelarlos en SQL** con reglas de negocio auditables.  
3. **Analizarlos en Power BI** con KPIs, Budget vs Real y estados de resultados (P&L).  

De esta forma, se logra mostrar cómo se construye un **pipeline end-to-end** para dar soporte a la toma de decisiones estratégicas en una empresa tecnológica.

---

## 🏗️ Arquitectura del Proyecto

### 1. Simulación de Datos (Python)
- **`01_generate_data.ipynb`** → genera transacciones (`fact_txn`) en moneda local por país y producto.  
- **`02_generate_support_tables.ipynb`** → crea dimensiones (`dim_*`), historial FX, gastos de marketing, headcount & payroll, y presupuesto (`fact_budget`).  

### 2. Modelo SQL (MySQL)
- **Tablas base**: hechos (`fact_*`) y dimensiones (`dim_*`).  
- **Vistas en USD** para análisis financiero:
  - `v_tpv_mensual_usd` → TPV mensual.  
  - `v_revenue_cogs_usd` → Revenue & COGS reales.  
  - `v_budget_usd` → Budget convertido a USD.  
  - `v_budget_vs_real_usd` → comparación Budget vs Real.  
  - `v_pnl_mensual_usd` → P&L mensual con Revenue, COGS, OPEX y EBITDA.  

### 3. Visualizaciones (Power BI)
- **Página 1 – Resumen Ejecutivo:** KPIs globales, Revenue por país/producto, evolución mensual.  
- **Página 2 – P&L Detalle:** matriz Revenue → COGS → GP → OPEX → EBITDA, línea temporal, breakdown de OPEX.  
- **Página 3 – Budget vs Real:** comparación de Revenue y OPEX presupuestados vs reales, con Δ y %.  

---

## 📊 KPIs calculados
- **TPV (Total Payment Volume):** volumen total transaccionado.  
- **Revenue:** ingresos (fee fijo para TopUp o variable en basis points).  
- **COGS:** costos directos (bps, TopUp=0).  
- **Gross Profit** = Revenue – COGS.  
- **OPEX:** gastos operativos (Payroll + Marketing, asignados por participación de revenue).  
- **EBITDA:** Gross Profit – OPEX.  
- **Budget vs Real:** diferencia absoluta y relativa entre lo real y lo presupuestado.  

---

## 📘 Glosario de conceptos clave
- **TPV:** total de pagos procesados.  
- **Revenue:** ingresos del negocio.  
- **COGS (Cost of Goods Sold):** costos directos de operación.  
- **OPEX (Operating Expenses):** gastos operativos (payroll y marketing).  
- **EBITDA:** indicador de rentabilidad operativa.  
- **bps (basis points):** 1 bps = 0,01% (÷10.000).  
- **TopUp:** recarga de saldo (fee fijo).  
- **rev_share:** share de revenue de un producto dentro de un país/mes.  

---

