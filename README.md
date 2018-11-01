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

