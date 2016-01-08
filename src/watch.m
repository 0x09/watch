// watch - very simple application usage logger for OS X
// Copyright 2014-2016 0x09.net.

#include <Cocoa/Cocoa.h>
#include <sqlite3.h>
#include <mach/mach_time.h>
#include "idle.h"

int main(int argc, char* argv[]) {
@autoreleasepool {
	signal(SIGTERM,SIG_IGN);
	dispatch_source_t sigterm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
	dispatch_source_set_event_handler(sigterm,^{
		CFRunLoopStop(CFRunLoopGetMain());
	});
	dispatch_resume(sigterm);

	mach_timebase_info_data_t tb = iocputimebase();

	dispatch_queue_t writequeue = dispatch_queue_create(NULL,DISPATCH_QUEUE_SERIAL);

	__block sqlite3* db;
	__block sqlite3_stmt* ins,* insapp;
	dispatch_async(writequeue,^{
		NSURL* dbpath = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"net.0x09.watch"];
		const char* dbfile = [[dbpath URLByAppendingPathComponent:@"watch.db"] fileSystemRepresentation];
		if(sqlite3_open_v2(dbfile,&db,SQLITE_OPEN_READWRITE,NULL)) {
			if(![[NSFileManager defaultManager] createDirectoryAtURL:dbpath withIntermediateDirectories:YES attributes:nil error:nil] ||
				sqlite3_open_v2(dbfile,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,NULL))
				exit(1);
			sqlite3_exec(db,
				"CREATE TABLE applications("
					"application INTEGER PRIMARY KEY,"
					"name TEXT NOT NULL DEFAULT(''),"
					"bundle TEXT NOT NULL DEFAULT(''),"
					"UNIQUE(name,bundle) ON CONFLICT IGNORE"
				");"
				"CREATE TABLE events("
					"time DATETIME,"
					"duration INTEGER,"
					"idle BOOLEAN,"
					"application INTEGER REFERENCES applications ON UPDATE CASCADE"
				");",
			NULL,NULL,NULL);
		}
		sqlite3_exec(db,
			"PRAGMA journal_mode = WAL;"
			"PRAGMA synchronous = NORMAL;"
			"PRAGMA temp_store = MEMORY;",
		NULL,NULL,NULL);
		sqlite3_prepare_v2(db,"INSERT INTO applications(name,bundle) VALUES (ifnull(?,''),ifnull(?,''))",-1,&insapp,NULL);
		sqlite3_prepare_v2(db,"INSERT INTO events VALUES (?,?,?,(SELECT application FROM applications WHERE name = ifnull(?,'') AND bundle = ifnull(?,'')))",-1,&ins,NULL);
	});

	NSOperationQueue* notequeue = [NSOperationQueue new];
	NSNotificationCenter* nc = [[NSWorkspace sharedWorkspace] notificationCenter];
	NSNotificationCenter* dc = [NSNotificationCenter defaultCenter];
	__block uint64_t last = 0;
	__block bool is_idle = false;
	id activeobserver = [nc addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:notequeue
		usingBlock:^(NSNotification* n){
			uint64_t cputime = iocputime_with_base(tb);
			is_idle = ioisidle();
			time_t walltime = time(NULL);
			NSRunningApplication* app = [n userInfo][NSWorkspaceApplicationKey];
			dispatch_async(writequeue,^{
				if(last) {
					sqlite3_step(insapp);
					sqlite3_reset(insapp);
					sqlite3_bind_int64(ins,2,cputime-last);
					sqlite3_step(ins);
					sqlite3_reset(ins);
				}
				const char* name = [app.localizedName UTF8String];
				const char* bundle = [app.bundleIdentifier UTF8String];
				sqlite3_bind_text(insapp,1,name,-1,SQLITE_TRANSIENT);
				sqlite3_bind_text(insapp,2,bundle,-1,SQLITE_TRANSIENT);
				sqlite3_bind_int64(ins,1,walltime);
				sqlite3_bind_int(ins,3,is_idle);
				sqlite3_bind_text(ins,4,name,-1,SQLITE_TRANSIENT);
				sqlite3_bind_text(ins,5,bundle,-1,SQLITE_TRANSIENT);
				last = cputime;
			});
	}];
	id idleobserver = [dc addObserverForName:@"IOWentIdle" object:nil queue:notequeue
		usingBlock:^(NSNotification* n){
			if(!is_idle) {
				time_t walltime = ((NSNumber*)[n userInfo][@"walltime"]).unsignedLongLongValue / 1000000000;
				uint64_t idletime = ((NSNumber*)[n userInfo][@"at"]).unsignedLongLongValue;
				is_idle = true;
				dispatch_async(writequeue,^{
					uint64_t cputime = last > idletime ? last : idletime;
					sqlite3_step(insapp);
					sqlite3_reset(insapp);
					sqlite3_bind_int64(ins,2,cputime-last);
					sqlite3_step(ins);
					sqlite3_reset(ins);
					if(last < idletime)
						sqlite3_bind_int64(ins,1,walltime);
					sqlite3_bind_int(ins,3,true);
					last = cputime;
				});
			}
	}];
	id returnobserver = [dc addObserverForName:@"IOReturnedFromIdle" object:nil queue:notequeue
		usingBlock:^(NSNotification* n){
			if(is_idle) {
				uint64_t margin = ((NSNumber*)[n userInfo][@"margin"]).unsignedLongLongValue;
				time_t walltime = (((NSNumber*)[n userInfo][@"walltime"]).unsignedLongLongValue - margin/2) / 1000000000;
				uint64_t returntime = ((NSNumber*)[n userInfo][@"at"]).unsignedLongLongValue - margin/2;
				dispatch_async(writequeue,^{
					uint64_t cputime = last > returntime ? last : returntime;
					sqlite3_step(insapp);
					sqlite3_reset(insapp);
					sqlite3_bind_int64(ins,2,cputime-last);
					sqlite3_step(ins);
					sqlite3_reset(ins);
					if(last < returntime)
						sqlite3_bind_int64(ins,1,walltime);
					sqlite3_bind_int(ins,3,false);
					last = cputime;
				});
				is_idle = false;
			}
	}];
	id sleepobserver = [nc addObserverForName:NSWorkspaceWillSleepNotification object:nil queue:notequeue usingBlock:^(NSNotification* n){
		uint64_t cputime = iocputime_with_base(tb);
		dispatch_async(writequeue,^{
			sqlite3_step(insapp);
			sqlite3_reset(insapp);
			sqlite3_bind_int64(ins,2,cputime-last);
			sqlite3_step(ins);
			sqlite3_reset(ins);
			last = 0;
		});
	}];
	id wakeobserver = [nc addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:notequeue usingBlock:^(NSNotification* n){
		[nc postNotificationName:NSWorkspaceDidActivateApplicationNotification object:nil
			userInfo:@{NSWorkspaceApplicationKey:[[NSWorkspace sharedWorkspace] frontmostApplication]}
		];
	}];
	[nc postNotificationName:NSWorkspaceDidActivateApplicationNotification object:nil
		userInfo:@{NSWorkspaceApplicationKey:[[NSWorkspace sharedWorkspace] frontmostApplication]}
	];
	ioidlelisten();
	CFRunLoopRun();
	[nc postNotificationName:NSWorkspaceDidActivateApplicationNotification object:nil];
	[nc removeObserver:activeobserver];
	[dc removeObserver:idleobserver];
	[dc removeObserver:returnobserver];
	[dc removeObserver:sleepobserver];
	[dc removeObserver:wakeobserver];
	[notequeue waitUntilAllOperationsAreFinished];
	dispatch_sync(writequeue,^{
		sqlite3_finalize(insapp);
		sqlite3_finalize(ins);
		sqlite3_close(db);
	});
}
}