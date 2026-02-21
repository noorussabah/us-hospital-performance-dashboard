# SQL — Data Modeling & Analytics

This folder contains all SQL scripts used to model, transform, and analyze CMS hospital quality data before visualization in Power BI.

The SQL layer is implemented in **Microsoft SQL Server (T-SQL)** and follows a simple star-schema style with dimensions, fact tables, and analytics views.

---

## Files

### `create_tables.sql`  
Creates and populates the core **data model**:

**Dimension tables**
- `dim_hospital` – hospital master data (location, type, ownership, emergency services)
  - Includes grouped fields: `hospital_type_group`, `ownership_group`

**Fact tables**
- `fact_overall_rating` – CMS overall hospital star ratings  
- `fact_patients_rating` – HCAHPS patient experience star ratings  

This script:
- Cleans raw CMS fields (trim, type casting, null handling)
- Enforces primary keys and foreign keys
- Adds convenience groupings for analytics

---

### `analytics.sql`  
Contains **exploratory and analytical SQL queries** used to answer research questions, including:

- Distribution of hospital star ratings (national & by state)
- Ratings by ownership and hospital type
- Patient experience vs overall hospital quality
- Variation in HCAHPS aspects (standard deviation)
- Emergency Department (ED) performance benchmarking
- State-level and ownership-level ED performance comparisons

These queries were used for:
- Validating data
- Designing metrics
- Prototyping insights before creating Power BI visuals

---

### `views.sql`  
Defines reusable **analytics views** consumed directly by Power BI:

Key views include:
- `vw_avg_rating_by_state`  
- `vw_avg_rating_by_type_ownership`  
- `vw_patient_vs_overall_rating`  
- `vw_hcahps_aspect_variation`  
- `vw_patient_rating_mismatch`  
- `vw_ed_performance_unified`  

These views:
- Standardize business logic
- Provide clean, slicer-ready datasets for dashboards
- Encapsulate complex transformations (percentiles, composites, mismatch flags)

---

## 🔧 How to Use

1. Load raw CMS CSVs into staging tables (`raw_*`)
2. Run `create_tables.sql` to build the data model  
3. Run `views.sql` to create Power BI–ready analytics views  
4. Use `analytics.sql` for validation and ad-hoc analysis  
5. Connect Power BI directly to the SQL views

---

## 🛠️ Tech

- Database: Microsoft SQL Server  
- SQL dialect: T-SQL   
 