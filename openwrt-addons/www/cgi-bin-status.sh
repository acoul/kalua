#!/bin/sh
. /tmp/loader

_http header_mimetype_output 'text/html'


remote_hops()
{
	local remote_nodenumber remote_lanadr

	remote_nodenumber="$( _ipsystem do "$REMOTE_ADDR" )"
	remote_lanadr="$( _ipsystem do "$remote_nodenumber" | grep ^'LANADR=' | cut -d'=' -f2 )"

	_olsr remoteip2metric "$remote_lanadr" || echo '?'
}

output_table()
{
	local file='/tmp/OLSR/LINKS.sh'
	local line word remote_hostname iface_out iface_out_color mac snr bgcolor toggle rx_mbytes tx_mbytes i all gw_file
	local LOCAL REMOTE LQ NLQ COST COUNT=0 cost_int cost_color snr_color dev channel metric gateway gateway_percent
	local head_list neigh_list neigh_file neigh age inet_offer bytes cost_best cost_best_time th_insert mult_ip count cost_align
	local symbol_infinite='<big>&infin;</big>'
	local mult_list="$( uci -q get olsrd.@Interface[0].LinkQualityMult ) $( uci -q get olsrd.@Interface[1].LinkQualityMult )"

	if [ -e '/tmp/OLSR/DEFGW_NOW' ]; then
		read gateway <'/tmp/OLSR/DEFGW_NOW'
		[ "$gateway" = 'empty' ] && gateway=
	else
		gateway=
	fi

	all=0
	for gw_file in /tmp/OLSR/DEFGW_[0-9]*; do {
		[ -e "$gw_file" ] && {
			read i <"$gw_file"
			all=$(( $all + $i ))
		}
	} done

	for neigh_file in /tmp/OLSR/isneigh_*; do {
		case "$neigh_file" in
			*'_bestcost')
			;;
			*)
				[ -e "$neigh_file" ] && {
					neigh_list="$neigh_list ${neigh_file#*_}"
				}
			;;
		esac
	} done

	# tablehead - change also 'colspan' in 'old neighs' when we add/del something here
	echo -n "<tr>"
	head_list='No. Nachbar-IP Hostname Schnittstelle lokale&nbsp;Interface-IP LQ NLQ ETX ETX<small><sub>min</sub></small> Speed<small><sub>best</sub></small> SNR Metrik raus rein Gateway'
	for word in $head_list; do {
		case "$word" in
			'Gateway')
				if [ -e '/tmp/OLSR/DEFGW_empty' ]; then
					read i <'/tmp/OLSR/DEFGW_empty'
					word="$word ($(( ($i * 100) / $all ))% Inselbetrieb)"
				elif inet_offer="$( _net local_inet_offer )"; then
					word="$word (Einspeiser: $inet_offer)"
				fi

				[ -z "$gateway" ] && th_insert=" bgcolor='crimson'"
			;;
			'ETX')
				th_insert='class="sorttable_numeric"'
			;;
		esac

		echo -n "<th valign='top' nowrap ${th_insert}>$word</th>"
	} done
	echo -n "</tr>"

	local octet3
	get_octet3()
	{
		local ip="$1"

		ip=${ip#*.}
		ip=${ip#*.}
		octet3=${ip%.*}
	}

	build_cost_best()
	{
		local remote_ip="$1"
		local cost_file="/tmp/OLSR/isneigh_${remote_ip}_bestcost"

		if [ -e "$cost_file" ]; then
			cost_best_time="$( _file time "$cost_file" humanreadable )"
			read cost_best <"$cost_file"
		else
			cost_best='&mdash;'
		fi
	}

	build_remote_hostname()
	{
		local remote_ip="$1"

		remote_hostname="$( _net ip2dns "$remote_ip" )"

		# did not work (e.g. via nameservice-plugin), so ask the remote directly
		[ "$remote_hostname" = "$remote_ip" ] && {
			remote_hostname="$( _tool remote "$remote_ip" hostname )"
			if [ -z "$remote_hostname" ]; then
				remote_hostname="$remote_ip"
			else
				# otherwise we could include a redirect/404
				remote_hostname="$( _sanitizer do "$remote_hostname" strip_newlines hostname )"
			fi
		}

		case "$remote_hostname" in
			mid[0-9].*)
				# mid3.F36-Dach4900er-MESH -> F36-Dach4900er-MESH
				remote_hostname="${remote_hostname#*.}"
			;;
			'xmlversion'*|'htmlxml'*)
				# fetched 404/error-page
				remote_hostname="$remote_ip"
			;;
		esac

		case "$remote_hostname" in
			"$remote_ip")
			;;
			*'.'*)
				# myhost.lan -> myhost
				remote_hostname="${remote_hostname%.*}"
			;;
		esac
	}

	_net include
	_olsr include
	count=0
	while read line; do {
		# LOCAL=10.63.2.3;REMOTE=10.63.48.65;LQ=0.796;NLQ=0.000;COST=1.875;COUNT=$(( $COUNT + 1 ))
		eval $line

		count=$(( $count + 1 ))
		iface_out="$( _net ip2dev "$REMOTE" )"
		neigh_list="$( _list remove_element "$neigh_list" "$REMOTE" )"

		build_remote_hostname "$REMOTE"

		case "$toggle" in
			'even')
				toggle=
				bgcolor=
			;;
			*)
				toggle='even'
				bgcolor='beige'
			;;
		esac

		if [ -e "/tmp/OLSR/DEFGW_$REMOTE" ]; then
			read i <"/tmp/OLSR/DEFGW_$REMOTE"
			gateway_percent=$(( ($i * 100) / $all ))
			gateway_percent="${gateway_percent}%"		# TODO: sometimes >100%
		else
			gateway_percent=
		fi

		if [ "$gateway" = "$REMOTE" ]; then
			bgcolor='#ffff99'			# lightyellow
			eval $( _olsr best_inetoffer )		# GATEWAY,METRIC,ETX,INTERFACE


			if [ -n "$METRIC" ]; then
				gateway_percent="${gateway_percent:-100%}, $METRIC Hops, ETX $ETX"
			else
				gateway_percent="(kein HNA!)"
			fi
		else
			[ -n "$gateway_percent" ] && {
				gateway_percent="$gateway_percent (vor $( _file age "/tmp/OLSR/DEFGW_$REMOTE" humanreadable ))"
			}
		fi

		metric="$( _olsr remoteip2metric "$REMOTE" )"
		case "$metric" in
			'1')
				metric='direkt'
			;;
			'')
				metric='&mdash;'
			;;
		esac

		is_wifi()
		{
			_net dev_is_wifi "$1" && return 0

			case "$COST" in
				'1.000'|'0.100')
					return 1
				;;
				*)
					# likely no ethernet/VPN
					return 0
				;;
			esac
		}

		channel=; snr=; rx_mbytes=; tx_mbytes=
		if is_wifi "$iface_out"; then
			mac="$( _net ip2mac "$REMOTE" )" || {
				mac="$( _tool remote "$REMOTE" ip2mac )"
				mac="$( _sanitizer do "$mac" mac )"
			}

			if [ -n "$mac" ]; then
				for dev in $WIFI_DEVS; do {

					# maybe use: wifi_get_station_param / wifi_show_station_traffic
					set -- $( iw dev "$dev" station get "$mac" )
					while [ -n "$1" ]; do {
						shift
						case "$1 $2" in
							'signal avg:')
								snr="$3"
								break 2
							;;
							'rx bytes:')
								rx_mbytes=$(( $3 / 1024 / 1024 ))
								[ $rx_mbytes -eq 0 ] && rx_mbytes='&mdash;'
							;;
							'tx bytes:')
								tx_mbytes=$(( $3 / 1024 / 1024 ))
								[ $tx_mbytes -eq 0 ] && tx_mbytes='&mdash;'
							;;
						esac
					} done
				} done

				if [ -n "$snr" ]; then
					channel="$( _wifi channel "$dev" )"
					channel="/Kanal&nbsp;$channel"

					# 95 = noise_base / drivers_default
					# http://en.wikipedia.org/wiki/Thermal_noise#Noise_power_in_decibels
					# https://lists.open-mesh.org/pipermail/b.a.t.m.a.n/2014-April/011911.html
					snr="$(( 95 + $snr ))"

					if   [ $snr -gt 30 ]; then
						snr_color='green'
					elif [ $snr -gt 20 ]; then
						snr_color='yellow'
					elif [ $snr -gt 5  ]; then
						snr_color='orange'
					else
						snr_color='red'
					fi
				else
					snr='error/no_assoc'
					snr_color='red'
				fi
			else
				snr='error/no_mac'
				snr_color='red'
			fi

			iface_out_color=
		else
			# use net_dev_type()
			snr='ethernet'
			snr_color='green'
			iface_out_color='green'

			case "$iface_out" in
				$LANDEV)
					channel='/LAN'
				;;
				$WANDEV)
					channel='/WAN'
				;;
				'tun'*|'tap'*)
					channel='/VPN'
				;;
			esac

			# RX bytes:1659516 (1.5 MiB)  TX bytes:12571064 (11.9 MiB)
			bytes="$( ifconfig "$iface_out" | fgrep 'RX bytes:' )"
			set -- ${bytes//:/ }

			rx_mbytes=$(( $3 / 1024 / 1024 ))
			[ $rx_mbytes -eq 0 ] && rx_mbytes='&mdash;'
			tx_mbytes=$(( $8 / 1024 / 1024 ))
			[ $tx_mbytes -eq 0 ] && tx_mbytes='&mdash;'
		fi

		# TODO: detect proper $REMOTE - type, $LOCAL is wrong
		case "x$LOCAL" in
			$LANADR|$WANADR)
				snr='ethernet'
				snr_color='green'
				iface_out_color='green'

				case "$LOCAL" in
					$LANADR)
						channel='/LAN_bla'
					;;
					$WANADR)
						channel='/WAN_bla'
					;;
				esac
			;;
		esac

		cost_int="${COST%.*}${COST#*.}"
		if   [ -z "$cost_int" ]; then
			cost_int=99999		# for sorting - TODO: does not work
			cost_color='red'
		elif [ $cost_int -gt 10000 ]; then
			cost_color='red'
		elif [ $cost_int -gt 4000  ]; then
			cost_color='orange'
		elif [ $cost_int -gt 2000  ]; then
			cost_color='yellow'
		else
			cost_color='green'
		fi

		case " $mult_list " in
			*" $REMOTE "*)
				# e.g. '10.10.12.1 0.7 10.10.99.1 0.3' -> 0.7
				mult_ip="${mult_list#*$REMOTE }"
				mult_ip="${mult_ip%% *}"
			;;
			*)
				mult_ip=
			;;
		esac

		if [ -n "$COST" ]; then
			cost_align='right'
			[ -n "$mult_ip" ] && COST="${mult_ip}&nbsp;&lowast;&nbsp;${COST}"
		else
			cost_align='center'
			COST="$symbol_infinite"
			[ -n "$mult_ip" ] && COST="(${mult_ip}&nbsp;&lowast;)&nbsp;$COST"
		fi

		build_cost_best "$REMOTE"
		get_octet3 "$REMOTE"

		cat <<EOF
