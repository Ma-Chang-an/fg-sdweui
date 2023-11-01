#!/bin/bash

set -Eeuox pipefail

count=0
while [ $count -lt 30 ]
do
    if [ -d "/mnt/auto" ]
    then
        echo "Directory /mnt/auto exists. Exiting."
        exit 0
    else
        echo "Directory /mnt/auto does not exist. Waiting for 10 seconds."
        sleep 10
        count=$((count+1))
    fi
done

echo "Directory /mnt/auto does not exist. Maximum wait time exceeded."

