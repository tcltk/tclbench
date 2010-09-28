#
# libbench.tcl <testPattern> <interp> <outChannel> <benchFile1> ?...?
#
# This file has to have code that works in any version of Tcl that
# the user would want to benchmark.
#
# RCS: @(#) $Id: libbench.tcl,v 1.15 2010/09/28 00:05:14 hobbs Exp $
#
# Copyright (c) 2000-2001 Jeffrey Hobbs.

# We will put our data into these named globals
global BENCH bench

#
# We claim all procedures starting with bench*
#

# bench_tmpfile --
#
#   Return a temp file name that can be modified at will
#
# Arguments:
#   None
#
# Results:
#   Returns file name
#
proc bench_tmpfile {} {
    global tcl_platform env BENCH
    if {![info exists BENCH(uniqid)]} { set BENCH(uniqid) 0 }
    set base "tclbench[incr BENCH(uniqid)].dat"
    if {[info exists tcl_platform(platform)]} {
	if {$tcl_platform(platform) == "unix"} {
	    return "/tmp/$base"
	} elseif {$tcl_platform(platform) == "windows"} {
	    return [file join $env(TEMP) $base]
	} else {
	    return $base
	}
    } else {
	# The Good Ol' Days (?) when only Unix support existed
	return "/tmp/$base"
    }
}

# bench_rm --
#
#   Remove a file silently (no complaining)
#
# Arguments:
#   args	Files to delete
#
# Results:
#   Returns nothing
#
proc bench_rm {args} {
    foreach file $args {
	if {[info tclversion] > 7.4} {
	    catch {file delete $file}
	} else {
	    catch {exec /bin/rm $file}
	}
    }
}

