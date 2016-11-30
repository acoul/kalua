#!/bin/sh

OPTION="$1"		# e.g. 'cache' or 'func:$name arg1 arg2'
WISH_NETWORK="$2"

TMPDIR='/var/run/kalua'
[ -d "$TMPDIR" ] || {
	mkdir -p "$TMPDIR"
	chmod -R 777 "$TMPDIR"
}

log()
{
	local MESSAGE="$1"

	MESSAGE="$( date ) $0: $MESSAGE"

	echo "$MESSAGE"
	# /usr/bin/logger -s "$MESSAGE"
}

uptime_in_seconds()
{
	cut -d'.' -f1 /proc/uptime
}

list_networks()
{
	local dir file

	for dir in /var/www/networks/*; do {
		# allow symlinks
		for file in $dir/meshrdf/recent/*; do break; done
		[ -e "$file" ] && basename "$dir"
	} done
}

htmlout_error_summary()
{
	local LIST="$1"
	local FILE_SUMMARY_TEMP FILE_SUMMARY NET NETWORK
	local LINENO_FIRST_ENDING_TR_TAG LINENO_JS_START LINENO_JS_ENDING
	local HTML_INDEX LINK FILE_CONTACT_DATA CONTACT_DATA OMIT VERY_OLD

	log "htmlout_error_summary: working"

	FILE_SUMMARY_TEMP="/tmp/summary.html.tmp"
	FILE_SUMMARY="/var/www/networks/error/index.html"

	NET='/var/www/networks/ilm1/meshrdf/recent'	# last build valid network
	NETWORK="$( echo "$NET" | cut -d'/' -f5 )"	# e.g. elephant

#	log "[OK] starting to build summary.html, taking network '$NETWORK' for template NET: '$NET'"
	# writeout table/html-headers MINUS javascript (till first </tr>-tag)
	LINENO_FIRST_ENDING_TR_TAG="$( sed -n '/<\/tr>/{=;q}' "$NET/../../index.html" )"
	LINENO_JS_START="$(  sed -n '/<script/{=;q}'   "$NET/../../index.html" )"
	LINENO_JS_ENDING="$( sed -n '/<\/script/{=;q}' "$NET/../../index.html" )"
	sed -n "1,${LINENO_FIRST_ENDING_TR_TAG}p" "$NET/../../index.html" | sed "${LINENO_JS_START},${LINENO_JS_ENDING}d" >$FILE_SUMMARY_TEMP
	sed -i "s|^<title>.*|<title>error-overview@$( date "+%d.%b'%y-%H:%M" )</title>|" "$FILE_SUMMARY_TEMP"

	for NET in $LIST; do {					# /var/www/networks/ffweimar/meshrdf/recent
		NETWORK="$( echo "$NET" | cut -d'/' -f5 )"	# e.g. elephant
		HTML_INDEX="/var/www/networks/$NETWORK/index.html"

		# TODO: use ignore_network() ?
		case "$NETWORK" in
			dhsylt|elephant|ffweimar*|galerie|tkolleg|ffsundi|artotel|\
			sachsenhausen|versiliawe|liszt28|zumnorde|tuberlin|preskil|\
			versiliaje|gnm|hotello*|marinapark|vivaldi|satama|fparkssee|dhfleesensee|boltenhagendh)
#				log "summary: [OK] omitting network '$NETWORK' for error-summary"
				continue
			;;
		esac

		LINK="http://intercity-vpn.de/networks/$NETWORK"

		FILE_CONTACT_DATA="/var/www/networks/$NETWORK/contact.txt"
		if [ -e "$FILE_CONTACT_DATA" ]; then
			read -r CONTACT_DATA <"$FILE_CONTACT_DATA"
		else
			CONTACT_DATA="bitte eintragen in $FILE_CONTACT_DATA"
		fi
#		log "[OK] including '$NETWORK'-contacts: $CONTACT_DATA"

		fgrep -sq " title='MISS " "$HTML_INDEX" && {
			# header:
			{
				printf '%s' "<tr><td align='left' colspan='25' bgcolor='#81F7F3'><small>"
				printf '%s' "<br></small><big><a href='$LINK' title='$CONTACT_DATA'>$NETWORK</a>"
				echo   "</big></small><br></small></td></tr>"
			} >>"$FILE_SUMMARY_TEMP"

			OMIT='d85d4c9c2fb0'		# leonardo/beach
			VERY_OLD='#8A0829'		# darkviolett = very old nodes - we suppress them (see meshrdf_generate)
			fgrep " title='MISS " "$HTML_INDEX" | fgrep -v "$OMIT" | fgrep -v "$VERY_OLD" >>"$FILE_SUMMARY_TEMP"
		}

	} done

	echo '</table></body></html>' >>"$FILE_SUMMARY_TEMP"
	mv "$FILE_SUMMARY_TEMP" "$FILE_SUMMARY"
#	log "summary: wrote DGB2: $( ls -l "$FILE_SUMMARY" )"

	[ -e "/tmp/lockfile_meshrdf_cache_$$" ] && {
		rm "/tmp/lockfile_meshrdf_cache_$$"
	}

	log '[READY]'
}



# /var/www/networks/fuerstengruft/gruft.html_for_all_dates.sh

build_html_tarball()
{
	log "[OK] build_html_tarball"

	(
	ls -l /var/www/networks/ | grep ^'d' | while read -r LINE; do {
		set -- $LINE
		case "$9" in
			*':'*)
			;;
			*)
				cp /var/www/networks/$9/index.html /var/www/files/cache-$9.html
			;;
		esac
	} done

	cd /var/www/files/ || exit
	tar cjf /var/www/files/all.tar.bz2 cache-*
	tar cJf /var/www/files/all.tar.xz cache-*
	)

	log "[OK] build_html_tarball - READY"
}

optimize_space()
{
	local partition="/dev/xvda1"
	local blocks freemb

	blocks="$( df | sed -n "s#^${partition}[^0-9]*[0-9]*[^0-9]*[0-9]*[^0-9]*\([0-9]*\).*#\1#p" )"
	freemb=$(( ${blocks:-0 } / 1024 ))

	[ $freemb -lt 500 ] && {
		log "removing apache logs"
		/etc/init.d/apache2 stop
		rm /var/log/apache2/access.log
		rm /var/log/apache2/error.log
		/etc/init.d/apache2 start
	}
}

list_meshrdf_files_with_zero_size()
{
	find /var/www/networks -type f -size 0 | fgrep "/recent/"
}

ignore_network()
{
	local network="$1"

	case "$network" in
		zumnorde|artotel|fparkssee|satama|marinapark|ffsundi|ffleipzig|\
		sachsenhausen|hotello-*|olympia|dhsylt|cupandcoffee|elephant|\
		galerie|preskil|tuberlin|vivaldi|boltenhagendh|dhfleesensee)
			log "[OK] ignoring call for '$network'"
			return 0
		;;
		*)
			return 1
		;;
	esac
}

urlencode()					# SENS: converting chars using a fixed table, where we know the URL-encodings
{						#   is: , ; : ? # [ ] / @ + = " ' | ( ) TAB < > ! * { } $ ^ space
	echo "$1" | sed -e 's/,/%2c/g'	\
			-e 's/;/%3b/g'	\
			-e 's/:/%3a/g'	\
			-e 's/?/%3f/g'	\
			-e 's/#/%23/g'	\
			-e 's/\[/%5b/g'	\
			-e 's/\]/%5d/g'	\
			-e 's/\//%2f/g'	\
			-e 's/@/%40/g'	\
			-e 's/+/%2b/g'  \
			-e 's/=/%3d/g'	\
			-e 's/"/%22/g'	\
			-e "s/'/%27/g"	\
			-e "s/|/%7c/g"	\
			-e "s/[(]/%28/g" \
			-e "s/[)]/%29/g" \
			-e "s/	/%09/g"	\
			-e 's/</%3c/g'  \
			-e 's/>/%3e/g'  \
			-e 's/!/%21/g' \
			-e 's/*/%2a/g' \
			-e 's/{/%7b/g' \
			-e 's/}/%7d/g' \
			-e 's/\$/%24/g' \
			-e 's/\^/%5e/g' \
			-e 's/ /+/g'
}

