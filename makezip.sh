#!/bin/bash
# makes zip archive for distribution, first argument is version number
#
# example: to make lentickle1.0.zip:
# ./makezip.sh 1.0

packagename="lentickle"
pwd=`pwd`
thisdir=`basename $pwd`

cd ..

find $thisdir -not -name "makezip.sh" -not -wholename "*/.git*" -not -name "${packagename}*.zip" |zip ${thisdir}/${packagename}${1}.zip -@

