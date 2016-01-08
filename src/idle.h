// watch - very simple application usage logger for OS X
// Copyright 2014-2016 0x09.net.

#include <stdbool.h>
#include <mach/mach_time.h>
#include <sys/time.h>

uint64_t iogetidletime(void);
void ioidlelisten(void);
bool ioisidle(void);

static inline mach_timebase_info_data_t iocputimebase() {
	mach_timebase_info_data_t tb;
	mach_timebase_info(&tb);
	return tb;
}
static inline uint64_t iocputime_with_base(mach_timebase_info_data_t tb) { return mach_absolute_time() * tb.numer / tb.denom; }

static inline uint64_t iorealtime() {
	struct timeval tv;
	gettimeofday(&tv,NULL);
	return tv.tv_sec*1000000000ULL + tv.tv_usec*1000ULL;
}