logrotate_monilog()
{
	local file="$TMPDIR/monilog.txt"
	local size datestring final
	local border=$(( 10 * 1024 * 1024 ))
	local destdir='/var/www'
	local destfile="$destdir/$( basename "$file" )"

	[ -e "$file" ] || return 0
	size="$( stat -c'%s' "$file" )"
	[ $size -gt $border ] || return 0

	log "logrotate '$file' into '$destdir/'"
	cp "$file" "$destdir"
	>"$file"
	bzip2 --small --best "$destfile"

	datestring=$( date +%s )
	final="$destfile.$datestring.bz2"
	mv "$destfile.bz2" "$final"
	log "logrotate ready: $final"
}

gen_meshrdf_for_network()
{
	local funcname='gen_meshrdf_for_network'
	local network="$1"
	local html="/var/www/networks/$network/index.html"
	local temp="$html.temp"
	local url="http://127.0.0.1/networks/$network/meshrdf/?ORDER=hostname"
	local datadir="/var/www/networks/$network/meshrdf/recent"
	# FIXME! better pattern
	local newest_file="$datadir/$( ls -1t "$datadir" | grep "[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]"$ | head -n1 )"
	local hash_file="/dev/shm/meshrdf_hash_$network"
	local hash_now="$( date +%s -r "$newest_file" )"
	local hash_last

	ignore_network "$network" && return 0

	respect_fileage()
	{
		case "$( date '+%H:%M' )" in	# e.g. 09:01
			'02:'*|'03:'*|'14:'*)
				log "$funcname: respect_fileage: no"
				return 1
			;;
			*)
				case "$network" in
					'cvjm')
						# only 1 router
						return 1
					;;
					*)
