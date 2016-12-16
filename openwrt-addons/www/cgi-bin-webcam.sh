#!/bin/sh
[ -n "$REMOTE_ADDR" ] && {
. /tmp/loader

cd /webcam || exit

_http header_mimetype_output 'application/x-tar' "webcam_${ANYADR}_$( date +%s ).tar"

LIST="$TMPDIR/webcam_filelist.txt"
# e.g. '02-20161209142507-01.jpg' or 'webcam.jpg'
ls -1t *'.jpg' >"$LIST"
sed -i 's/lastsnap.jpg/d' "$LIST"

[ -s "$LIST" ] && {
	read -r FILE <"$LIST"			# most recent
	END_MARKER="$( printf "\xFF\xD9" )"
	FILE_END="$( tail -c2 "$FILE" )"
	test "$END_MARKER" = "$FILE_END" || BADFILE="$FILE"	# we do not remove it later, if not fully written

	# e.g. download/cronjob like:
	# wget -O recent.bin http://$IP/cgi-bin-webcam.sh && mv recent.bin cam_$IP.$(date +%s).tar'
	tar -c -T "$LIST" -f -

	while read -r FILE; do {
		# test "$END_MARKER" = "$FILE_END"
		test -e "$FILE" -a "$FILE" != 'webcam.jpg' && {
			test "$FILE" = "$BADFILE" || rm "$FILE"
		}
	} done <"$LIST"
}

rm "$LIST"
}

pics2movie()
{
	local out codec file timestamp line j=0 i=0 oldest=0 newest=9999999999
	# scp 10.63.2.34:bigbrother/cam-{buero-innen,buero-aussen,muelltonne}/*.tar .
	mkdir 'pix' || return		# plain .jpg's from tar-files
	mkdir 'frames' || return	# sanitized pics converted to .png

	# unpack every tar and throw all files into dir 'pix' and order them
	for file in *.tar; do {
		j=$(( j + 1 ))
		tar -C 'pix' -xf "$file" || logger -s "error in '$file'"
		rm "$file"

		cd 'pix' || return 1
		ls -1 >"../frames/files.txt"
		while read -r line; do {
			timestamp="$( date +%s -r "$line" )"
			test $timestamp -gt $oldest && oldest=$timestamp
			test $timestamp -lt $newest && newest=$timestamp

			mv "$line" "../frames/img-$( date +%s -r "$line" ).jpg"
			i=$(( i + 1 ))
		} done <"../frames/files.txt"
		cd - >/dev/null || return
	} done
	logger -s "all files: $i in $j tars - oldest=$oldest=$( date -d @$oldest ) newest=$newest=$( date -d @$newest )"
	# Di 13. Dez 14:54:04 CET 2016
	# di 13  dez 14 54 04 cet 2016
	# 2016-13dez-14h54
	set -- $( date -d @$oldest | sed 's/[^0-9a-zA-Z]/ /g' | tr '[:upper:]' '[:lower:]' )
	oldest="$8-${2}$3-${4}h$5"
	set -- $( date -d @$newest | sed 's/[^0-9a-zA-Z]/ /g' | tr '[:upper:]' '[:lower:]' )
	newest="$8-${2}$3-${4}h$5"
	out="../$( pwd | sed 's|^.*/||' )_$( date +%s )_${newest}_${oldest}.mp4"	# dirname in which we are in, e.g. cam-buero-aussen

	# sanitize each picture in 'frames'
	cd frames || return
	codec='-c:v libx264 -pix_fmt yuv420p -preset ultrafast -crf 15 -profile:v baseline -level 3.0'
	ls -1rt | while read -r file; do {
		convert "$file" -resize 1280x720 -depth 24 -colorspace RGB ppm:-
		rm "$file"
	} done | ffmpeg -r 10 -f image2pipe -vcodec ppm -i - $codec -f mp4 "$out"

	cd - >/dev/null && rm -fR 'pix' 'frames'
}
