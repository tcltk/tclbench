#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

#
# Run the main script from an 8.0+ interp
#
package require Tcl 8

set MYDIR [file dirname [info script]]

proc usage {} {
    set me [file tail [info script]]
    puts stderr "Usage: $me ?options?\
	    \n\t-help			# print out this message\
	    \n\t-paths <pathList>	# path or list of paths to search for interps\
	    \n\t-minversion <version>	# minimum interp version to use\
	    \n\t-maxversion <version>	# maximum interp version to use\
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
    tcllist	{}
    tklist	{}
}
if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	switch -glob -- $key {
	    -help*	{ usage }
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
	    -minv*	{
		# Allow a minimum version to search for,
		# restricted to version, not patchlevel
		set opts(minver) [convertVersion [lindex $argv 1]]
		set argv [lreplace $argv 0 1]
	    }
	    -maxv*	{
		# Allow a maximum version to search for,
		# restricted to version, not patchlevel
		set opts(maxver) [convertVersion [lindex $argv 1]]
		set argv [lreplace $argv 0 1]
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
} else {
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

proc getInterps {optArray pattern iArray} {
    upvar 1 $optArray opts $iArray var
    foreach path $opts(paths) {
	foreach interp [glob -nocomplain [file join $path $pattern]] {
	    if {[file executable $interp] && ![info exists var($interp)]} {
		if {[catch {exec echo "puts \[info patchlevel\] ; exit" | \
			$interp} patchlevel]} {
		    error $::errorInfo
		}
		# Lame patch mechanism doesn't understand [abp]
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
array set TCL_INTERP {ORDERED {} VERSION {}}
array set TK_INTERP  {ORDERED {} VERSION {}}
getInterps opts "tclsh?*" TCL_INTERP
getInterps opts "wish?*" TK_INTERP

#
# Post processing
#
proc postProc {iArray} {
    upvar 1 $iArray var
    set i 0
    foreach ipair $var(ORDERED) {
	set label  [incr i]:[lindex $ipair 0]
	set interp [lindex $ipair 1]
	lappend var(VERSION)	$label
	set var($label)		$interp
    }
    puts "$iArray: $var(VERSION)"
}
postProc TCL_INTERP
postProc TK_INTERP

#
# Do benchmarking
#
proc collectData {iArray dArray fileList} {
    upvar 1 $iArray ivar $dArray DATA

    array set DATA {MAXLEN 0}
    foreach label $ivar(VERSION) {
	set interp $ivar($label)
	puts "Benchmark $label $interp"
	if {[catch {eval exec [list $interp libbench.tcl $interp stdout] \
		$fileList} output]} {
	    error $::errorInfo
	}
	#puts $output ; continue
	array set tmp $output
	foreach i [lsort -integer [array names tmp {[0-9]*}]] {
	    set DATA($i,$label) [lindex $tmp($i) 1]
	    set DATA($i,desc)   [lindex $tmp($i) 0]
	    if {[string length $DATA($i,desc)] > $DATA(MAXLEN)} {
		set DATA(MAXLEN) [string length $DATA($i,desc)]
	    }
	}
    }
}
proc outputData {iArray dArray} {
    upvar 1 $iArray ivar $dArray DATA

    set maxlen $DATA(MAXLEN)
    puts "[format %[expr {$maxlen+5}]s\t { }][join $ivar(VERSION) \t]"

    foreach name [lsort -dictionary [array names DATA {*desc}]] {
	set num [lindex [split $name ,] 0]
	puts -nonewline [format "%.3d) %-${maxlen}s" $num $DATA($name)]
	foreach label $ivar(VERSION) {
	    # not %d to allow non-int result codes
	    puts -nonewline [format "\t%7s" $DATA($num,$label)]
	}
	puts ""
    }
}
if {[llength $opts(tcllist)]} {
    collectData TCL_INTERP TCL_DATA $opts(tcllist)
    outputData TCL_INTERP TCL_DATA
}
if {[llength $opts(tklist)]} {
    puts ""
    collectData TK_INTERP TK_DATA $opts(tklist)
    outputData TK_INTERP TK_DATA
}