#						log "$funcname: respect_fileage: yes"
						return 0
					;;
				esac
			;;
		esac
	}

	respect_fileage && {
		read -r hash_last <"$hash_file"	# = timestamp

		if [ "$hash_last" = "$hash_now" ]; then
#			log "$funcname() NEEDED? no changes for network $network - ignoring call - is: $hash_now"

			# FIXME! get newest file will not work for "symlinks only"
			[ "$network" = 'server' ] || return 0
		else
#			log "$funcname() NEEDED? found changes network $network - was: $hash_last != $hash_now (now)"
			echo "$hash_now" >"$hash_file"
		fi
	}

	# file age:
	local unixtime_file="$( date +%s -r "$html" )"
	local unixtime_here="$( date +%s )"
	local unixtime_diff=$(( unixtime_here - unixtime_file ))

	log "[START] network $network (last build before $unixtime_diff sec)"
	touch "$temp" && chmod 777 "$temp"
	wget -qO "$temp" "$url"
	mv "$temp" "$html"

	unixtime_file="$( date +%s -r "/var/www/files/all.tar.xz" )"
	unixtime_here="$( date +%s )"
	unixtime_diff=$(( unixtime_here - unixtime_file ))
	[ $unixtime_diff -gt 1800 ] && build_html_tarball

#	/var/www/scripts/apply_new_network.sh "$network"

	log "[READY] fetched $network"
}

case "$OPTION" in
	'func:'*)
		OPTION="$( echo "$OPTION" | cut -d':' -f2 )"
		log "executing function: $OPTION"
		$OPTION
		exit $?
	;;
esac

# this detroys the ping-counter! we really should send out an SMS
log "checking: disk full?"
if df -h /dev/xvda1 | fgrep -q "100%"; then
	if iptables -nL INPUT | head -n3 | grep -q ^'ACCEPT' ; then
		log "diskspace OK - allowing ssh-login: already allowed"
	else
		/var/www/scripts/send_sms.sh "liszt28" "0176/24223419" "intercity-vpn.de: disk full - needs housekeeping"
		log "disk full - allowing ssh-login from everywhere"
		iptables -I INPUT -p tcp -j ACCEPT
	fi
else
	iptables -nL INPUT | head -n3 | grep ^'ACCEPT' | grep -q 'tcp  --  0.0.0.0/0' && {
		log "diskspace OK again - removing 'accept all'-input rule"
		iptables -D INPUT 1
	}
fi