<tr bgcolor='$bgcolor'>
 <td align='right'><small>$count</small></td>
 <td nowrap sorttable_customkey='$octet3'> <a href='http://$REMOTE/cgi-bin-status.html'>$REMOTE</a> </td>
 <td nowrap> <a href='http://$REMOTE/cgi-bin-status.html'>$remote_hostname</a> </td>
 <td bgcolor='$iface_out_color'> ${iface_out}${channel} </td>
 <td> $LOCAL </td>
 <td> $LQ </td>
 <td> $NLQ </td>
 <td sorttable_customkey='$cost_int' align='$cost_align' bgcolor='$cost_color'> $COST </td>
 <td align='right' title='$cost_best_time'> $cost_best </td>
 <td align='right'>$( _wifi speed cached $REMOTE | cut -d'-' -f2 )</td>
 <td align='right' bgcolor='$snr_color'> $snr </td>
 <td align='center'> $metric </td>
 <td align='right'> $rx_mbytes </td>
 <td align='right'> $tx_mbytes </td>
 <td nowrap> $gateway_percent </td>
</tr>
EOF
	} done <"$file"

	# old neighs, which are unknown now
	for neigh in $neigh_list; do {
		get_octet3 "$neigh"
		age="$( _file age "/tmp/OLSR/isneigh_$neigh" humanreadable_verbose )"
		build_remote_hostname "$neigh"
		build_cost_best "$neigh"
		count=$(( $count + 1 ))
		metric="$( _olsr remoteip2metric "$neigh" )"

		echo "<tr>"
		echo " <td align='right'><small>$count</small></td>"
		echo " <td sorttable_customkey='$octet3'> <a href='http://$neigh/cgi-bin-status.html'>$neigh</a> </td>"
		echo " <td> <a href='http://$neigh/cgi-bin-status.html'>$remote_hostname</a> </td>"
		echo " <td colspan='5' nowrap align='right'> vermisst seit $age </td>"
		echo " <td align='right' title='$cost_best_time'> $cost_best </td>"
		echo " <td>&nbsp;</td>"		# speed
		echo " <td>&nbsp;</td>"		# SNR
		echo " <td align='center'> ${metric:-&mdash;} </td>"
		echo " <td colspan='3'> &nbsp; </td>"
		echo "</tr>"
	} done
}

