---
title: "Mos Playground"
---

I was looking for some fun and thought I should try to set up
some postprocessing models to predict some weather quantities
for the wetterturnier.

This repository does only exist to keep track of the code, it
does not mean that I will finish this project in the near future :).

This repository is publicly available under GPL-2 (copyright holder
Reto Stauffer). Feel free to use, adjust, and redistribute the code
snippets as long as you give credit according the GPL-2 rules!

Downloading GFS deterministic data
==================================

The script `GFS_download.py` can be used to download and subset
deterministic GFS (archive) data. Makes use of the `config.conf`
file which defines (section `[paam]`) which parameters should
be downloaded and processed. Stores the data into `data/YYYYmmddHHMM`
as grib2 files (one file for each parameter and forecast step).

The `dates.list` files contains the dates a wetterturnier tournament
took place. The idea is to only download GFS forecasts for these
specific dates (always Friday) such that I can make use of the
observations from the tournament data base and do not have to
find observations somewhere else.

What it does:

* Reading `GFS_config.conf` (if the `--devel` flag is set sequentially
  reading trough (`GFS_config.conf` and `GFS_devel.conf`)
* Given the config: trying to download the deterministic forecasts
  from the nomads https servers (for one specific model run).
    * Check if all grib2 files are existing on local dist. If so, skip this
      one and proceed to the next forecast step.
    * Download inventory (if available)
    * If not available: download grib2 (if available) and create inventory
      (at this point I should make use of the local grib2 file, at the moment
      I just use the inventory ..., requires `wgrib2` to be installed)
    * Parse inventory file, identify the parameters we need
    * Download the segments of the grib2 file we requested for (curl)
    * If subsetting is requested: make spatial subset (required `wgrib2` to
      be installed)
    * If `split_files = True`: split the grib file in parameter-specific grib2
      files (requires `wgrib2` to be installed). This actually only makes sense
      for development purposes, in an operational setting one should download
      one file [optionally subset it], and use this for further processing.

Convert Grib2 to NetCDF
=======================

The script `GFS_convert.py` takes all GFS subset files and combines
them in one single NetCDF file per model initialization. These files
will be used later for the interpolation and whatever comes next.
Does not delete the grib files.


Interpolate GFS
===============

After the grib files have been converted to NetCDF (`GFS_convert.py`)
I am using a NetCDF based bilinear interpolation written in R. 
Please note that this requires the `mospack` (which is also part
of this repository) to be installed.

`GFS_interpolate.R` interpolates all NetCDF files in the `netcdf` folder
which match the expected file name `^GFS_[0-9]{8}_[0-9]{4}_combined.nc$`.
The interpolated and reshaped objects (`zoo`) will be stored in a new
`rds` folder.


OGIMET_synop_parser.py
======================

Downloading and parsing historical synop messages to create the observation
data sets. _Please do use ogimet downloads with care_, ogimet is not a data
provider, even if he has some data API interfaces.

`python OGIMET_synop_parser.py -s <station>` should download the synop files,
stores the downloaded files into the `obs_html` folder, and creates `sqlite3`
databases with the observations (folder `obs_sqlite3`).  Requires, of course,
sqlite3 and the corresponding python package to be installed.