[ "$OPTION" = "cache" ] && {
	if ls -1 /tmp/lockfile_meshrdf_cache_* >/dev/null 2>/dev/null; then
		log "lockfile found: /tmp/lockfile_meshrdf_cache_*, ABORT"
		exit
	else
		log "[START] starting new round with pid $$ option: '$OPTION' network_wish: '$WISH_NETWORK'"
		touch "/tmp/lockfile_meshrdf_cache_$$"
		TIME_START="$( uptime_in_seconds )"
	fi
}

remove_logs()
{
	log "deleting '/var/log/apache2/access.log.*'"
	rm /var/log/apache2/access.log.*
	log "deleting '/var/log/apache2/error.log.*'"
	rm /var/log/apache2/error.log.*
	log "deleting some log in /var/log/..."
	rm /var/log/user.log.*
	rm /var/log/messages.*
	rm /var/log/kern.log.*
	rm /var/log/syslog.*
	rm /var/log/auth.*
	rm /var/log/tinyproxy.log.*
	rm /var/log/daemon.log.*
	rm /var/log/dmesg.*
	rm /var/log/debug.*

	log "trash: rm /tmp/write_meshrdf.* $( ls -1 /tmp/write_meshrdf.* | wc -l )"
	rm /tmp/write_meshrdf.*
	log "trash: now $( ls -1 /tmp/write_meshrdf.* | wc -l )"
}

logrotate_monilog
remove_logs
optimize_space

log "check: 0 byte files?"

case "$( date '+%H:%M' )" in    # e.g. 09:01
	'02:'*|'03:'*)
		/var/www/scripts/read_kernel_release_dates.sh
	;;
esac




[ -n "$( list_meshrdf_files_with_zero_size )" ] && {
	log "[ERR] found $( list_meshrdf_files_with_zero_size | wc -l ) meshrdf-files, which have 0 byte size, deleting them"

	for FILE in $( list_meshrdf_files_with_zero_size ); do {
		rm "$FILE"
	} done

	log "[READY] deleting 0 byte meshrdf-files"
}


LIST="$( list_networks )"
TEMP="/tmp/meshrdf_check_$$"
MESSAGE=

I=0
for NET in $LIST; do {
	I=$(( I + 1 ))
} done
IALL=$I

I=0
for NET in $LIST; do {
	logrotate_monilog
	ignore_network "$NET" && continue
	NET="/var/www/networks/$NET/meshrdf/recent"

	# TODO: always for 'small' networks
	# build often!
#	gen_meshrdf_for_network gnm
	gen_meshrdf_for_network limona
	gen_meshrdf_for_network cvjm
#	gen_meshrdf_for_network ewerk
#	gen_meshrdf_for_network malchow		# demo
#	gen_meshrdf_for_network malchowpferde
#	gen_meshrdf_for_network malchowpension
	gen_meshrdf_for_network abtpark
#	gen_meshrdf_for_network ffweimar-vhs
	gen_meshrdf_for_network ffweimar-dnt
	gen_meshrdf_for_network wagenplatz
	gen_meshrdf_for_network monami
#	gen_meshrdf_for_network ffweimar-roehr
#	gen_meshrdf_for_network ilm1
	gen_meshrdf_for_network server
#	gen_meshrdf_for_network xoai

	htmlout_error_summary "$LIST"		# very fast
	/var/www/scripts/build_whitelist_incoming_ssh.sh start

#	FILE="$( ls -1t $NET/* | head -n1 )"
#	UNIXTIME_FILE="$( date +%s -r "$FILE" )"
#	UNIXTIME_HERE="$( date +%s )"
#	UNIXTIME_DIFF=$(( UNIXTIME_HERE - UNIXTIME_FILE ))
#	[ $UNIXTIME_DIFF -gt 3600 ] && {
#		log "[OK] diff = $UNIXTIME_DIFF sec - omitting network $NET"
#		continue
#	}

	[ -d "$NET/../../getip" ] || {
		ln -s "/var/www/scripts/getip/" "$NET/../../getip"
	}

	log "chmod -R 777 $NET"
	chmod -R 777 "$NET"

	log "chmod -R 777 $NET/../../registrator/recent"
	chmod -R 777 "$NET/../../registrator/recent"

	log "chmod 777 $NET/../../pubip.txt"
	touch $NET/../../pubip.txt
	chmod 777 $NET/../../pubip.txt

	touch $NET/../failure_overview.txt
	chmod 777 $NET/../failure_overview.txt
	touch $NET/../failure_overview.txt.tmp
	chmod 777 $NET/../failure_overview.txt.tmp

	[ -n "$( ls -1 $NET/autonode* 2>/dev/null )" ] && rm $NET/autonode*

	I=$(( I + 1 ))
	log "net: $( echo $NET | cut -d'/' -f5 ) = $I/$IALL"

	[ -n "$WISH_NETWORK" ] && {
		echo $NET | grep -q "$WISH_NETWORK" || continue
	}

	MAX_FAILS=60
	while true; do {
		[ "$OPTION" = "debug" ] && break

		MAX_FAILS=$(( MAX_FAILS - 1 ))
		[ $MAX_FAILS -eq 0 ] && {
			log "too much load, too often: $MAX_FAILS, rebooting in 30 sec"
			sleep 30
			reboot
		}

		read -r LOAD _ </proc/loadavg
		case "$LOAD" in
			0*)
				break
			;;
			*)
				sleep 60
			;;
		esac
	} done

	NETWORK="$( echo $NET | cut -d'/' -f5 )"	# e.g. elephant
	ERR=
	WEAK=
	LOST=
	GOOD=

