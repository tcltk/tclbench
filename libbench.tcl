#
# libbench.tcl <interp> <outChannel> <benchFile1> ?<benchFile2> ...?
#

# Not all interpreters support [file delete]
if {[info exists tcl_platform(platform)]} {
    if {$tcl_platform(platform) == "unix"} {
	set TMPFILE /tmp/tmpbench.file
	set deleteCommand "/bin/rm"
    } elseif {$tcl_platform(platform) == "windows"} {
	set TMPFILE [file join $env(TEMP) tmpbench.file]
	set deleteCommand "$env(COMSPEC) /c del"
    }
} else {
    # The Good Ol' Days (?) when only Unix support existed
    set TMPFILE /tmp/tmpbench.file
    set deleteCommand "/bin/rm"
}

# bench --
#
#   main bench procedure
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
    global bench errorInfo errorCode
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
    if {$opts(-pre) != ""} {
	uplevel \#0 $opts(-pre)
    }
    if {$opts(-body) != ""} {
	set code [catch {uplevel \#0 \
		[list time $opts(-body) $opts(-iter)]} res]
	if {$code && ($code != 666)} {
	    return -code $code -errorinfo $errorInfo -errorcode $errorCode
	}
	set bench($bench(major)) [list $opts(-desc) [lindex $res 0]]
	incr bench(major)
    }
    if {$opts(-post) != ""} {
	uplevel \#0 $opts(-post)
    }
    return
}

set MY_INTERP [lindex $argv 0]
set outfile [lindex $argv 1]
if {[string compare $outfile stdout]} {
    set outfid [open $outfile w]
} else {
    set outfid stdout
}
set argv [lreplace $argv 0 1]

rename exit exit.true
proc exit args {
    error "called \"exit $args\" in benchmark test"
}

foreach file $argv {
    if {[file exists $file]} {
	puts $outfid [list Sourcing $file]
	source $file
    }
}

foreach i [lsort -integer [array names bench {[0-9]*}]] {
    puts $outfid "$i [list $bench($i)]"
}

exit.true ; # needed for Tk tests
