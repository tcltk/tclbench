#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

# runbench.tcl ?options?
#
set RCS {RCS: @(#) $Id: runbench.tcl,v 1.11 2001/06/03 20:40:51 hobbs Exp $}
#
# Copyright (c) 2000-2001 Jeffrey Hobbs.

#
# Run the main script from an 8.2+ interp
#
if {[catch {package require Tcl 8.2}]} {
    set me [file tail [info script]]
    puts stderr "$me requires 8.2+ to run, although it can benchmark\
	    any Tcl v7+ interpreter"
    exit 1
}

regexp {,v (\d+\.\d+)} $RCS -> VERSION
set MYDIR [file dirname [info script]]
set ME [file tail [info script]]

proc usage {} {
    puts stderr "Usage (v$::VERSION): $::ME ?options?\
	    \n\t-help			# print out this message\
	    \n\t-iterations <#>		# max # of iterations to run a benchmark\
	    \n\t-minversion <version>	# minimum interp version to use\
	    \n\t-maxversion <version>	# maximum interp version to use\
	    \n\t-match <glob>		# only run tests matching this pattern\
	    \n\t-rmatch <regexp>	# only run tests matching this pattern\
	    \n\t-normalize <version>	# normalize numbers to given version\
	    \n\t-notcl			# do not run tclsh tests\
	    \n\t-notk			# do not run wish tests\
	    \n\t-output <text|list|csv>	# style of output from program (default: text)\
	    \n\t-paths <pathList>	# path or list of paths to search for interps\
	    \n\t-throwerrors		# propagate errors in benchmarks files\
	    \n\t-verbose		# output interim status info\
	    \n\tfileList		# files to source, files matching *tk*\
	    \n\t			# will be used for Tk benchmarks"
    exit 1
}

proc convertVersion {ver} {
    # We must modify the version number if an abp version
    # is specified, because the package mechanism will choke
    if {[string is double -strict -fail i $ver] == 0} {
	set ver [string range $ver 0 [expr {$i-1}]]
    }
    return $ver
}

#
# Process args
#
array set opts {
    paths	{}
    minver	0.0
    maxver	10.0
    match	{}
    rmatch	{}
    tcllist	{}
    tklist	{}
    tclsh	"tclsh?*"
    wish	"wish?*"
    usetk	1
    usetcl	1
    errors	0
    verbose	0
    output	text
    iters	1000
    norm	{}
}

if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	switch -glob -- $key {
	    -help*	{ usage }
	    -throw*	{
		# throw errors when they occur in benchmark files
		set opts(errors) 1
		set argv [lreplace $argv 0 0]
	    }
	    -iter*	{
		# Maximum iters to run a test
		# The test may set a smaller iter run, but anything larger
		# will be reduced.
		set opts(iters) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -min*	{
		# Allow a minimum version to search for,
		# restricted to version, not patchlevel
		set opts(minver) [convertVersion [lindex $argv 1]]
		set argv [lreplace $argv 0 1]
	    }
	    -max*	{
		# Allow a maximum version to search for,
		# restricted to version, not patchlevel
		set opts(maxver) [convertVersion [lindex $argv 1]]
		set argv [lreplace $argv 0 1]
	    }
	    -match*	{
		set opts(match) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -rmatch*	{
		set opts(rmatch) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -norm*	{
		set opts(norm) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -notcl	{
		set opts(usetcl) 0
		set argv [lreplace $argv 0 0]
	    }
	    -notk	{
		set opts(usetk) 0
		set argv [lreplace $argv 0 0]
	    }
	    -outp*	{
		# Output style
		set opts(output) [lindex $argv 1]
		if {![regexp {^(text|list|csv)$} $opts(output)]} { usage }
		set argv [lreplace $argv 0 1]
	    }
	    -path*	{
		# Support single dir path or multiple paths as a list
		if {[file isdir [lindex $argv 1]]} {
		    lappend opts(paths) [lindex $argv 1]
		} else {
		    foreach path [lindex $argv 1] {
			lappend opts(paths) $path
		    }
		}
		set argv [lreplace $argv 0 1]
	    }
	    -v*	{
		set opts(verbose) 1
		set argv [lreplace $argv 0 0]
	    }
	    default {
		foreach arg $argv {
		    if {![file exists $arg]} {
			usage
		    }
		    if {[string match *tk* $arg]} {
			lappend opts(tklist) $arg
		    } else {
			lappend opts(tcllist) $arg
		    }
		}
		break
	    }
	}
    }
}
if {[llength $opts(tcllist)] == 0 && [llength $opts(tklist)] == 0} {
    set opts(tcllist) [lsort [glob $MYDIR/tcl/*.bench]]
    set opts(tklist)  [lsort [glob $MYDIR/tk/*.bench]]
}

#
# Find available interpreters.
# The user PATH will be searched, unless specified otherwise by -paths.
# 
if {[llength $opts(paths)] == 0} {
    set pathSep [expr {($tcl_platform(platform) == "windows") ? ";" : ":"}]
    set opts(paths) [split $env(PATH) $pathSep]
}
# Hobbs override for precise testing
if {[info exists env(SNAME)]} {
    #set opts(paths) /home/hobbs/install/$env(SNAME)/bin
}

#
# Collect interp info from path(s)
#
proc getInterps {optArray pattern iArray} {
    upvar 1 $optArray opts $iArray var
    foreach path $opts(paths) {
	foreach interp [glob -nocomplain [file join $path $pattern]] {
	    if {[file executable $interp] && ![info exists var($interp)]} {
		if {[catch {exec echo "puts \[info patchlevel\] ; exit" | \
			$interp} patchlevel]} {
		    if {$opts(errors)} {
			error $::errorInfo
		    } else {
			puts stderr $patchlevel
			continue
		    }
		}
		# Lame package mechanism doesn't understand [abp]
		set ver [convertVersion $patchlevel]
		# Only allow versions within specified restrictions
		if {
		    ([package vcompare $ver $opts(minver)] >= 0) &&
		    ([package vcompare $opts(maxver) $ver] >= 0)
		} {
		    set var($interp) $patchlevel
		    lappend var(ORDERED) [list $patchlevel $interp]
		    set var(ORDERED) [lsort -dictionary -decreasing \
			    -index 0 $var(ORDERED)]
		}
	    }
	}
    }

    #
    # Post process ordering of the interpreters for output
    #
    set i 0
    foreach ipair $var(ORDERED) {
	set label  [incr i]:[lindex $ipair 0]
	set interp [lindex $ipair 1]
	if {[string equal "$i:$opts(norm)" $label]} {
	    set opts(norm) $label
	    set ok 1
	} elseif {$opts(norm) != "" && [string match "*$opts(norm)" $interp]} {
	    set opts(norm) $label
	    set ok 1
	}
	lappend var(VERSION) $label
	set var($label)      $interp
    }
    if {$opts(norm) != "" && ![info exists ok]} {
	puts stderr "Unable to normalize \"$opts(norm)\":\
		must be patchlevel or name of executable"
	set opts(norm) {}
	if {$opts(errors)} { exit }
    }
    vputs stdout "$iArray: $var(VERSION)"
}

#
# variation of puts to allow for -verbose operation
#
proc vputs {args} {
    global opts
    if {$opts(verbose)} {
	uplevel 1 [list puts] $args
    }
}

#
# Do benchmarking
#
proc collectData {iArray dArray oArray fileList} {
    upvar 1 $iArray ivar $dArray DATA $oArray opts

    array set DATA {MAXLEN 0}
    foreach label $ivar(VERSION) {
	set interp $ivar($label)
	vputs stdout "Benchmark $label $interp"
	set cmd [list $interp libbench.tcl \
		-match $opts(match) \
		-rmatch $opts(rmatch) \
		-iters $opts(iters) \
		-interp $interp \
		-errors $opts(errors) \
		]
	set start [clock seconds]
	foreach file $fileList {
	    vputs -nonewline stdout [string index [file tail $file] 0]
	    flush stdout
	    if {[catch {eval exec $cmd [list $file]} output]} {
		if {$opts(errors)} {
		    error $::errorInfo
		} else {
		    puts stderr $output
		    continue
		}
	    }
	    #vputs $output ; continue
	    array set tmp $output
	    catch {unset tmp(Sourcing)}
	    foreach desc [array names tmp] {
		set DATA(desc:${desc}) {}
		set DATA(:$desc$label) $tmp($desc)
		if {[string length $desc] > $DATA(MAXLEN)} {
		    set DATA(MAXLEN) [string length $desc]
		}
	    }
	    unset tmp
	}
	set elapsed [expr {[clock seconds] - $start}]
	set hour [expr {$elapsed / 3600}]
	set min [expr {$elapsed / 60}]
	set sec [expr {$elapsed % 60}]
	vputs stdout " [format %.2d:%.2d:%.2d $hour $min $sec] elapsed"
    }
}

#
# Various data output styles
#
proc outputData-text {iArray dArray {norm {}}} {
    upvar 1 $iArray ivar $dArray DATA

    set fmt "%.3d %-$DATA(MAXLEN)s"
    set i 0
    set out [format $fmt $i "VERSIONS:"]
    foreach lbl $ivar(VERSION) { append out [format " %7s" $lbl] }
    append out \n

    foreach elem [lsort -dictionary [array names DATA {desc*}]] {
	set desc [string range $elem 5 end]
	append out [format $fmt [incr i] $desc]
	foreach lbl $ivar(VERSION) {
	    # establish a default for tests that didn't exist for this interp
	    if {![info exists DATA(:$desc$lbl)]} { set DATA(:$desc$lbl) "-=-" }
	}
	if {[info exists DATA(:$desc$norm)] && \
		[string is double -strict $DATA(:$desc$norm)]} {
	    foreach lbl $ivar(VERSION) {
		if {[string is double -strict $DATA(:$desc$lbl)]} {
		    append out [format " %7.2f" \
			    [expr {double($DATA(:$desc$lbl)) / \
			    double($DATA(:$desc$norm))}]]
		} else {
		    append out [format " %7s" $DATA(:$desc$lbl)]
		}
	    }
	} else {
	    foreach lbl $ivar(VERSION) {
		# not %d to allow non-int result codes
		append out [format " %7s" $DATA(:$desc$lbl)]
	    }
	}
	append out "\n"
    }

    append out [format $fmt $i "BENCHMARKS"]
    foreach lbl $ivar(VERSION) { append out [format " %7s" $lbl] }
    append out \n
    return $out
}

#
# List format is:
#  <num> <desc> <val1> <val2> ...
#
proc outputData-list {iArray dArray {norm {}}} {
    upvar 1 $iArray ivar $dArray DATA

    set i 0
    set out [list [concat [list $i VERSIONS:] $ivar(VERSION)]]

    foreach elem [lsort -dictionary [array names DATA {desc*}]] {
	set desc [string range $elem 5 end]
	set name [incr i]
	set line [list [incr i] $desc]
	foreach lbl $ivar(VERSION) {
	    # establish a default for tests that didn't exist for this interp
	    if {![info exists DATA(:$desc$lbl)]} { set DATA(:$desc$lbl) "-=-" }
	}
	if {[info exists DATA(:$desc$norm)] && \
		[string is double -strict $DATA(:$desc$norm)]} {
	    foreach lbl $ivar(VERSION) {
		if {[string is double -strict $DATA(:$desc$lbl)]} {
		    lappend line [format "%.2f" \
			    [expr {double($DATA(:$desc$lbl)) / \
			    double($DATA(:$desc$norm))}]]
		} else {
		    lappend line $DATA(:$desc$lbl)
		}
	    }
	} else {
	    foreach lbl $ivar(VERSION) { lappend line $DATA(:$desc$lbl) }
	}
	lappend out $line
    }

    lappend out [concat [list $i BENCHMARKS] $ivar(VERSION)]
    return $out
}

proc list2csv {list} {
    set out ""
    foreach l $list {
	set sep {}
	foreach val $l {
	    if {[string match "*\[\",\]*" $val]} {
		append out $sep\"[string map [list \" \"\"] $val]\"
	    } else {
		append out $sep$val
	    }
	    set sep ,
	}
	append out \n
    }
    return $out
}

proc outputData {optArray iArray dArray} {
    upvar 1 $optArray opts $iArray ivar $dArray DATA

    switch -exact -- $opts(output) {
	text {
	    puts -nonewline stdout [outputData-text ivar DATA $opts(norm)]
	}
	list {
	    puts stdout [join [outputData-list ivar DATA $opts(norm)] \n]
	}
	csv {
	    puts -nonewline stdout \
		    [list2csv [outputData-list ivar DATA $opts(norm)]]
	}
    }
}

proc now {} {
    return [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
}

if {[llength $opts(tcllist)] && $opts(usetcl)} {
    array set TCL_INTERP {ORDERED {} VERSION {}}
    getInterps opts $opts(tclsh) TCL_INTERP
    vputs stdout "STARTED [now] ($::ME v$::VERSION)"
    collectData TCL_INTERP TCL_DATA opts $opts(tcllist)
    outputData opts TCL_INTERP TCL_DATA
    vputs stdout "FINISHED [now]"
}

if {[llength $opts(tklist)] && $opts(usetk)} {
    vputs stdout ""
    array set TK_INTERP {ORDERED {} VERSION {}}
    getInterps opts $opts(wish) TK_INTERP
    vputs stdout "STARTED [now] ($::ME v$::VERSION)"
    collectData TK_INTERP TK_DATA opts $opts(tklist)
    outputData opts TK_INTERP TK_DATA
    vputs stdout "FINISHED [now]"
}
