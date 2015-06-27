#!/bin/sh

count_occurence_of_string()
{
	local string="$1"
	local tempfile='/tmp/count_occurence_of_string'
	local file

	find . -type f >"$tempfile"

	while read file; do {
		fgrep "$string" "$file"
	} done <"$tempfile" | wc -l

	rm "$tempfile"
}

list_all_function_names()
{
	local file line name name_sanitized
	local tempfile='/tmp/list_all_function_names'

	find . -type f >"$tempfile"

	while read file; do {
		while read line; do {
			case "$line" in
				*"()"*)
					case "$line" in
						[a-zA-Z]*)
							name="$( echo "$line" | cut -d'(' -f1 )"
							name="$( echo "$name" | sed 's/[ ]*$//g' )"	# strip trailing spaces
							name_sanitized="$( echo "$name" | sed 's/[^a-zA-Z0-9_]//g' )"
							[ "$name" = "$name_sanitized" ] && echo "$name"
						;;
					esac
				;;
			esac
		} done <"$file"
	} done <"$tempfile"

	rm "$tempfile"
}

for NAME in $( list_all_function_names ); do {
	echo "$( count_occurence_of_string "$NAME" ) x $NAME()"
} done

