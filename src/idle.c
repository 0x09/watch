// watch - very simple application usage logger for OS X
// Copyright 2014-2016 0x09.net.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include "idle.h"

const unsigned long long
	kIdleThreshold   = 150ULL*NSEC_PER_SEC,
	kIdlePoll        = kIdleThreshold/3,
	kIdleTolerance   = kIdlePoll/5,
	kReturnPoll      =  5ULL*NSEC_PER_SEC,
	kReturnTolerance = kReturnPoll/1;

uint64_t iogetidletime() {
	io_registry_entry_t entry = IORegistryEntryFromPath(kIOMasterPortDefault,"IOService:/IOResources/IOHIDSystem");
	CFNumberRef n = IORegistryEntryCreateCFProperty(entry,CFSTR("HIDIdleTime"),kCFAllocatorDefault,0);
	int64_t nanoseconds = 0;
	CFNumberGetValue(n, kCFNumberSInt64Type, &nanoseconds);
	CFRelease(n);
	IOObjectRelease(entry);
	return nanoseconds;
}

bool ioisidle() { return iogetidletime() >= kIdleThreshold; }

void ioidlelisten() {
	mach_timebase_info_data_t tb = iocputimebase();

	dispatch_source_t idletimer   = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0));
	dispatch_source_t returntimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0));
	dispatch_source_set_timer(idletimer,  dispatch_time(DISPATCH_TIME_NOW,kIdlePoll),  kIdlePoll,  kIdleTolerance);
	dispatch_source_set_timer(returntimer,dispatch_time(DISPATCH_TIME_NOW,kReturnPoll),kReturnPoll,kReturnTolerance);

	__block uint64_t checkpoint = 0;
	dispatch_source_set_event_handler(returntimer,^{
		uint64_t idle = iogetidletime();
		uint64_t cputime = iocputime_with_base(tb);
		if(idle < kIdleThreshold) {
			uint64_t at = cputime - idle;
			uint64_t margin = at - checkpoint;
			uint64_t walltime = iorealtime() - idle;
			dispatch_async(dispatch_get_main_queue(),^{
				CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
				CFNumberRef cfat     = CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&at);
				CFNumberRef cfmargin = CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&margin);
				CFNumberRef cfwall   = CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&walltime);
				CFDictionaryRef userinfo = CFDictionaryCreate(
					kCFAllocatorDefault,
					(const void*[]){CFSTR("at"),CFSTR("margin"),CFSTR("walltime")},
					(const void*[]){cfat,cfmargin,cfwall},
					3,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks
				);
				CFNotificationCenterPostNotification(center,CFSTR("IOReturnedFromIdle"),NULL,userinfo,TRUE);
				CFRelease(cfat);
				CFRelease(cfmargin);
				CFRelease(cfwall);
			});
			dispatch_suspend(returntimer);
			dispatch_resume(idletimer);
		}
		checkpoint = cputime;
	});

	dispatch_source_set_event_handler(idletimer,^{
		uint64_t idle = iogetidletime();
		if(idle >= kIdleThreshold) {
			uint64_t cputime = iocputime_with_base(tb);
			uint64_t at = cputime - idle;
			uint64_t walltime = iorealtime() - idle;
			dispatch_async(dispatch_get_main_queue(),^{
				CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
				CFNumberRef cfat   =   CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&at);
				CFNumberRef cfidle =   CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&idle);
				CFNumberRef cfwall =   CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt64Type,&walltime);
				CFDictionaryRef userinfo = CFDictionaryCreate(
					kCFAllocatorDefault,
					(const void*[]){CFSTR("at"),CFSTR("idletime"),CFSTR("walltime")},
					(const void*[]){cfat,cfidle,cfwall},
					3,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks
				);
				CFNotificationCenterPostNotification(center,CFSTR("IOWentIdle"),NULL,userinfo,TRUE);
				CFRelease(cfat);
				CFRelease(cfidle);
				CFRelease(cfwall);
			});
			dispatch_suspend(idletimer);
			checkpoint = cputime;
			dispatch_resume(returntimer);
		}
	});

	dispatch_resume(ioisidle() ? returntimer : idletimer);
}
