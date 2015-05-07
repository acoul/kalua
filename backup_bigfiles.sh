#!/bin/sh

SIZE="$1"
DEST="bastian@weimarnetz.de:/mnt/hd/bastian/backups/backup-server-network"

for FILE in $( find /var/www/networks/ -type f -name *.lzma -size +${SIZE:-100M} ); do {
	ls -la "$FILE"
	scp "$FILE" $DEST-$( echo $FILE | cut -d'/' -f5 )-$( basename "$FILE" ) && rm "$FILE"
} done

