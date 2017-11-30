
DROP TABLE IF EXISTS patient_age;
CREATE TEMP TABLE patient_age AS
(
WITH first_admission_time AS
(
  SELECT
      a.hadm_id
      , icu.icustay_id
      , p.subject_id
      , p.dob
      , p.gender
      , MIN (a.admittime) AS first_admittime
      , MIN( ROUND( (cast(admittime as date) - cast(dob as date)) / 365.242,2) ) AS first_admit_age
  FROM mimiciii.patients p
  INNER JOIN mimiciii.admissions a ON (p.subject_id = a.subject_id)
  INNER JOIN mimiciii.icustays icu ON (a.hadm_id = icu.hadm_id)
  GROUP BY a.hadm_id, p.subject_id, p.dob, p.gender,icu.icustay_id
  ORDER BY a.hadm_id
)
SELECT
	hadm_id
    , icustay_id
    , subject_id
    , dob
    , gender
    , first_admittime
    , first_admit_age
    , CASE
        -- all ages > 89 in the database were replaced with 300
        WHEN first_admit_age > 89
            then '>89'
        WHEN first_admit_age >= 14
            THEN 'adult'
        WHEN first_admit_age <= 1
            THEN 'neonate'
        ELSE 'middle'
        END AS age_group
FROM first_admission_time
ORDER BY subject_id 
);

DROP TABLE IF EXISTS adults;
CREATE TEMP TABLE adults AS
(
SELECT * 
FROM patient_age p1 
WHERE p1.age_group = 'adult'
AND p1.icustay_id = (select max(p2.icustay_id) from patient_age p2 where p2.hadm_id = p1.hadm_id)
);

DROP TABLE IF EXISTS training_ids;
CREATE TEMP TABLE training_ids AS
(
SELECT * 
FROM adults
LIMIT 40000
);

/*
DROP TABLE IF EXISTS feats_included;
CREATE TEMP TABLE feats_included AS 
(
select 
d.itemid, count(*)/330712483.0 as proportion
from chartevents cvts 
inner join d_items d ON (cvts.itemid  = d.itemid)
group by d.itemid
order by proportion DESC
limit 100
);
*/

DROP TABLE IF EXISTS feats_included;
CREATE TEMP TABLE feats_included AS
(
select d.itemid, 0.1234 as proportion -- random proportion var assigned so query doesnt need to be altered.
from d_items d
where d.label in ('Heart Rate',
    'Arterial BP [Systolic]','Arterial Blood Pressure systolic',
    'Arterial BP [Diastolic]','Arterial Blood Pressure diastolic',
    'Capillary Refill',
    'ETCO2','EtCO2',
    'FIO2','FiO2',
    'GCS Total',
    'Blood Glucose', 
    'O2 saturation pulseoxymetry', 'SpO2',
    'Temperature F', 
    'Arterial pH','Art.pH',
    'Respiratory Rate'
    )
);


DROP TABLE IF EXISTS feature_table;
CREATE TEMP TABLE feature_table AS 
(
select 
cvts.icustay_id
, tr.first_admit_age
, EXTRACT(HOUR FROM (cvts.charttime - icu.intime)) + 24*EXTRACT(DAY FROM (cvts.charttime - icu.intime)) 
as num_hours
, d.label
, feats.proportion*100 as feature_strength
, COALESCE(valuenum, 0) as amount
from chartevents cvts 
inner join training_ids tr ON (cvts.icustay_id = tr.icustay_id)
inner join icustays icu ON (cvts.icustay_id = icu.icustay_id)
inner join d_items d ON (cvts.itemid = d.itemid)
inner join feats_included feats ON (feats.itemid = cvts.itemid)
);

select * from feature_table 
where amount != 0
;