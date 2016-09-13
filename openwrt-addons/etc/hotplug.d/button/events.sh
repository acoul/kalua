#!/bin/sh
# sourced from /sbin/hotplug-call
# or call via:
# BUTTON=wps; ACTION=released; . /etc/hotplug.d/button/events.sh

# also must take care of '/etc/rc.button/reset'
[ "$BUTTON" = 'reset' ] && BUTTON='wps'

case "${BUTTON}-${ACTION}" in
	# wps = WiFi Protected Setup: http://wiki.openwrt.org/doc/uci/wireless#wps.options
	'wps-pressed')
		read -r UP REST </proc/uptime
		echo "${UP%.*}${UP#*.}" >'/tmp/BUTTON'
	;;
	'wps-released')
		if read -r START 2>/dev/null <'/tmp/BUTTON'; then
			read -r UP REST </proc/uptime
			END="${UP%.*}${UP#*.}"
			DIFF=$(( END - START ))
		else
			DIFF=99		# 100 = longpress
		fi

		# FIXME! DIFF = 1000 -> 10 seconds
		logger -s -- "$0: button '$BUTTON' released after $DIFF millisec"
		rm '/tmp/BUTTON'

		# works with e.g.
		# Alesis M1 Active 320 USB = 08bb:29b0 = Texas Instruments PCM2900B Audio CODEC:
		# PE-5819-919 auvisio ext. USB-Soundkarte "Virtual 7.1" = 0d8c:000c = C-Media Electronics, Inc. Audio Adapter
		next_radio()
		{
			route -n | grep -q ^'0\.0\.0\.0' || return 0

			local file='/tmp/audioplayer.sh'
			local url
			local i=1

			if [ -e "$file" ]; then
				read -r _ i <"$file"
				i=$(( i + 1 ))

				killall madplay
				# play a jingle? -> http://ctrlq.org/listen/
			else
				[ -e '/tmp/audioplayer.dev' ] || return
			fi

			# file generated during cron-startup
			read -r DSPDEV <'/tmp/audioplayer.dev' || logger -s -- "$0: audioplayer: DSP-dev"

			case "$i" in
				2) url='soma.fm space-station http://sfstream1.somafm.com:2020' ;;
				3) url='soma.fm xmasinfrisko http://sfstream1.somafm.com:2100' ;;
				4) url='soma.fm indiepop http://sfstream1.somafm.com:8090' ;;
				5) url='mdr figaro http://avw.mdr.de/livestreams/mdr_figaro_live_128.m3u' ;;
				6) url='radio-blau main http://www.radioblau.de/stream/radioblau.m3u' ;;
				7) url='apollo-radio main http://stream.apolloradio.de/APOLLO/mp3.m3u' ;;
				8) url='harmonyfm goodtimes http://mp3.harmonyfm.de/harmonyfm/hqlivestream.mp3' ;;
				8) url='radio-lotte main http://www.radio-lotte.de/stream/radiolotte.m3u' ;;
				9) url='FM4 main http://mp3stream1.apasf.apa.at:8000' ;;
				10)url='soma.fm secret-agent http://mp3.somafm.com:443' ;;
				*) url='radio-lotte main http://www.radio-lotte.de/stream/radiolotte.m3u';i=1;;
			esac

			logger -s -- "$0: audioplayer: station: $url"
			url="$( echo $url | cut -d' ' -f3 )"
			case "$url" in
				*'.m3u'|*.'M3U')
					url="$( wget -qO - "$url" | grep -v ^'#' | head -n1 )"
				;;
			esac

			buffer_useable()
			{
				command -v 'stdbuf' >/dev/null || return
				test -e '/usr/lib/coreutils/libstdbuf.so'
			}

			logger -s -- "$0: audiplayer: i: $i - url: $url"
			echo  >"$file" "# $i"
			DOWNLOAD="wget --user-agent 'AUDIOPLAYER' -qO - '$url'"
			BUFFER="$( buffer_useable && echo 'stdbuf --input=1024KB --output=0 ' )"
			MADPLAY="madplay --output=$DSPDEV --quiet -"
			# rmmod because of https://dev.openwrt.org/ticket/13392
			# TODO: needed yet?
			CLEANUP="rmmod snd_usb_audio && modprobe snd_usb_audio"

			# our $file is sourced from cron.minutely
			if command -v 'mpg123' >/dev/null; then
				echo >>"$file" "pidof mpg123 >/dev/null || ( mpg123 -b 1024 -m -c -y -k 100 -q '$url' ) &"
			else
				echo >>"$file" "pidof madplay >/dev/null || ( $DOWNLOAD | $BUFFER $MADPLAY; $CLEANUP; ) &"
			fi

			chmod +x "$file"
			exec "$file"
		}

		if PID="$( pidof madplay )" ; then
			if [ $DIFF -ge 100 ]; then	# long pressed
				rm '/tmp/audioplayer.sh'
				kill $PID
			else
				next_radio
			fi
		else
			next_radio
		fi

		. /tmp/loader
		_weblogin authserver_message "button_pressed.$NODENUMBER.$ANYADR.$HOSTNAME.$DIFF.msec"

		[ $DIFF -gt 300 ] && {
			_log it firmware_button daemon info "button_pressed.$NODENUMBER.$ANYADR.$HOSTNAME.$DIFF.msec"

			[ $DIFF -gt 1000 ] && {
				touch '/coredump/testdump.core'		# FIXME! see system_adjust_coredump()
				touch '/www/serial_enabled'
				_watch coredump 'during: button-hotplug'
			}

			PID="$( uci -q get system.@monitoring[0].button_smstext )" && {
				for END in $( uci -q get system.@monitoring[0].button_phone ); do {
					USERNAME="$( uci -q get sms.@sms[0].username )"
					PASSWORD="$( uci -q get sms.@sms[0].password )"
					_sms send "$END" "$PID" '' "$USERNAME" "$PASSWORD"
				} done
			}
		}
	;;
	*)
		logger -s -- "$0: button '$BUTTON' action: '$ACTION' ignoring args: $*"
	;;
esac