[ -e '/tmp/OLSR/ALL' ] || _olsr build_tables

# in /tmp/OLSR/ALL
# Table: Links
# Table: Neighbors
# Table: Topology
# Table: HNA
# Table: MID
# Table: Routes

# TODO: 'Table: HNA' -> $1 = 0.0.0.0/0 = Einspeiser

# count all uniq entries/destinations in table 'Topology'
NODE_COUNT=0
NODE_LIST=
PARSE=
while read LINE; do {
	case "${PARSE}${LINE}" in
		'Table: Topology')
			PARSE='true-'
		;;
		'true-Dest. IP'*)
		;;
		'true-')
			NODE_LIST=
			break
		;;
		'true-'*)
			# 10.63.1.97  10.63.183.33  0.121  0.784  10.487
			set -- $LINE
			case "$NODE_LIST" in
				*" $1 "*)
					# already in list
				;;
				*)
					NODE_LIST="$NODE_LIST $1 "
					NODE_COUNT=$(( $NODE_COUNT + 1 ))
				;;
			esac
		;;
	esac
} done <'/tmp/OLSR/ALL'

read ROUTE_COUNT <'/tmp/OLSR/ROUTE_COUNT'

if [ -e '/tmp/OLSR/ALL' ]; then
	AGE_DATABASE="$( _file age '/tmp/OLSR/ALL' sec )"
