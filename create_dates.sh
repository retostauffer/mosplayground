
START="20190115"
END=`date -u "+%Y%m%d" -d "1 days ago"`

LOOPDATE=$START
while [ $LOOPDATE -le $END ] ; do

   tmp=`date -u "+%Y-%m-%d" -d "${LOOPDATE}"`
   echo $tmp

   LOOPDATE=`date -u "+%Y%m%d" -d "${LOOPDATE} +1 day"`
done