#	log "[OK] load-detector passed, load: $LOAD"

	echo >>"/tmp/networks_list.txt.tmp" "$NETWORK "
	echo >/tmp/all_pubips.txt_$$ "$NETWORK: $( cat /var/www/networks/$NETWORK/pubip.txt 2>/dev/null )"

#	log "test -n \"\$( ls -1 $NET )\" && ..."

	[ -n "$( ls -1 $NET )" ] && {		# e.g. /var/www/networks/ffweimar/meshrdf/recent

		[ ! -e "/var/www/networks/$NETWORK/meshrdf/meshrdf.txt" ] && {
#			log "touching '/var/www/networks/$NETWORK/meshrdf/meshrdf.txt'"
			touch "/var/www/networks/$NETWORK/meshrdf/meshrdf.txt"
		}

		DATE_TODAY="$( date +%Y%b%d )"
		for VDS_FILE in $( ls -1 /var/www/networks/$NETWORK/vds/db_backup.tgz_* | grep -v "$DATE_TODAY" ); do {
			ls -al --time-style=+%D "$VDS_FILE" | grep -q "$(date +%D)" && {		# is from today
				[ -e "$VDS_FILE.$DATE_TODAY" ] || {
					log "creating vds-file backup $VDS_FILE.$DATE_TODAY"
					cp "$VDS_FILE" "$VDS_FILE.$DATE_TODAY"
				}
			}
		} done

		if [ "$OPTION" = "cache" ]; then

			log "[START] fetching $NETWORK"
			chmod 777 "/var/www/networks/$NETWORK/meshrdf/meshrdf.html"

			case "$NETWORK" in
				ffweimar|liszt28)
					# hide failures (move to bottom)
				;;
				*)
					# show failures
					MYORDER="age2"
					log "MYORDER=$MYORDER"
				;;
			esac

#			touch "/var/www/networks/$NETWORK/meshrdf/meshrdf.html.temp"
#			chmod 777 "/var/www/networks/$NETWORK/meshrdf/meshrdf.html.temp"# BLA			wget -qO "/var/www/networks/$NETWORK/index.html.temp" "http://127.0.0.1/networks/$NETWORK/meshrdf/?ORDER=$MYORDER"
#			mv "/var/www/networks/$NETWORK/index.html.temp" "/var/www/networks/$NETWORK/index.html"
			gen_meshrdf_for_network "$NETWORK"

