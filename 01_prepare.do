/*==============================================================================
  01_prepare.do

  Step 2 of 2.

  Loads the patched EU-SILC cross-section produced by 00_build_hhtype.do,
  merges the household-type mapping (hhtype), filters to the population aged
  65+, and creates the variables used in the analysis: age class, sex,
  marital status (4 categories), demographic cells, education (3 categories)
  and housing tenure (owner/renter).

  Input:  $dataout/eusilc_2023_full_fixed.dta    full sample, RX020 patched
          $dataout/hhtype_by_hh.dta              household-type mapping
  Output: $dataout/eusilc_65plus_${year}.dta     analysis sample

  EU-SILC variable names (renamed inline) are read from globals that must be
  defined before running (see README): $age_var, $sex_var, $marital,
  $weight, $pov_var, plus the path global $dataout and the wave $year.
==============================================================================*/

*===============================================================================
* 1. LOAD DATA
*===============================================================================

use "$dataout/eusilc_${year}_full_fixed.dta", clear

* Country code: the variable may be delivered as "country" or "DB020"
cap ren COUNTRY country
cap ren DB020 country
cap confirm string variable country
if _rc {
    * country is numeric, convert to string
    decode country, gen(country_str)
    drop country
    rename country_str country
}

*===============================================================================
* 2. MERGE HHTYPE (household-level, before the 65+ filter)
*===============================================================================

merge m:1 country HH_ID using "$dataout/hhtype_by_hh.dta", ///
    keep(master match) ///
    keepusing(hhtype hhtype4 hh_n hh_has_couple hh_n_minors hh_n_adult_children) ///
    nogen

*===============================================================================
* 3. FILTER 65+ AND CONSTRUCT ANALYSIS VARIABLES
*===============================================================================

keep if $age_var >= 65

ren $pov_var   poor        // 1=at risk of poverty
ren $weight    pw          // personal weight
ren $age_var   age
ren $sex_var   sex         // 1=M, 2=F
ren $marital   marital     // 1=never married, 2=married, 3=separated, 4=widowed, 5=divorced

* Age class
gen byte age_class = .
replace age_class = 1 if age >= 65 & age <= 69
replace age_class = 2 if age >= 70 & age <= 74
replace age_class = 3 if age >= 75 & age <= 79
replace age_class = 4 if age >= 80
label define age_class_lbl 1 "65-69" 2 "70-74" 3 "75-79" 4 "80+", replace
label values age_class age_class_lbl

* Female indicator
gen byte female = (sex == 2) if !missing(sex)

* Marital status (4 categories)
gen byte mar = .
replace mar = 1 if marital == 2                          // married
replace mar = 2 if marital == 1                          // never married
replace mar = 3 if marital == 3 | marital == 5           // separated/divorced
replace mar = 4 if marital == 4                          // widowed
label define mar_lbl 1 "Married" 2 "Never married" 3 "Separated/divorced" 4 "Widowed", replace
label values mar mar_lbl

*-------------------------------------------------------------------------------
* 3b. EDUCATION AND TENURE — built defensively.
*     If the source EU-SILC variable is absent, the derived variable is left
*     missing and a warning is printed. The coding of PE040/PE041 (ISCED) and
*     HH020 (tenure) follows the EU-SILC 2023 release.
*-------------------------------------------------------------------------------
* Education, 3 categories (low <= lower-sec / medium upper-sec / high tertiary)
local edu_src ""
capture confirm variable PE041
if !_rc local edu_src "PE041"
if "`edu_src'" == "" {
    capture confirm variable PE040
    if !_rc local edu_src "PE040"
}
gen byte edu3 = .
if "`edu_src'" != "" {
    * The education variable mixes 1-digit (0-8) and 3-digit ISCED-2011 codes
    * (100..800). All codes are brought to the 1-digit ISCED level: codes >= 100
    * are divided by 100.
    tempvar isced
    gen double `isced' = `edu_src'
    replace `isced' = floor(`isced'/100) if `isced' >= 100
    replace edu3 = 1 if inrange(`isced', 0, 2)             // ISCED 0-2  Low
    replace edu3 = 2 if inrange(`isced', 3, 4)             // ISCED 3-4  Medium
    replace edu3 = 3 if `isced' >= 5 & !missing(`isced')   // ISCED 5-8  High
    label define edu3_lbl 1 "Low" 2 "Medium" 3 "High", replace
    label values edu3 edu3_lbl
    di as txt "edu3 built from `edu_src' (ISCED normalised)."
}
else di as err "WARNING: PE040/PE041 not found; edu3 left missing."

* Tenure (owner vs renter/other) from HH020
gen byte tenure = .
capture confirm variable HH020
if !_rc {
    replace tenure = 1 if HH020 == 1                       // owner
    replace tenure = 2 if inlist(HH020, 2, 3, 4)           // tenant / reduced / free
    label define tenure_lbl 1 "Owner" 2 "Renter/other", replace
    label values tenure tenure_lbl
    di as txt "tenure built from HH020."
}
else di as err "WARNING: HH020 not found; tenure left missing."

* Demographic cells
egen cell_demo = group(age_class female), label
egen cell_full = group(age_class female mar), label

*===============================================================================
* 4. KEEP ANALYSIS VARIABLES AND SAVE
*===============================================================================

keep country pw poor age_class female mar cell_demo cell_full ///
     hhtype hhtype4 hh_n hh_has_couple hh_n_minors hh_n_adult_children ///
     edu3 tenure

* Check the household-type merge
count if missing(hhtype)
if r(N) > 0 {
    di as txt "WARNING: `r(N)' obs 65+ without hhtype (failed merge)"
}

save "$dataout/eusilc_65plus_${year}.dta", replace

di as txt _n "=== eusilc_65plus_${year}.dta saved ==="
