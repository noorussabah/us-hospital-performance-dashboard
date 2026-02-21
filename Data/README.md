# Data Sources — CMS Hospital Quality Datasets

This project uses publicly available hospital quality and patient experience data published by the **Centers for Medicare & Medicaid Services (CMS)** through the CMS Care Compare program.

All raw CSV files used in this project are stored in this folder for reproducibility and transparency.

---

## Original Data Sources (CMS)

CMS Provider Data Portal:  
https://data.cms.gov/provider-data/search?fulltext=age  

---

### Hospital General Information  
Provides hospital profile information, ownership, services, and overall quality ratings.

- **Dataset page:**  
  https://data.cms.gov/provider-data/dataset/84jm-wiui  
- **File in this folder:**  
  `Hospital_General_Information.csv`

**Key fields used in this project:**
- Facility_ID  
- Facility_Name  
- State, City_Town, County_Parish  
- Hospital_Type  
- Hospital_Ownership  
- Emergency_Services  
- Hospital_Overall_Rating  

---

### HCAHPS — Patient Experience Survey Results  
Hospital Consumer Assessment of Healthcare Providers and Systems (HCAHPS) survey data measuring patient experience.

- **Dataset page:**  
  https://data.cms.gov/provider-data/dataset/xubh-q36u  
- **File in this folder:**  
  `HCAHPS-Hospital.csv`

**Key fields used in this project:**
- Facility_ID  
- HCAHPS_Measure_ID  
- HCAHPS_Question  
- Patient_Survey_Star_Rating  
- Number_of_Completed_Surveys  
- Survey_Response_Rate_Percent  
- Start_Date, End_Date  

---

### Timely & Effective Care — Hospital Operational Performance  
Operational performance measures such as Emergency Department wait times, left-before-being-seen rates, and imaging turnaround times.

- **Dataset page:**  
  https://data.cms.gov/provider-data/dataset/yv7e-xc69  
- **File in this folder:**  
  `Timely_and_Effective_Care-Hospital.csv`

**Key fields used in this project:**
- Facility_ID  
- Condition (e.g., Emergency Department)  
- Measure_ID  
- Measure_Name  
- Score  
- Sample  
- Start_Date, End_Date  

---

## Data Dictionary

The official CMS data dictionary was used to interpret metric definitions and measure logic:

https://data.cms.gov/provider-data/sites/default/files/data_dictionaries/hospital/HOSPITAL_Data_Dictionary.pdf  

This document explains:
- What each measure represents  
- Whether higher or lower values indicate better performance  
- Data availability notes  
- Reporting periods and footnotes  

---

## How This Data Is Used in the Project

The raw CSV files in this folder are ingested into **SQL Server**, where they are:

- Cleaned (trimming, type conversion, null handling)  
- Modeled into:
  - Dimension tables (e.g., hospitals)
  - Fact tables (overall ratings, patient experience, ED performance)
- Transformed into analytics views used by **Power BI dashboards**, including:
  - Hospital quality comparisons  
  - Patient experience vs quality mismatch analysis  
  - Emergency Department operational performance benchmarking  

---

## ⚠️ Notes

- Data is provided “as-is” by CMS and reflects reported values at the time of download.
- Some measures contain “Not Available” values or suppressed results for small sample sizes.
- Emergency Department performance measures are standardized in analysis (percentile-based) to allow fair cross-hospital comparison.

---

## 📌 Citation

If referencing this data elsewhere, please cite:

> Centers for Medicare & Medicaid Services (CMS), Provider Data Catalog — Hospital Quality and Patient Experience Datasets.