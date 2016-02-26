CC ?= cc
CFLAGS := -Os -std=c99 $(CFLAGS)

# These are all hardcoded one way or another
PLISTPREFIX = ~/Library/LaunchAgents
SHAREPREFIX = ~/Library/Application\ Support
BINPREFIX = /usr/local/bin

all: watch
watch: src/watch.o src/idle.o
	$(CC) -framework Cocoa -framework IOKit -lsqlite3 $(CFLAGS) -o $@ $^

install: watch
	mkdir -p $(BINPREFIX) $(PLISTPREFIX)
	install watch $(BINPREFIX)/net.0x09.watch
	install src/net.0x09.watch.plist $(PLISTPREFIX)/
	install src/watch.sh $(BINPREFIX)/

uninstall:
	launchctl unload -F $(PLISTPREFIX)/net.0x09.watch.plist
	rm -f $(PLISTPREFIX)/net.0x09.watch.plist $(BINPREFIX)/net.0x09.watch $(BINPREFIX)/watch.sh

purge: uninstall
	rm -f $(SHAREPREFIX)/net.0x09.watch/watch.db
	rmdir $(SHAREPREFIX)/net.0x09.watch/

clean:
	rm -f src/*.o watch

.PHONY: all install uninstall purge clean