else
	if _olsr uptime is_short; then
		AGE_DATABASE=-1
	else
		if _olsr build_tables; then
			AGE_DATABASE="$( _file age '/tmp/OLSR/ALL' sec )"
		else
			AGE_DATABASE="$( _system uptime sec )"
		fi
	fi
fi

if   [ $AGE_DATABASE -gt 120 ]; then
	echo >>$SCHEDULER_IMPORTANT "_olsr build_tables"
	AGE_HUMANREADABLE="&nbsp;&nbsp; Achtung: Datengrundlage >$( _stopwatch seconds2humanreadable "$AGE_DATABASE" ) alt"
elif [ $AGE_DATABASE -eq -1 ]; then
	AGE_HUMANREADABLE="&nbsp;&nbsp; Achtung: OLSR-Dienst gerade erst gestartet, keine Daten vorhanden"
fi

# changes/min
if [ -e '/tmp/OLSR/DEFGW_changed' ]; then
	UP_MIN=$( _system uptime min )
	GATEWAY_JITTER=$( _file lines '/tmp/OLSR/DEFGW_changed' )

	if [ $GATEWAY_JITTER -eq 1 ]; then
		GATEWAY_JITTER='nie'
	else
		GATEWAY_JITTER="$GATEWAY_JITTER in $UP_MIN min &Oslash; alle $(( $UP_MIN / $GATEWAY_JITTER )) min"
	fi
