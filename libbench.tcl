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
    global tcl_platform
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
    if {![info exists bench(major)]} {
	set bench(major) 1
	set bench(minor) 1
    }
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
	-iter	2000
    }
    while {[llength $args]} {
	set key [lindex $args 0]
	switch -glob -- $key {
	    -pr*	{ set opts(-pre) [lindex $args 1] }
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
    if {($BENCH(PATTERN) != "") && \
	    ![string match $BENCH(PATTERN) $opts(-desc)]} {
	return
    }
    if {$opts(-pre) != ""} {
	uplevel \#0 $opts(-pre)
    }
    if {$opts(-body) != ""} {
	set code [catch {uplevel \#0 \
		[list time $opts(-body) $opts(-iter)]} res]
	if {$code == 0} {
	    set bench($bench(major)) [list $opts(-desc) [lindex $res 0]]
	} elseif {$code == 666} {
	    if {$res == ""} { set res "N/A" }
	    set bench($bench(major)) [list $opts(-desc) $res]
	} else {
	    return -code $code -errorinfo $errorInfo -errorcode $errorCode
	}
	incr bench(major)
    }
    if {$opts(-post) != ""} {
	uplevel \#0 $opts(-post)
    }
    return
}

set BENCH(PATTERN)	[lindex $argv 0]
set BENCH(INTERP)	[lindex $argv 1]
set BENCH(OUTFILE)	[lindex $argv 2]
set argv [lreplace $argv 0 2]

if {[string compare $BENCH(OUTFILE) stdout]} {
    set BENCH(OUTFID) [open $BENCH(OUTFILE) w]
} else {
    set BENCH(OUTFID) stdout
}

rename exit exit.true
proc exit args {
    error "called \"exit $args\" in benchmark test"
}

foreach file $argv {
    if {[file exists $file]} {
	puts $BENCH(OUTFID) [list Sourcing $file]
	source $file
    }
}

foreach i [lsort -integer [array names bench {[0-9]*}]] {
    puts $BENCH(OUTFID) "$i [list $bench($i)]"
}

exit.true ; # needed for Tk tests
