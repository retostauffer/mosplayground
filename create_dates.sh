
START="20161201"
END=`date -u "+%Y%m%d" -d "1 days ago"`

echo $START
echo $END

LOOPDATE=$START
while [ $LOOPDATE -le $END ] ; do

   tmp=`date -u "+%Y-%m-%d" -d "${LOOPDATE}"`
   echo $tmp

   LOOPDATE=`date -u "+%Y%m%d" -d "${LOOPDATE} +1 day"`
done

