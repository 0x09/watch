#!/bin/bash
# watch - very simple application usage logger for OS X
# Copyright 2014-2016 0x09.net.

db="$HOME/Library/Application Support/net.0x09.watch/watch.db"
launchagent="$HOME/Library/LaunchAgents/net.0x09.watch.plist"

AWK=awk
have_gawk=0
if command -v gawk 2&>/dev/null; then
	AWK=gawk # for strftime
	have_gawk=1
fi

sub=$1
shift
case "$sub" in
	start)
		launchctl unload "$launchagent" 2> /dev/null
		launchctl load "$launchagent"
	;;
	stop) launchctl unload "$launchagent";;
	query) sqlite3 "$db" "$1";;
	last)
		sqlite3 "$db" "select
			(case when idle = 1 then '🕒 ' else ' ' end),
			(case when name = '' then ' ' else name end),
			datetime(time,'unixepoch','localtime'),
			printf('%8.2f',duration/1e9)
			from events natural join applications order by time desc limit $1
		" | column -ts'|' | tail -r;;
	since)
		sqlite3 "$db" "select
			(case when idle = 1 then '🕒 ' else ' ' end),
			(case when name = '' then ' ' else name end),
			datetime(time,'unixepoch','localtime'),
			printf('%8.2f',duration/1e9)
			from events natural join applications where datetime(time,'unixepoch','localtime') >= '$1' order by time
		" | column -ts'|';;
	totals)
		idle=false
		min=5
		perday="-86400+max" #so days = 1...
		while getopts "aif:t:m:d" opt; do
			case $opt in
				i) idle=true;;
				f) from="$(TZ=UTC date -jf "%F %T %z" "$OPTARG" +%s)";;
				t) to="$(TZ=UTC date -jf "%F %T %z" "$OPTARG" +%s)";;
				m) min="$OPTARG";;
				d) perday=min;;
				a) idle=true; unset -v min from to;;
			esac
		done
		$idle || filters+=" and idle = 0"
		[ -n "$from" ] && filters+=" and time > $from"
		[ -n "$to"   ] && filters+=" and time <= $to"
		[ -n "$min"  ] && filters+=" and duration > $min*1e9"
		[ -n "$filters" ] && filters="where ${filters:5}"

		sqlite3 "$db" "
			select sum(duration),'*',$perday(time),max(time),min(time) from events $filters;
			select sum(duration),name from events natural join applications $filters group by name order by sum(duration) desc
		" | $AWK -v have_gawk=$have_gawk '
			function format(ts){
				ts/=1e9;
				return sprintf("%u:%02u:%02u:%02u",ts/86400,int(ts/3600)%24,int(ts/60)%60,ts%60)
			}
			BEGIN{ FS="|" }
			NR==1{
				total=$1;
				if(have_gawk)
					print "since",strftime("%F %T %z",$5)
				days=($4-$3)/86400
			}
			$1>5*60*1e9 { printf("%s|%s|%6.2f%%\n",$2,format($1/days),$1*100/total) }
		' | column -ts'|'
	;;
	help)
		printf "watch.sh: very simple application usage logger frontend
Usage: watch.sh [start|stop|query|last|since|totals|help]

start/stop        - control the monitoring daemon
query <sql>       - directly query the log db via the sqlite command line application (see watch.sh query '.schema')
last <n>          - show the last n events
since <datetime>  - show all events since the given ISO 8601-formatted date
totals <opts>     - show running usage total. suboptions:
   -i               - include idle times in total (false)
   -f:-t <datetime> - from/to: limit totals to specified ISO 8601 timerange
   -m <seconds>     - minimum event duration to include in totals (5s)
   -d               - show per-day average usage rather than sum
   -a               - include everything
";;
	*) printf "Usage: watch.sh [start|stop|query|last|since|totals|help]\n";;
esac
