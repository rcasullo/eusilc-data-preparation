/*==============================================================================
  00_build_hhtype.do
  
  Step 1 of 2.
  
  Reads the raw EU-SILC cross-section, applies a country-specific fix to the
  age variable RX020 (Germany 2023+ does not provide RX020 directly; it is
  derived from RB080 = year of birth), and produces two outputs:
  
    1. eusilc_2023_full_fixed.dta — full sample with RX020 patched, used as
       input by 01_prepare.do
    2. hhtype_by_hh.dta — household-level mapping (one row per (country, HH_ID))
       with hhtype, hhtype4, and household composition aggregates, merged onto
       the analysis sample by 01_prepare.do
  
  hhtype is a 6-category classification of household composition; hhtype4 is
  a coarser 4-category version. Both are constant within
  hh_uid. Auxiliary aggregates retained: hh_n, hh_n_adults, hh_n_minors,
  hh_n_65plus, hh_has_couple, hh_n_adult_children, hh_n_minor_children.
  
  RX020 fix details:
  - For Germany (and any other country where RX020 is missing) RX020 is
    computed as ($year - 1) - RB080. The reference period of wave $year is
    the calendar year $year - 1.
  - Negative RX020 values (children born after the reference period) are
    recoded as missing.

  Country recoding:
  - country is delivered as a numeric variable with value labels
    (ISO-2 codes). For consistency across all derived files in the
    pipeline, it is converted to a str2 variable immediately after
    loading the raw file. The raw file in $datain/ is not modified.
  
  Input:  $datain/C - $year.dta            full SILC cross-section, all ages
  Output: $dataout/eusilc_2023_full_fixed.dta
          $dataout/hhtype_by_hh.dta
  
  The globals $datain, $dataout and $year must be defined before running
  (see README).
==============================================================================*/

*===============================================================================
* 1. LOAD RAW DATA AND PATCH RX020
*===============================================================================

use "$datain/C - $year.dta", clear

* Sanity checks on inputs
foreach v in country HH_ID PERS_ID RB080 {
    capture confirm variable `v'
    if _rc {
        di as err "ERROR: variable `v' not found in raw file"
        exit 111
    }
}
* Standardize country to str2 for consistency across the pipeline.
* The raw file in $datain/ is not modified — only the in-memory copy.
capture confirm string variable country
if _rc {
    decode country, gen(country_str)
    drop country
    rename country_str country
    replace country = substr(country, 1, 2)
    compress country
}

