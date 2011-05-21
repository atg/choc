#import <Cocoa/Cocoa.h>
#import <getopt.h>

/*
	Usage: mate [-awl<number>rdnhv] [file ...]
	Options:
	 -a, --async            Do not wait for file to be closed by TextMate.
	 -w, --wait             Wait for file to be closed by TextMate.
	 -l, --line <number>    Place caret on line <number> after loading file.
	 -r, --recent           Add file to Open Recent menu.
	 -d, --change-dir       Change TextMates working directory to that of the file.
	 -n, --no-reactivation  After edit with -w, do not re-activate the calling app.
	 -h, --help             Show this information.
	 -v, --version          Print version information.
	
	If multiple files are given, a project is created consisting of these
	files, -a is then default and -w will be ignored (e.g. "mate *.tex").
	
	By default mate will not wait for the file to be closed
	except when used as filter:
	 ls *.tex|mate|sh      -w implied
	 mate -|cat -n         -w implied (read from stdin)
	
	An exception is made if the command is started as something which ends
	with "_wait". So to have a command with --wait as default, you can
	create a symbolic link like this:
	 ln -s mate mate_wait
*/

@interface ChocWaiter : NSObject
{
	NSDictionary *response;
}

- (id)runWorkspace;
- (id)run:(NSString *)identifier;
- (void)gotNotification:(NSNotification *)notif;
- (NSDictionary *)gotResponse;

@end

void help() {
	fprintf(stderr,
"Usage: choc [-awdnhv] [file ...]\n"
"Options:\n"
" -a, --async\t\tDo not wait for the user to close the file in Chocolat. [default if output is ignored]\n"
" -w, --wait\t\tWait for file to be closed by Chocolat. [default if output is piped]\n"
" -d, --change-dir\tChange Chocolat's working directory to that of the file.\n"
" -n, --no-reactivation\tAfter editing with -w, do not reactivate the calling app.\n"
" -h, --help\t\tShow this information.\n"
" -v, --version\t\tPrint version information.\n"
"\n"
"If multiple files are given, -w will be ignored.\n"
"\n"
"By default choc will not wait for the file to be closed except when the output is not to the console:\n"
" ls *.tex|choc|sh\t-w implied\n"
" choc foo.h > bar.h\t-w implied\n"
"\n"
	);
}

void version() {
//	fprintf(stderr, "choc r1 (2011-02-27)\n");
	fprintf(stderr, "choc r2 (2011-05-21)\n");
}