# bench --
#
#   Main bench procedure.
#   The bench test is expected to exit cleanly.  If an error occurs,
#   it will be thrown all the way up.  A bench proc may return the
#   special code 666, which says take the string as the bench value.
#   This is usually used for N/A feature situations.
#
# Arguments:
#
#   -pre	script to run before main timed body
#   -body	script to run as main timed body
#   -post	script to run after main timed body
#   -desc	message text
#   -iterations	<#>
#
# Results:
#
#   Returns nothing
#
# Side effects:
#
#   Sets up data in bench global array
#
proc bench {args} {
    global BENCH bench errorInfo errorCode

    # -pre script
    # -body script
    # -desc msg
    # -post script
    # -iterations <#>
    array set opts {
	-pre	{}
	-body	{}
	-desc	{}
	-post	{}
    }
    set opts(-iter) $BENCH(ITERS)
    set opts(-autoscale) $BENCH(AUTOSCALE)
    while {[llength $args]} {
	set key [lindex $args 0]
	set val [lindex $args 1]
	switch -glob -- $key {
	    -auto*	{ set opts(-autoscale) $val }
	    -res*	{ set opts(-res)  $val }
	    -pr*	{ set opts(-pre)  $val }
	    -po*	{ set opts(-post) $val }
	    -bo*	{ set opts(-body) $val }
	    -de*	{ set opts(-desc) $val }
	    -it*	{
		# Only change the iterations when it is smaller than
		# the requested default
		if {$opts(-iter) > $val} { set opts(-iter) $val }
	    }
	    default {
		error "unknown option $key"
	    }
	}
	set args [lreplace $args 0 1]
    }
    if {($BENCH(MATCH) != "") && ![string match $BENCH(MATCH) $opts(-desc)]} {
	return
    }
    if {($BENCH(RMATCH) != "") && ![regexp $BENCH(RMATCH) $opts(-desc)]} {
	return
    }
    if {$opts(-pre) != ""} {
	uplevel \#0 $opts(-pre)
    }
    if {$opts(-body) != ""} {
	# always run it once to remove compile phase confusion
	set code [catch {uplevel \#0 $opts(-body)} res]
	if {!$code && [info exists opts(-res)] \
		&& [string compare $opts(-res) $res]} {
	    if {$BENCH(ERRORS)} {
		return -code error "Result was:\n$res\nResult\
			should have been:\n$opts(-res)"
	    } else {
		set res "BAD_RES"
	    }
	    set bench($opts(-desc)) $res
	    puts $BENCH(OUTFID) [list Sourcing "$opts(-desc): $res"]
	} else {
	    set iter $opts(-iter)
	    if {!$code && $opts(-autoscale)} {
		# Ensure total test runtime is 0.1s < $runtime < 4s.
		# time reports in microsecs.
		# Do 2nd call to remove catch variance
		set runtime [lindex [uplevel \#0 [list time $opts(-body) 1]] 0]
		if {$runtime*$iter < 100000} {
		    set iter [expr {int(100000.0/$runtime)}]
		} elseif {($runtime*$iter/1000.) > 5000} {
		    set iter [expr {int(4000000.0/$runtime)}]
		    if {$iter < 8} { set iter 8 }
		}
	    }
	    set code [catch {uplevel \#0 [list time $opts(-body) $iter]} res]
	    if {!$BENCH(THREADS)} {
		if {$code == 0} {
		    # Get just the microseconds value from the time result
		    set res [lindex $res 0]
		} elseif {$code != 666} {
		    # A 666 result code means pass it through to the bench
		    # suite. Otherwise throw errors all the way out, unless
		    # we specified not to throw errors (option -errors 0 to
		    # libbench).
		    if {$BENCH(ERRORS)} {
			return -code $code -errorinfo $errorInfo \
				-errorcode $errorCode
		    } else {
			set res "ERR"
		    }
		}
		set bench($opts(-desc)) $res
		puts $BENCH(OUTFID) [list Sourcing "$opts(-desc): $res"]
	    } else {
		# Threaded runs report back asynchronously
		thread::send $BENCH(us) \
			[list thread_report $opts(-desc) $code $res]
	    }
	}
    }
    if {($opts(-post) != "") && [catch {uplevel \#0 $opts(-post)} err] \
	    && $BENCH(ERRORS)} {
	return -code error "post code threw error:\n$err"
    }
    return
}

proc usage {} {
    set me [file tail [info script]]
    puts stderr "Usage: $me ?options?\
	    \n\t-help			# print out this message\
	    \n\t-rmatch <regexp>	# only run tests matching this pattern\
	    \n\t-match <glob>		# only run tests matching this pattern\
	    \n\t-interp	<name>		# name of interp (tries to get it right)\
	    \n\tfileList		# files to benchmark"
    exit 1
}

#
# Process args
#
if {[catch {set BENCH(INTERP) [info nameofexec]}]} {
    set BENCH(INTERP) $argv0
}
foreach {var val} {
	ERRORS		1
	MATCH		{}
	RMATCH		{}
	OUTFILE		stdout
	FILES		{}
	ITERS		5000
	AUTOSCALE	1
	THREADS		0
	EXIT		"[info exists tk_version]"
} {
    if {![info exists BENCH($var)]} {
	set BENCH($var) [subst $val]
    }
}
set BENCH(EXIT) 1

if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	set val [lindex $argv 1]
	switch -glob -- $key {
	    -help*	{ usage }
	    -err*	{ set BENCH(ERRORS)  $val }
	    -int*	{ set BENCH(INTERP)  $val }
	    -rmat*	{ set BENCH(RMATCH)  $val }
	    -mat*	{ set BENCH(MATCH)   $val }
	    -auto*	{ set BENCH(AUTOSCALE) $val }
	    -iter*	{ set BENCH(ITERS)   $val }
	    -thr*	{ set BENCH(THREADS) $val }
	    default {
		foreach arg $argv {
		    if {![file exists $arg]} { usage }
		    lappend BENCH(FILES) $arg
		}
		break
	    }
	}
	set argv [lreplace $argv 0 1]
    }
}

if {$BENCH(THREADS)} {
    # We have to be able to load threads if we want to use threads, and
    # we don't want to create more threads than we have files.
    if {[catch {package require Thread}]} {
	set BENCH(THREADS) 0
    } elseif {[llength $BENCH(FILES)] < $BENCH(THREADS)} {
	set BENCH(THREADS) [llength $BENCH(FILES)]
    }
}

rename exit exit.true
proc exit args {
    error "called \"exit $args\" in benchmark test"
}

if {[string compare $BENCH(OUTFILE) stdout]} {
    set BENCH(OUTFID) [open $BENCH(OUTFILE) w]
} else {
    set BENCH(OUTFID) stdout
}

#
# Everything that gets output must be in pairwise format, because
# the data will be collected in via an 'array set'.
#

if {$BENCH(THREADS)} {
    # Each file must run in it's own thread because of all the extra
    # header stuff they have.
    #set DEBUG 1
    proc thread_one {{id 0}} {
	global BENCH
	set file [lindex $BENCH(FILES) 0]
	set BENCH(FILES) [lrange $BENCH(FILES) 1 end]
	if {[file exists $file]} {
	    incr BENCH(inuse)
	    puts $BENCH(OUTFID) [list Sourcing $file]
	    if {$id} {
		set them $id
	    } else {
		set them [thread::create]
		thread::send -async $them { load {} Thread }
		thread::send -async $them \
			[list array set BENCH [array get BENCH]]
		thread::send -async $them \
			[list proc bench_tmpfile {} [info body bench_tmpfile]]
		thread::send -async $them \
			[list proc bench_rm {args} [info body bench_rm]]
		thread::send -async $them \
			[list proc bench {args} [info body bench]]
	    }
	    if {[info exists ::DEBUG]} {
		puts stderr "SEND [clock seconds] thread $them $file INUSE\
		$BENCH(inuse) of $BENCH(THREADS)"
	    }
	    thread::send -async $them [list source $file]
	    thread::send -async $them \
		    [list thread::send $BENCH(us) [list thread_ready $them]]
	    #thread::send -async $them { thread::unwind }
	}
    }

    proc thread_em {} {
	global BENCH
	while {[llength $BENCH(FILES)]} {
	    if {[info exists ::DEBUG]} {
		puts stderr "THREAD ONE [lindex $BENCH(FILES) 0]"
	    }
	    thread_one
	    if {$BENCH(inuse) >= $BENCH(THREADS)} {
		break
	    }
	}
    }

    proc thread_ready {id} {
	global BENCH

	incr BENCH(inuse) -1
	if {[llength $BENCH(FILES)]} {
	    if {[info exists ::DEBUG]} {
		puts stderr "SEND ONE [clock seconds] thread $id"
	    }
	    thread_one $id
	} else {
	    if {[info exists ::DEBUG]} {
		puts stderr "UNWIND thread $id"
	    }
	    thread::send -async $id { thread::unwind }
	}
    }

    proc thread_report {desc code res} {
	global BENCH bench errorInfo errorCode

	if {$code == 0} {
	    # Get just the microseconds value from the time result
	    set res [lindex $res 0]
	} elseif {$code != 666} {
	    # A 666 result code means pass it through to the bench suite.
	    # Otherwise throw errors all the way out, unless we specified
	    # not to throw errors (option -errors 0 to libbench).
	    if {$BENCH(ERRORS)} {
		return -code $code -errorinfo $errorInfo \
			-errorcode $errorCode
	    } else {
		set res "ERR"
	    }
	}
	set bench($desc) $res
    }

    proc thread_finish {{delay 4000}} {
	global BENCH bench
	set val [expr {[llength [thread::names]] > 1}]
	#set val [expr {$BENCH(inuse)}]
	if {$val} {
	    after $delay [info level 0]
	} else {
	    foreach desc [array names bench] {
		puts $BENCH(OUTFID) [list $desc $bench($desc)]
	    }
	    if {$BENCH(EXIT)} {
		exit.true ; # needed for Tk tests
	    }
	}
    }

    set BENCH(us) [thread::id]
    set BENCH(inuse) 0 ; # num threads in use
    puts $BENCH(OUTFID) [list __THREADED [package provide Thread]]

    thread_em
    thread_finish
    vwait forever
} else {
    foreach BENCH(file) $BENCH(FILES) {
	if {[file exists $BENCH(file)]} {
	    puts $BENCH(OUTFID) [list Sourcing $BENCH(file)]
	    source $BENCH(file)
	}
    }

    foreach desc [array names bench] {
	puts $BENCH(OUTFID) [list $desc $bench($desc)]
    }

    if {$BENCH(EXIT)} {
	exit.true ; # needed for Tk tests
    }
}
