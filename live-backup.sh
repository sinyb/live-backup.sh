#!/bin/bash

export PATH=/bin:/sbin:/usr/sbin:/usr/bin:/usr/local/bin

FROM=backup@[domain.com]
EMAIL=[recepient@domain.com]

TMPDIR=/DataSSD/images-tmp

if ! [ "${1}" == "start" ] ; then
  # requires argument "start", so it is not run by accident
    echo "Usage $0 start"
    exit 1
fi


backup() {

VM=${1}
LOGFILE=/var/log/backup/${VM}.log
exec >> ${LOGFILE} 2>&1

echo "Start: " `date`

local DISKSPEC
declare -a IMAGES

readarray -t IMAGES  < <(virsh domblklist --domain ${VM} | grep qcow2)

for I in "${IMAGES[@]}" ; do 
    read  DISK IMAGE <<< $I
    NAME=`basename ${IMAGE} .qcow2`
    DIR=`dirname ${IMAGE}`
    DISKSPEC="${DISKSPEC} --diskspec ${DISK},file=${TMPDIR}/${NAME}_backup.qcow2 "
done

echo "${DISKSPEC}"

if ! virsh snapshot-create-as --domain ${VM} --name ${VM}_backup ${DISKSPEC} --disk-only --atomic --quiesce --no-metadata ; then
    echo "ERROR, unable to create snaphot of ${VM}!" | tee >(mail -r ${FROM} -s "Backup ${VM} problem!" -a ${LOGFILE} ${EMAIL})
    return 1
fi

# all images now have "_backup" in name
virsh domblklist --domain ${VM}


for I in "${IMAGES[@]}" ; do 
    read  DISK IMAGE <<< $I
    NAME=`basename ${IMAGE} .qcow2`
    DIR=`dirname ${IMAGE}`

# if XFS is not formatted with "-m reflink=1" then next line won't work !!!
    cp -v --reflink=always ${IMAGE} ${DIR}/backup/${NAME}.$(date +%a).qcow2

    virsh blockcommit --domain ${VM} ${DISK} --active --verbose --pivot &&  rm -v ${TMPDIR}/${NAME}_backup.qcow2
done

# all images are without "_backup" now
if virsh domblklist --domain ${VM} | grep "_backup" ; then
    echo "ERROR backup ${VM}, check logs!" | tee >(mail -r ${FROM} -s "Backup ${VM} problem!" -a ${LOGFILE} ${EMAIL})
else
    echo "${VM} backed up OK" | tee >(mail -r ${FROM} -s "Backup ${VM} OK." -a ${LOGFILE} ${EMAIL})
fi

echo "Finish: " `date`

} # backup()



# main program starts here

for MACHINE in $(virsh list --name); do
    backup ${MACHINE}
done

