# EU-SILC data preparation

STATA code that prepares the EU-SILC 2023 cross-section (27 EU countries and Norway) and builds an analysis sample of the population aged 65 and over. The repository contains data preparation steps only.

Author: Riccardo Casullo, Sapienza University of Rome.

## Data

**The microdata are not included.** EU-SILC microdata are distributed by Eurostat to research entities under a research contract and cannot be redistributed. Information on access: https://ec.europa.eu/eurostat/web/microdata/european-union-statistics-on-income-and-living-conditions

The code expects the full cross-section (all ages, personal and household variables merged) saved as `C - 2023.dta` in the folder set by `$datain`.

## What the code does

| File | Step |
|---|---|
| `00_build_hhtype.do` | Fills in age (RX020) where a country does not release it, deriving it from year of birth (RB080); builds a household-level classification of living arrangements (6 and 4 categories) from the partner and parent identifiers of each member, with a check that every household is classified |
| `01_prepare.do` | Merges household type onto individuals, keeps the population aged 65+, and builds age classes, marital status, demographic cells, education (from ISCED codes delivered in mixed 1- and 3-digit formats) and housing tenure |

## How to run

The two files run in order: `00_build_hhtype.do`, then `01_prepare.do`. They read paths and variable names from globals that must be defined first, for example:

```stata
global datain   "/path/to/data/raw"
global dataout  "/path/to/data/clean"
global year     2023
global age_var  "RX020"   // age at end of income reference period
global sex_var  "RB090"   // sex (1=M, 2=F)
global marital  "PB190"   // legal marital status
global weight   "RB050"   // personal cross-sectional weight
global pov_var  "HX080"   // at-risk-of-poverty indicator
```

Clean files are written to `$dataout`.