else
	GATEWAY_JITTER='nie'
fi

cat <<EOF
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
	"http://www.w3.org/TR/html4/loose.dtd">
<html>
 <head>
  <title>$HOSTNAME - No. $NODENUMBER - Nachbarn</title>
  <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=ISO-8859-15">
EOF

_http include_js_sorttable

cat <<EOF
 </head>
 <body>
  <h1>$HOSTNAME &ndash; No. $NODENUMBER (mit OpenWrt r$( _system version short ) auf $HARDWARE)</h1>
  <h3><a href='#'> OLSR-Verbindungen </a> $AGE_HUMANREADABLE </h3>
  <big>&Uuml;bersicht &uuml;ber aktuell bestehende OLSR-Verbindungen ($NODE_COUNT Netzknoten, $ROUTE_COUNT Routen, $( remote_hops ) Hops zu Betrachter $REMOTE_ADDR, Gatewaywechsel: $GATEWAY_JITTER)</big><br>

  <table cellspacing='5' cellpadding='5' border='0' class='sortable'>
EOF

output_table
echo '  </table>'
_switch show 'html' 'Ansicht der Netzwerkanschl&uuml;sse:&nbsp;'

cat <<EOF
  <h3> Legende: </h3>
  <ul>
   <li> <b>Metrik</b>: Daten werden direkt oder &uuml;ber Zwischenstationen gesendet </li>
   <li> <b>Raus</b>: Tx = gesendete Daten = Upload [Megabytes] </li>
   <li> <b>Rein</b>: Rx = empfangene Daten = Download [Megabytes] </li>
   <li> <b>LQ</b>: Erfolgsquote vom Nachbarn empfangener Pakete </li>
   <li> <b>NLQ</b>: Erfolgsquote zum Nachbarn gesendeter Pakete </li>
   <li> <b>ETX</b>: zu erwartende Sendeversuche pro Paket (k&uuml;nstlicher Multiplikator wird angezeigt)</li>
   <li>
   <ul>
    <li> <b><font color='green'>Gr&uuml;n</font></b>: sehr gut (ETX < 2) </li>
    <li> <b><font color='yellow'>Gelb</font></b>: gut (2 < ETX < 4) </li>
    <li> <b><font color='orange'>Orange</font></b>: noch nutzbar (4 < ETX < 10) </li>
    <li> <b><font color='red'>Rot</font></b>: schlecht (ETX > 10) </li>
   </ul>
   </li>
   <li> <b>SNR</b>: Signal/Noise-Ratio = Signal/Rausch-Abstand [dB] </li>
   <li>
   <ul>
    <li> <b><font color='green'>Gr&uuml;n</font></b>: sehr gut (SNR > 30) </li>
    <li> <b><font color='yellow'>Gelb</font></b>: gut (30 > SNR > 20) </li>
    <li> <b><font color='orange'>Orange</font></b>: noch nutzbar (20 > SNR > 5) </li>
    <li> <b><font color='red'>Rot</font></b>: schlecht (SNR < 5) </li>
   </ul>
   </li>
  </ul>

 </body>
</html>
EOF
