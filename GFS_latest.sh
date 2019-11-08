#!/bin/bash
# -------------------------------------------------------------------
# - NAME:        GFS_latest.sh
# - AUTHOR:      Reto Stauffer
# - DATE:        2019-08-05
# -------------------------------------------------------------------
# - DESCRIPTION: Download latest forecast if possible.
# -------------------------------------------------------------------
# - EDITORIAL:   2019-08-05, RS: Created file on pc24-c707.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2019-11-08 10:09 on pc24-c707
# -------------------------------------------------------------------


date1=`date "+%Y-%m-%d" -d "1days ago"`
date2=`date "+%Y-%m-%d" -d "2days ago"`


printf "\n--------------------------------------\n"
printf "* TRYING TO DOWNLOAD %s\n" "${date1}"
python GFS_download.py -r 0 -d ${date1}

printf "\n--------------------------------------\n"
printf "* TRYING TO DOWNLOAD %s\n" "${date2}"
python GFS_download.py -r 0 -d ${date2}
