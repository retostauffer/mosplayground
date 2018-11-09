# -------------------------------------------------------------------
# - NAME:        synop-check.sh
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-09
# -------------------------------------------------------------------
# - DESCRIPTION: Just because I am too lazy to grep every time.
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-09, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-09 08:03 on marvin
# -------------------------------------------------------------------


set -u
year=-9
month=-9
day=-9
hour=-9
hours=-9
station=-9

while [ $station -lt 6000 ] || [ $station -gt 12000 ] ; do
    read -p "Station (wmo): " station
done
n=`find obs_html/ogimet_synop_${station}_*.dat 2>/dev/null | wc -l`
if [ $n -eq 0 ] ; then
    printf "Sorry, no files for station \"%d\"\n\n" ${station}
    exit 9
fi


while [ $year -lt 2016 ] || [ $year -gt 2018 ] ; do
    read -p "Year (YYYY):   " year
done
while [ $month -lt 1 ] || [ $month -gt 12 ] ; do
    read -p "Month (mm):    " month
done
while [ $day -lt 1 ] || [ $day -gt 31 ] ; do
    read -p "Day (dd):      " day
done
while [ $hour -lt 0 ] || [ $hour -gt 23 ] ; do
    read -p "Hour (HH):     " hour
done
while [ $hours -lt 1 ] || [ $hours -gt 24 ] ; do
    read -p "Hours (1-24):  " hours
done

date=`date -u -d "${year}-${month}-${day} ${hour}:00"`
let lag=$hour-1
while [ $lag -ge 0 ] ; do
    pat=`date -u -d "${date} ${lag} hours ago" "+%Y,%m,%d,%H"`

    cat obs_html/ogimet_synop_${station}_*.dat | egrep "${pat}"
    let lag=$lag-1
done













