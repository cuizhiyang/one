#!/bin/bash
#./get_jdk.sh 9,tar.gz
[ "$(rpm -qa "lynx|wget" |wc -l)" -ne 2 ] && yum clean all && yum install -y lynx wget

if [ -z "$1" ]; then
	jdk_v=8
	jdk_t=rpm
else
	jdk_v=$(echo $1 |egrep -o [6-9])
	jdk_t=$(echo $1 |egrep -o 'rpm|tar.gz|exe')
	[ -z "$jdk_v" ] && jdk_v=8
	[ -z "$jdk_t" ] && jdk_t=rpm
fi

echo "$jdk_v $jdk_t"

jdk_d1=$(lynx -source https://www.oracle.com/technetwork/java/javase/downloads/index.html |egrep -o "\/technetwork\/java/\javase\/downloads\/jdk${jdk_v}-downloads-.+?\.html" |head -1) 

jdk_d2=$(lynx -source https://www.oracle.com/$jdk_d1 |egrep -o "https\:\/\/download.oracle\.com\/otn-pub\/java\/jdk\/[8-9](u[0-9]+|\+).*\/jdk-${jdk_v}.*(-|_)(linux|windows)-(x64|x64_bin).${jdk_t}" |tail -1) 
echo $jdk_d2
echo

[ -n $jdk_d2 ] && wget -c --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" -N $jdk_d2
