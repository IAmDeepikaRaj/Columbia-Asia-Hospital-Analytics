use columbia_asia_hospital;

-- Q15: Top 5 high-revenue doctors with below-average patient counts

WITH DoctorStats AS (
    SELECT
        doctor_name,
        doctor_id,
        COUNT(*) AS patient_count,
        SUM(total_bill) AS total_revenue,
        AVG(total_bill) AS revenue_per_patient
    FROM hospital_analysis
    GROUP BY doctor_name, doctor_id
),

AveragePatients AS (
    SELECT AVG(patient_count) AS avg_patient_count
    FROM DoctorStats
)

SELECT
    ds.doctor_name,
    ds.doctor_id,
    ds.patient_count,
    ROUND(ds.total_revenue, 2) AS total_revenue,
    ROUND(ds.revenue_per_patient, 2) AS revenue_per_patient
FROM DoctorStats ds
CROSS JOIN AveragePatients ap
WHERE ds.patient_count < ap.avg_patient_count
ORDER BY ds.total_revenue DESC
LIMIT 5;

-- Q16: Departments with decreasing average waiting time for three consecutive months

WITH MonthlyWait AS (
    SELECT
        department_referral,
        DATE_FORMAT(visit_datetime, '%Y-%m') AS visit_month,
        ROUND(AVG(patient_waittime), 2) AS avg_wait
    FROM hospital_analysis
    WHERE visit_datetime IS NOT NULL
    GROUP BY
        department_referral,
        DATE_FORMAT(visit_datetime, '%Y-%m')
),

WaitTrend AS (
    SELECT
        department_referral,
        visit_month,
        avg_wait,

        LAG(avg_wait, 1) OVER (
            PARTITION BY department_referral
            ORDER BY visit_month
        ) AS previous_month_wait,

        LAG(avg_wait, 2) OVER (
            PARTITION BY department_referral
            ORDER BY visit_month
        ) AS two_months_ago_wait

    FROM MonthlyWait
)

SELECT
    department_referral,
    visit_month AS ending_month,
    two_months_ago_wait,
    previous_month_wait,
    avg_wait AS current_month_wait

FROM WaitTrend

WHERE two_months_ago_wait > previous_month_wait
  AND previous_month_wait > avg_wait

ORDER BY department_referral, ending_month;


-- Q17: Male-to-Female Patient Ratio for Each Doctor

SELECT
    doctor_name,
    SUM(
        CASE
            WHEN patient_gender = 'M' THEN 1
            ELSE 0
        END
    ) AS male_patients,
    SUM(
        CASE
            WHEN patient_gender = 'F' THEN 1
            ELSE 0
        END
    ) AS female_patients,
    ROUND(
        SUM(CASE WHEN patient_gender = 'M' THEN 1 ELSE 0 END)
        /
        NULLIF(
            SUM(CASE WHEN patient_gender = 'F' THEN 1 ELSE 0 END),
            0
        ),
        2
    ) AS male_female_ratio
FROM hospital_analysis
GROUP BY doctor_name
ORDER BY male_female_ratio DESC;


-- Q18: Average Patient Satisfaction Score by Doctor

SELECT
    doctor_name,
    ROUND(AVG(patient_sat_score), 2)
        AS avg_satisfaction,

    COUNT(patient_sat_score)
        AS satisfaction_responses,

    COUNT(*)
        AS total_patients

FROM hospital_analysis
GROUP BY doctor_name
HAVING COUNT(patient_sat_score) > 0
ORDER BY avg_satisfaction DESC;


SELECT
    doctor_name, COUNT(DISTINCT patient_race) as patient_race_count
FROM hospital_analysis
GROUP BY doctor_name;


-- Q19: Find doctors who have treated patients from different races and calculate the diversity of their patient base. 

WITH RaceCounts AS (
    SELECT
        doctor_name,
        patient_race,
        COUNT(*) AS race_patient_count
    FROM hospital_analysis
    WHERE patient_race IS NOT NULL
    GROUP BY
        doctor_name,
        patient_race
),

DoctorTotals AS (
    SELECT
        doctor_name,
        SUM(race_patient_count) AS total_patients,
        COUNT(*) AS race_categories
    FROM RaceCounts
    GROUP BY doctor_name
),

DiversityScores AS (
    SELECT
        rc.doctor_name,
        dt.total_patients,
        dt.race_categories,
        SUM(
            POWER(
                rc.race_patient_count / dt.total_patients,
                2
            )
        ) AS concentration
    FROM RaceCounts rc
    JOIN DoctorTotals dt
        ON rc.doctor_name = dt.doctor_name
    GROUP BY
        rc.doctor_name,
        dt.total_patients,
        dt.race_categories
)

SELECT
    doctor_name,
    total_patients,
    race_categories,
    ROUND(1 - concentration, 3)
        AS simpson_diversity_index
FROM DiversityScores
ORDER BY simpson_diversity_index DESC;



-- Q20: Male-to-Female Total Bill Ratio by Department

SELECT
    department_referral,

    ROUND(
        SUM(
            CASE
                WHEN patient_gender = 'M'
                THEN total_bill
                ELSE 0
            END
        ), 2
    ) AS male_total_bill,

    ROUND(
        SUM(
            CASE
                WHEN patient_gender = 'F'
                THEN total_bill
                ELSE 0
            END
        ), 2
    ) AS female_total_bill,

    ROUND(
        SUM(
            CASE
                WHEN patient_gender = 'M'
                THEN total_bill
                ELSE 0
            END
        )
        /
        NULLIF(
            SUM(
                CASE
                    WHEN patient_gender = 'F'
                    THEN total_bill
                    ELSE 0
                END
            ),
            0
        ),
        2
    ) AS male_female_bill_ratio
FROM hospital_analysis
GROUP BY department_referral
ORDER BY male_female_bill_ratio DESC;


-- Q21: Check eligible records before updating

SELECT
    COUNT(*) AS eligible_records
FROM hospital_analysis
WHERE department_referral = 'General Practice'
  AND patient_waittime > 30
  AND patient_sat_score IS NOT NULL;
  

-- Create a backup before modifying data

CREATE TABLE hospital_er_backup AS
SELECT *
FROM hospital_er;

-- =====================================================
-- Q21: UPDATE PATIENT SATISFACTION SCORES
-- Type: UPDATE Query
-- Objective:
-- Increase satisfaction scores by 2 points for patients
-- in General Practice with waiting time > 30 minutes.
-- Maximum permitted satisfaction score: 10.
-- =====================================================

UPDATE hospital_er h
JOIN doctor_patients_data d
    ON h.patient_id = d.patient_id
SET h.patient_sat_score =
    LEAST(
        CAST(h.patient_sat_score AS DECIMAL(4,2)) + 2,
        10
    )
WHERE d.department_referral = 'General Practice'
  AND h.patient_waittime > 30
  AND h.patient_sat_score IS NOT NULL
  AND TRIM(h.patient_sat_score) <> '';

-- Expected result from this project:
-- 1,071 records updated.
-- 100 eligible records already had a score of 10.
-- NULL and blank satisfaction values were excluded.
