#
# libbench.tcl <testPattern> <interp> <outChannel> <benchFile1> ?...?
#
# This file has to have code that works in any version of Tcl that
# the user would want to benchmark.
#

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
    global tcl_platform env
    if {[info exists tcl_platform(platform)]} {
	if {$tcl_platform(platform) == "unix"} {
	    return "/tmp/tclbench.dat"
	} elseif {$tcl_platform(platform) == "windows"} {
	    return [file join $env(TEMP) "tclbench.dat"]
	} else {
	    return "tclbench.dat"
	}
    } else {
	# The Good Ol' Days (?) when only Unix support existed
	return "/tmp/tclbench.dat"
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
    while {[llength $args]} {
	set key [lindex $args 0]
	switch -glob -- $key {
	    -pr*	{ set opts(-pre)  [lindex $args 1] }
	    -po*	{ set opts(-post) [lindex $args 1] }
	    -bo*	{ set opts(-body) [lindex $args 1] }
	    -de*	{ set opts(-desc) [lindex $args 1] }
	    -it*	{ set opts(-iter) [lindex $args 1] }
	    default {
		error "unknown option $key"
	    }
	}
	set args [lreplace $args 0 1]
    }
    if {($BENCH(MATCH) != "") && ![string match $BENCH(MATCH) $opts(-desc)]} {
	return
    }
    if {$opts(-pre) != ""} {
	uplevel \#0 $opts(-pre)
    }
    if {![info exists BENCH(index)]} {
	set BENCH(index) 1
    }
    if {$opts(-body) != ""} {
	# always run it once to remove compile phase confusion
	catch {uplevel \#0 $opts(-body)}
	set code [catch {uplevel \#0 \
		[list time $opts(-body) $opts(-iter)]} res]
	if {$code == 0} {
	    # Get just the microseconds value from the time result
	    set res [lindex $res 0]
	} elseif {$code != 666} {
	    # A 666 result code means pass it through to the bench suite.
	    # Otherwise throw errors all the way out, unless we specified
	    # not to throw errors (option -errors 0 to libbench).
	    if {$BENCH(ERRORS)} {
		return -code $code -errorinfo $errorInfo -errorcode $errorCode
	    } else {
		set res "ERR"
	    }
	}
	set bench([format "%.3d" $BENCH(index)]) [list $opts(-desc) $res]
	incr BENCH(index)
    }
    if {$opts(-post) != ""} {
	uplevel \#0 $opts(-post)
    }
    return
}

proc usage {} {
    set me [file tail [info script]]
    puts stderr "Usage: $me ?options?\
	    \n\t-help			# print out this message\
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
set BENCH(ERRORS)	1
set BENCH(MATCH)	{}
set BENCH(OUTFILE)	stdout
set BENCH(FILES)	{}
set BENCH(ITERS)	1000

if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	switch -glob -- $key {
	    -help*	{ usage }
	    -err*	{ set BENCH(ERRORS)  [lindex $argv 1] }
	    -int*	{ set BENCH(INTERP) [lindex $argv 1] }
	    -mat*	{ set BENCH(MATCH) [lindex $argv 1] }
	    -iter*	{ set BENCH(ITERS) [lindex $argv 1] }
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

if {[string compare $BENCH(OUTFILE) stdout]} {
    set BENCH(OUTFID) [open $BENCH(OUTFILE) w]
} else {
    set BENCH(OUTFID) stdout
}

rename exit exit.true
proc exit args {
    error "called \"exit $args\" in benchmark test"
}

#
# Everything that gets output must be in pairwise format, because
# the data will be collected in via an 'array set'.
#

foreach file $BENCH(FILES) {
    if {[file exists $file]} {
	puts $BENCH(OUTFID) [list Sourcing $file]
	source $file
    }
}

foreach i [array names bench] {
    puts $BENCH(OUTFID) [list $i $bench($i)]
}

exit.true ; # needed for Tk tests
