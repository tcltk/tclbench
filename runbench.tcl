#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

#
# Run the main script from an 8.1.1+ interp
#
if {[catch {package require Tcl 8.1.1}]} {
    set me [file tail [info script]]
    puts stderr "$me requires 8.1.1+ to run, although it can benchmark\
	    any Tcl v7+ interpreter"
    exit 1
}

set MYDIR [file dirname [info script]]

proc usage {} {
    set me [file tail [info script]]
    puts stderr "Usage: $me ?options?\
	    \n\t-help			# print out this message\
	    \n\t-errors <0|1>		# whether or not errors should be thrown\
	    \n\t-iterations <#>		# default # of iterations to run a benchmark\
	    \n\t-minversion <version>	# minimum interp version to use\
	    \n\t-maxversion <version>	# maximum interp version to use\
	    \n\t-match <glob>		# only run tests matching this pattern\
	    \n\t-notcl			# do not run tclsh tests\
	    \n\t-notk			# do not run wish tests\
	    \n\t-output <text|list|csv>	# style of output from program\
	    \n\t-paths <pathList>	# path or list of paths to search for interps\
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
    tcllist	{}
    tklist	{}
    tclsh	"tclsh?*"
    wish	"wish?*"
    usetk	1
    usetcl	1
    errors	1
    verbose	0
    output	text
    iters	2000
}
if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	switch -glob -- $key {
	    -help*	{ usage }
	    -err*	{
		# Whether or not to throw errors
		set opts(errors) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -iter*	{
		# Default iters to run a test
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
		    error $::errorInfo
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
# Post processing
#
proc orderInterps {iArray} {
    upvar 1 $iArray var
    set i 0
    foreach ipair $var(ORDERED) {
	set label  [incr i]:[lindex $ipair 0]
	set interp [lindex $ipair 1]
	lappend var(VERSION)	$label
	set var($label)		$interp
    }
    vputs stdout "$iArray: $var(VERSION)"
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
		-iters $opts(iters) \
		-interp $interp \
		-errors $opts(errors) \
		]
	if {[catch {eval exec $cmd $fileList} output]} {
	    error $::errorInfo
	}
	#vputs $output ; continue
	array set tmp $output
	catch {unset tmp(Sourcing)}
	foreach i [array names tmp] {
	    set DATA($i,desc)   [lindex $tmp($i) 0]
	    set DATA($i,$label) [lindex $tmp($i) 1]
	    if {[string length $i$DATA($i,desc)] > $DATA(MAXLEN)} {
		set DATA(MAXLEN) [string length $i$DATA($i,desc)]
	    }
	}
    }
}

#
# Various data output styles
#
proc outputData-text {iArray dArray} {
    upvar 1 $iArray ivar $dArray DATA

    set fmt "%-[expr {$DATA(MAXLEN) + 1}]s"
    set out [format $fmt "000 VERSIONS:"]
    foreach lbl $ivar(VERSION) { append out [format " %7s" $lbl] }
    append out \n

    foreach elem [lsort -dictionary [array names DATA {*desc}]] {
	set name [lindex [split $elem ,] 0]
	append out [format $fmt "$name $DATA($elem)"]
	foreach lbl $ivar(VERSION) {
	    # not %d to allow non-int result codes
	    if {![info exists DATA($name,$lbl)]} { set DATA($name,$lbl) "-=-" }
	    append out [format " %7s" $DATA($name,$lbl)]
	}
	append out "\n"
    }

    append out [format $fmt "END VERSIONS:"]
    foreach lbl $ivar(VERSION) { append out [format " %7s" $lbl] }
    append out \n
    return $out
}

#
# List format is:
#  <num> <desc> <val1> <val2> ...
#
proc outputData-list {iArray dArray} {
    upvar 1 $iArray ivar $dArray DATA

    set out [list [concat [list 000 VERSIONS:] $ivar(VERSION)]]

    foreach elem [lsort -dictionary [array names DATA {*desc}]] {
	set name [lindex [split $elem ,] 0]
	set line [list $name $DATA($elem)]
	foreach lbl $ivar(VERSION) {
	    # not %d to allow non-int result codes
	    if {![info exists DATA($name,$lbl)]} { set DATA($name,$lbl) "-=-" }
	    lappend line $DATA($name,$lbl)
	}
	lappend out $line
    }

    lappend out [concat [list END VERSIONS:] $ivar(VERSION)]
    return $out
}

proc list2csv {list} {
    set out ""
    foreach l $list {
	set sep {}
	foreach val $l {
	    if {[string match -nocase "*\[\",\]*" $val]} {
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

proc outputData {type iArray dArray} {
    upvar 1 $iArray ivar $dArray DATA

    switch -exact -- $type {
	text {
	    puts -nonewline stdout [outputData-text ivar DATA]
	}
	list {
	    puts -nonewline stdout [join [outputData-list ivar DATA] \n]\n
	}
	csv {
	    puts -nonewline stdout [list2csv [outputData-list ivar DATA]]
	}
    }
}

if {[llength $opts(tcllist)] && $opts(usetcl)} {
    array set TCL_INTERP {ORDERED {} VERSION {}}
    getInterps opts $opts(tclsh) TCL_INTERP
    orderInterps TCL_INTERP
    vputs stdout "STARTED [clock format [clock seconds]]"
    collectData TCL_INTERP TCL_DATA opts $opts(tcllist)
    outputData $opts(output) TCL_INTERP TCL_DATA
    vputs stdout "FINISHED [clock format [clock seconds]]"
}

if {[llength $opts(tklist)] && $opts(usetk)} {
    vputs stdout ""
    array set TK_INTERP {ORDERED {} VERSION {}}
    getInterps opts $opts(wish) TK_INTERP
    orderInterps TK_INTERP
    vputs stdout "STARTED [clock format [clock seconds]]"
    collectData TK_INTERP TK_DATA opts $opts(tklist)
    outputData $opts(output) TK_INTERP TK_DATA
    vputs stdout "FINISHED [clock format [clock seconds]]"
}
