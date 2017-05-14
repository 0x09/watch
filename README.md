watch - very simple application usage logger for OS X 10.7+

watch is a small, low footprint launchd daemon that listens for application switches and idle states and logs events to a simple sqlite database.

# Building
	make && make install

installs the binary, launchd plist, and a small shell frontend. To (re)start the daemon and begin logging, use

	watch.sh start

To remove, `make uninstall`. To remove and get rid of the log db entirely, `make purge`.

# Use
watch.sh is a very thin frontend over sqlite's command line application that allows easy access to the db and some obvious statistics.

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

Note that some functions of the shell script require sqlite 3.8.3, available in OS X 10.10+ and on previous versions via [homebrew](http://brew.sh).