#			log "[START] building map for $NETWORK"
#			/var/www/scripts/meshrdf_generate_map.sh "/var/www/networks/$NETWORK/meshrdf" >/tmp/map_$$.txt
#			log "[READY] building map for $NETWORK"

			case "$( date +%M )" in
				INACTIVE)
					for FORMAT in svg fake; do {			# fixme! png / pdf
						log "[START] building format $FORMAT for $NETWORK"
						dot 1>/dev/null 2>/dev/null -Goverlap=scale -Gsplines=true -Gstart=3 -v -T$FORMAT -o /tmp/map_$$.$FORMAT /tmp/map_$$.txt
						log "[READY] building format $FORMAT for $NETWORK"

						cp /tmp/map_$$.$FORMAT "/var/www/networks/$NETWORK/meshrdf/map.$FORMAT"
						mv /tmp/map_$$.$FORMAT "/var/www/networks/$NETWORK/map.$FORMAT"
					} done

					cp /tmp/map_$$.txt "/var/www/networks/$NETWORK/map.txt"
					mv /tmp/map_$$.txt "/var/www/networks/$NETWORK/meshrdf/map.txt"
					rm "/var/www/networks/$NETWORK/map_"*	2>/dev/null				# fixme!
					rm "/var/www/networks/$NETWORK/meshrdf/map_"*				# fixme!
				;;
				*)
					ignore_network "$NETWORK" || {
					log "[OK] writing netjson for '$NETWORK'"
					cd "/var/www/networks/$NETWORK/meshrdf" || exit

					rm map.json.* 2>/dev/null	# FIXME! remove later...
					if /var/www/scripts/meshrdf_generate_netjson.sh "$NETWORK" >"map.json.$$"; then
						mv "map.json.$$" "map.json"
						log "[OK] ready netjson for '$NETWORK'"
					else
						log "[ERR] during netjson"
						rm "map.json.$$"
					fi

					cd - 2>/dev/null || exit
					}
				;;
			esac
		else
			case $NETWORK in
				ffweimar|ffsundi)
					log "[OK] omitting network $NETWORK"
					continue
				;;				# nosms or status please
			esac

#			log "fetching: $NETWORK message: '$MESSAGE' option: '$OPTION'"
		fi

		[ "$OPTION" = "cache" ] || {
			TEMP="/var/www/networks/$NETWORK/index.html"
			WEAK="$( grep " node_weak " "$TEMP" | sed -n 's/^.* node_weak \([0-9]*\).*/\1/p' )"
			LOST="$( grep " node_lost " "$TEMP" | sed -n 's/^.* node_lost \([0-9]*\).*/\1/p' )"
			GOOD="$( grep " node_good " "$TEMP" | sed -n 's/^.* node_good \([0-9]*\).*/\1/p' )"

			[ "$WEAK" != "0" ] && ERR="weak:$WEAK"
			[ "$LOST" != "0" ] && ERR="${ERR}lost:$LOST"

			case "$WEAK$LOST" in
				00)
					:
				;;
				"")
					:
				;;
				*)
					logger -s "$0: $NETWORK weak/lost: $WEAK/$LOST"
				;;
			esac

			[ -n "$ERR" ] && {
				MESSAGE="${MESSAGE}${MESSAGE:+ }${NETWORK}-good:${GOOD}$ERR"
			}
		}
	}

} done

log "[READY] first loop"

mv /tmp/all_pubips.txt_$$ /tmp/all_pubips.txt
mv /tmp/networks_list.txt.tmp /var/www/network_list.txt

[ "$OPTION" = 'cache' ] && {
	htmlout_error_summary "$LIST"
	exit
}



[ "${#MESSAGE}" -gt 160 ] && {
	log "message too long: $MESSAGE"
	MESSAGE=
}

[ -n "$MESSAGE" ] && {
	# FIXME! use '/var/www/scripts/send_sms.sh'
	RECIPIENTS="0179/7465017 0176/61623698"

	SERVICE="http://www.sms77.de/gateway"
	USERNAME="gforce"
	PASSWORD="mvemjsunpsms77"

	log "sms: $MESSAGE"

	MESSAGE="$( urlencode "$MESSAGE" )"

	for NUMBER in $RECIPIENTS; do {
		NUMBER="$( echo $NUMBER | sed 's/[^0-9]//g' )"
		URL="${SERVICE}/?type=quality&u=${USERNAME}&p=${PASSWORD}&to=${NUMBER}&text=${MESSAGE}"

		case "$OPTION" in
			debug) log "DEBUG: wget -qO /dev/null '$URL'" ;;
			    *) wget -qO /dev/null "$URL"; log "wgetrc: $# <- '$URL'";;
		esac
	} done
}

log "[READY] needed $(( $( uptime_in_seconds ) - TIME_START )) seconds"