* Diagnostics before patching
quietly count if missing(RX020)
local n_miss_pre = r(N)
di as txt _n "RX020 missing before patch: " %9.0fc `n_miss_pre'

* Patch: fill missing RX020 from RB080 (year of birth)
* Reference period of wave $year is calendar year ($year - 1)
replace RX020 = ($year - 1) - RB080 if missing(RX020) & !missing(RB080)

* Recode negative RX020 (children born after reference period) as missing
replace RX020 = . if RX020 < 0

* Diagnostics after patching
quietly count if missing(RX020)
di as txt "RX020 missing after patch:  " %9.0fc r(N)

label variable RX020 "Age at end of income reference period (patched)"

*===============================================================================
* 2. SAVE FIXED FULL FILE (used as input by 01_prepare.do)
*===============================================================================

save "$dataout/eusilc_${year}_full_fixed.dta", replace
di as txt _n "=== eusilc_${year}_full_fixed.dta saved ==="

*===============================================================================
* 3. PROGRAM — build hhtype on the currently loaded file
*===============================================================================

capture program drop build_hhtype
program define build_hhtype

    * Age and base flags
    gen age_ind = RX020
    gen byte is_adult = (age_ind >= 18) if !missing(age_ind)
    gen byte is_minor = (age_ind <  18) if !missing(age_ind)
    gen byte is_65p   = (age_ind >= 65) if !missing(age_ind)

    * Partner flag
    capture confirm variable RB240
    if _rc {
        di as err "ERROR: variable RB240 (partner ID) not found"
        exit 111
    }
    gen byte has_partner_ind = !missing(RB240) & RB240 != 0

    * Unique household ID (avoid cross-country collisions)
    egen hh_uid = group(country HH_ID)

    * Household-level aggregates
    bysort hh_uid: gen hh_n = _N
    bysort hh_uid: egen hh_n_adults = total(is_adult)
    bysort hh_uid: egen hh_n_minors = total(is_minor)
    bysort hh_uid: egen hh_n_65plus = total(is_65p)
    bysort hh_uid: egen hh_has_couple = max(has_partner_ind)

    * Children of household members
    foreach v in RB220 RB230 {
        capture confirm variable `v'
        if _rc {
            di as err "ERROR: variable `v' not found"
            exit 111
        }
    }
    gen byte is_child_of_hhmember = (!missing(RB220) & RB220 != 0) | ///
                                     (!missing(RB230) & RB230 != 0)
    bysort hh_uid: egen hh_has_children = max(is_child_of_hhmember)

    gen byte is_adult_child = (is_child_of_hhmember == 1 & is_adult == 1)
    gen byte is_minor_child = (is_child_of_hhmember == 1 & is_minor == 1)
    bysort hh_uid: egen hh_n_adult_children = total(is_adult_child)
    bysort hh_uid: egen hh_n_minor_children = total(is_minor_child)

    *--- hhtype: 6 categories ---
    gen byte hhtype = .
    replace hhtype = 1 if hh_n == 1
    replace hhtype = 2 if hh_n == 2 & hh_has_couple == 1 & ///
                          hh_n_adults == 2 & hh_n_minors == 0
    replace hhtype = 5 if hh_n >= 3 & hh_n_minors >= 1 & missing(hhtype)
    replace hhtype = 3 if hh_has_couple == 1 & hh_n_adult_children >= 1 & ///
                          hh_n_minors == 0 & missing(hhtype)
    replace hhtype = 4 if hh_has_couple == 0 & hh_n_adult_children >= 1 & ///
                          hh_n_minors == 0 & missing(hhtype)
    replace hhtype = 6 if missing(hhtype)

    label define hhtype_lbl ///
        1 "Lives alone" ///
        2 "Couple only" ///
        3 "Couple + adult children" ///
        4 "Single + adult children" ///
        5 "Multigenerational (with minors)" ///
        6 "Other", replace
    label values hhtype hhtype_lbl
    label variable hhtype "Household type (6 cat)"

    *--- hhtype4: 4 categories (coarser) ---
    gen byte hhtype4 = .
    replace hhtype4 = 1 if hh_n == 1
    replace hhtype4 = 2 if hh_n == 2 & hh_has_couple == 1
    replace hhtype4 = 3 if hh_n >= 2 & hh_has_couple == 1 & missing(hhtype4)
    replace hhtype4 = 4 if hh_n >= 2 & hh_has_couple == 0 & missing(hhtype4)

    label define hhtype4_lbl ///
        1 "Alone" 2 "Couple only" ///
        3 "Couple + others" 4 "No partner + others", replace
    label values hhtype4 hhtype4_lbl
    label variable hhtype4 "Household type (4 cat)"

    * Sanity check: every household must be classified
    quietly count if missing(hhtype)
    assert r(N) == 0
end

*===============================================================================
* 4. BUILD HHTYPE AND SAVE HOUSEHOLD-LEVEL MAPPING
*===============================================================================

build_hhtype

gen silc_wave = $year

keep hh_uid country HH_ID silc_wave hhtype hhtype4 ///
     hh_n hh_n_adults hh_n_minors hh_n_65plus ///
     hh_has_couple hh_n_adult_children hh_n_minor_children

bysort hh_uid: keep if _n == 1

di as txt _n "--- hhtype x country (all households) ---"
tab hhtype country, col nofreq

di as txt _n "--- Distribution of hh_n ---"
sum hh_n, detail

save "$dataout/hhtype_by_hh.dta", replace

di as txt _n "=== hhtype_by_hh.dta saved ==="