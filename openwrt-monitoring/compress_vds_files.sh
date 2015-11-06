#!/bin/sh

# TODO:
# cd /root/backup/ejbw/pbx/; ls -1 | while read FILE; do case "$FILE" in *'01_'*|*'31_'|*'15_'*);;*) rm "$FILE";;esac; done
#
# - log/log schrumpfen
#
# /etc/init.d/apache2 stop
# find /var/www/networks -type f -name meshrdf.txt | while read FILE; do rm $FILE; touch $FILE; chmod 777 $FILE; done
# /etc/init.d/apache2 start
#
#
# vertrauen:
# scp -P 10022 .ssh/id_rsa.pub root@87.171.45.240:/tmp
# auf server:
# cat /tmp/id_rsa.pub >>.ssh/authorized_keys


log()
{
	logger -s "$(date) $0: $1"
}

list_networks()
{
	local pattern1="/var/www/networks/"
	local pattern2="/meshrdf/recent"

	find /var/www/networks/ -name recent |
	 grep "meshrdf/recent"$ |
	  sed -e "s|$pattern1||" -e "s|$pattern2||"
}

free_diskspace()
{
	df -h /dev/xvda1 | tail -n1
}

cleanup_disc()
{
	log "[START] cleanup_disc"
	/etc/init.d/apache2 stop
	rm /var/log/apache2/access.log
	rm /var/log/apache2/error.log
	rm /tmp/write_meshrdf.*

	# see /var/www/scripts/meshrdf_accept.php
	mv '/tmp/monilog.txt' "/var/www/files/openwrt/monilog_$( date +%Y%b%d ).txt"
	touch '/tmp/monilog.txt'
	chmod 777 '/tmp/monilog.txt'
	bzip2 "/var/www/files/openwrt/monilog_$( date +%Y%b%d ).txt"

	/etc/init.d/apache2 start
	log "[READY] cleanup_disc"
}

case "$1" in
	"")
		echo "Usage: $0 <start|check|networkname>"
		echo
		echo "loops over:"
		list_networks
		exit 1
	;;
	start|check)
		LIST_NETWORKS="$( list_networks )"
	;;
	*)
		LIST_NETWORKS="$1"
	;;
esac

cleanup_disc

for NETWORK in $LIST_NETWORKS; do {
	du -sh "/var/www/networks/$NETWORK/vds"

	[ "$1" = "check" ] && continue

	cd "/var/www/networks/$NETWORK/vds" || exit
	BACKUP="backup_vds_$( date +%Y%b%d_%H:%M ).tar.lzma"
	log "[START] working on $NETWORK: $( free_diskspace ) in dir: '$( pwd )'"

	find . -size -500c | fgrep "db_backup.tgz_" |
	 while read -r FILE; do {
		log "deleting too small db-backup: $FILE <500 bytes"
		rm -f "$FILE"
	 } done

	ls -1 ./*.tar | while read -r TAR; do {
		ls -l ./$TAR
		lzma ./$TAR
	} done

	ls -1 backup_vds_$( date +%Y%b%d)* && {
		log "[ERR] backup is from today, do nothing, check: $( pwd )/backup_vds_*"
#		continue
	}

	rm "/tmp/compress_vds_*"
#	rm ../meshrdf/meshrdf.txt

	{
		ls -1 | grep ^"user-"
		ls -1 ./*.$( date +%Y )*
		ls -1 db_backup.tgz_*.2012*
		ls -1 db_backup.tgz_*.2013*
		ls -1 ../log/log.txt
		ls -1 ../media/traffic_*
		ls -1 ../media/map_topology_*
		ls -1 ../registrator/registrator.txt
		ls -1 ../meshrdf/meshrdf-monthquadruple-*
		ls -1 ../meshrdf/meshrdf-year-*
		ls -1 ../meshrdf/recent/*.wifiscan
		ls -1 ../meshrdf/meshrdf.txt
		find /var/www/networks/spbansin/media/pix_old -type f
		find /var/www/networks/spbansin/media/webcam_movies/ -type f
	} >"/tmp/compress_vds_$$"

	ls -1 backup_vds_$( date +%Y%b%d )* || {
		tar -T /tmp/compress_vds_$$ --lzma -cf ./$BACKUP
		ls -l ./$BACKUP
	}

	log "[DELETING]"
	sed -i 's/^/rm /' "/tmp/compress_vds_$$"
	.  "/tmp/compress_vds_$$"
	rm "/tmp/compress_vds_$$"

	log "[READY] $NETWORK: $( free_diskspace )"
} done