int main (int argc, char * const * argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	BOOL shouldWait = NO;
	
	int userWait = NO;
	int userAsync = NO;
	
	int shouldChangeDir = NO;
	int noReactiviation = NO;
	
	BOOL stdin_isa_tty = isatty(0);
	BOOL stdout_isa_tty = isatty(1);
	
	/* getopt_long stores the option index here. */
	int option_index = 0;
	int i = 0;
	
	id previousapp = [NSRunningApplication currentApplication];
	NSLog(@"previousapp = %@", previousapp);
	
	while (1)
	{
    	static struct option long_options[] = {
        	/* These options set a flag. */
	        {"async",			no_argument, 0,	'a'},
	        {"wait",			no_argument, 0,	'w'},
	        {"change-dir",		no_argument, 0,	'd'},
		    {"no-reactivation",	no_argument, 0,	'n'},
	        {"help",			no_argument, 0,	'h'},
	        {"version",			no_argument, 0,	'v'},
        	{0, 0, 0, 0}
        };
        		
		char c = getopt_long(argc, argv, "awdnhv",
						long_options, &option_index);
		
		i++;
		
		if (c == 'a')
			userAsync = YES;
		else if (c == 'w')
			userWait = YES;
		else if (c == 'd')
			shouldChangeDir = YES;
		else if (c == 'n')
			noReactiviation = YES;
		
		else if (c == 'h')
		{
			help();
			exit(0);
		}
		else if (c == 'v')
		{
			version();
			exit(0);
		}
		else if (c == '?')
		{
			break;
		}
		else if (c == -1)
		{
			break;
		}
	}
	
	if (userWait)
		shouldWait = YES;
	else if (userAsync)
		shouldWait = NO;
	else if (!stdout_isa_tty)
		shouldWait = YES;
	else
		shouldWait = NO;
	
	//Get remaining options
	NSMutableArray *remainingOptions = [[[NSMutableArray alloc] init] autorelease];
	while (i < argc)
	{
		const char *opt = argv[i++];
		[remainingOptions addObject:[[NSURL fileURLWithPath:[[[[NSString alloc] initWithUTF8String:opt] autorelease] stringByStandardizingPath]] path]];
	}
		
	if ([remainingOptions count] >= 2)
		shouldWait = NO;
	
	NSData *inData = nil;
	if ([remainingOptions count] == 0 || !stdin_isa_tty)
	{
		inData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
	}
	
	NSString *identifier = [NSString stringWithFormat:@"%lf", [NSDate timeIntervalSinceReferenceDate]];
	
	NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
	[userInfo setValue:[remainingOptions copy] forKey:@"files"];
	if (inData)
		[userInfo setValue:inData forKey:@"data"];
	[userInfo setValue:[NSNumber numberWithBool:shouldChangeDir] forKey:@"change-working-directory"];
	
	if (shouldChangeDir)
		[userInfo setValue:[[NSFileManager defaultManager] currentDirectoryPath] forKey:@"working-directory"];
	
	BOOL isLaunched = NO;
	NSArray *runningApps = [[NSWorkspace sharedWorkspace] launchedApplications];
	for (NSDictionary *rapp in runningApps)
	{
		NSString *bident = [rapp valueForKey:@"NSApplicationBundleIdentifier"];
		if ([[bident lowercaseString] isEqual:@"net.fileability.chocolat"] || [[bident lowercaseString] isEqual:@"com.chocolatapp.chocolat"] || [[bident lowercaseString] isEqual:@"com.fileability.chocolat"])
		{
			isLaunched = YES;
			break;
		}
	}
	
	// Has launched?
	if (!isLaunched)
	{
		[[NSWorkspace sharedWorkspace] launchApplication:@"Chocolat"];
		
		// How many seconds do we wait?
		NSRunLoop *theRL = [NSRunLoop currentRunLoop];
		
		[theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		ChocWaiter *waiter = [[[ChocWaiter alloc] init] runWorkspace];
		
		NSDictionary *response = nil;
		
		while (1)
		{
			if (response = [waiter gotResponse])
			{
				NSString *bident = [[response valueForKey:@"NSWorkspaceApplicationKey"] valueForKey:@"bundleIdentifier"];
				if ([[bident lowercaseString] isEqual:@"net.fileability.chocolat"] || [[bident lowercaseString] isEqual:@"com.chocolatapp.chocolat"] || [[bident lowercaseString] isEqual:@"com.fileability.chocolat"])
				{
					sleep(1);
					break;
				}
			}
			
			[theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		}
	}
	
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"net.fileability.choc-opened" object:identifier userInfo:userInfo deliverImmediately:NO];
	
	if (shouldWait)
	{
		NSRunLoop *theRL = [NSRunLoop currentRunLoop];
		
		[theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		ChocWaiter *waiter = [[[ChocWaiter alloc] init] run:identifier];
		
		NSDictionary *response = nil;
		
		while (1)
		{
			if (response = [waiter gotResponse])
				break;
			
			[theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		}
		
		// Output the data...
		if (!stdout_isa_tty)
		{
			NSData *responseData = [response objectForKey:@"data"];
			if (responseData)
			{
				NSFileHandle *stdoutFileHandle = [NSFileHandle fileHandleWithStandardOutput];
				[stdoutFileHandle writeData:responseData];
			}
		}
		
		// Reactivate the calling app
		if (!noReactiviation)
		{
			[previousapp activateWithOptions:0];
		}
	}
		
    // insert code here...
    [pool drain];
    return 0;
}

@implementation ChocWaiter

- (id)runWorkspace
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(gotNotification:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
	return self;
}
- (id)run:(NSString *)identifier
{
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(gotNotification:) name:@"net.fileability.choc-closed" object:identifier suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
	return self;
}
- (void)gotNotification:(NSNotification *)notif
{
	response = [[notif userInfo] copy];
}
- (NSDictionary *)gotResponse
{
	return response;
}

@end