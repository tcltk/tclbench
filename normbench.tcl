#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

# runbench.tcl ?options?
#
set RCS {RCS: @(#) $Id: normbench.tcl,v 1.4 2004/12/20 22:29:40 hobbs Exp $}
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
	    \n\t-normalize <version>	# normalize numbers to given version\
	    \n\t?file?			# runbench output file to normalize (or stdin)"
    exit 1
}

#
# Process args
#
array set opts {
    norm	{}
    fid		stdin
}
if {[llength $argv]} {
    while {[llength $argv]} {
	set key [lindex $argv 0]
	switch -glob -- $key {
	    -help*	{ usage }
	    -norm*	{
		set opts(norm) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    default {
		if {![file exists $key]} {
		    usage
		} else {
		    set opts(fid) [open $key r]
		    set argv [lreplace $argv 0 0]
		    # The file should be the last arg
		    if {[llength $argv]} { usage }
		}
	    }
	}
    }
}

proc csv2list {str {sepChar ,}} {
    regsub -all {(\A\"|\"\Z)} $str \0 str
    set str [string map [list $sepChar\"\"\" $sepChar\0\" \
	    \"\"\"$sepChar \"\0$sepChar \
	    \"\" \" \" \0 ] $str]
    set end 0
    while {[regexp -indices -start $end {(\0)[^\0]*(\0)} $str \
	    -> start end]} {
	set start [lindex $start 0]
	set end   [lindex $end 0]
	set range [string range $str $start $end]
	set first [string first $sepChar $range]
	if {$first >= 0} {
	    set str [string replace $str $start $end \
		    [string map [list $sepChar \1] $range]]
	}
	incr end
    }
    set str [string map [list $sepChar \0 \1 $sepChar \0 {} ] $str]
    return [split $str \0]
}

proc list2csv {list {sepChar ,}} {
    set out ""
    foreach l $list {
	set sep {}
	foreach val $l {
	    if {[string match "*\[\"$sepChar\]*" $val]} {
		append out $sep\"[string map [list \" \"\"] $val]\"
	    } else {
		append out $sep$val
	    }
	    set sep $sepChar
	}
	append out \n
    }
    return $out
}


proc findVersion {norm versions} {
    if {$norm == ""} { return 0 }
    set i [lsearch -exact $versions $norm]
    if {$i >= 0} { return $i }
    set i [lsearch -glob $versions *$norm*]
    if {$i >= 0} { return $i }
    puts stderr "Unable to normalize \"$norm\": must be one of [join $versions {, }]"
    usage
}

proc normalize-text {norm line} {
    global start col
    scan $line %d num
    if {$num == 0} {
	set start [expr {[string first 1: $line]-1}]
	set col [findVersion $norm [string range $line $start end]]
	return $line
    }
    set times [string range $line $start end]
    set ntime [lindex $times $col]
    if {![string is double -strict $ntime] || $ntime == 0} {
	# This didn't return valid data.  Try walking backwards to find
	# a newer version that we can normalize this row on, since newer
	# versions are to the left.
	for {set i $col} {$i >= 0} {incr i -1} {
	    set ntime [lindex $times $i]
	    if {[string is double -strict $ntime] && $ntime} { break }
	}
	# Hmph.  No usable data.
	if {$i == -1} { return $line }
    }
    set out [string range $line 0 [expr {$start-1}]]
    foreach t $times {
	if {[string is double -strict $t]} {
	    append out [format " %7.2f" \
		    [expr {double($t) / double($ntime)}]]
	} else {
	    append out [format " %7s" $t]
	}
    }
    return $out
}

proc normalize-list {norm line} {
    global col
    if {[lindex $line 0] == 0} {
	set col [findVersion $norm [lrange $line 2 end]]
	return $line
    }
    set times [lrange $line 2 end]
    set ntime [lindex $times $col]
    if {![string is double -strict $ntime]} {
	return $line
    } else {
	set out [lrange $line 0 1]
	foreach t $times {
	    if {[string is double -strict $t]} {
		lappend out [format "%.2f" \
			[expr {double($t) / double($ntime)}]]
	    } else {
		lappend out $t
	    }
	}
	return $out
    }
}

proc normalize {norm indata} {
    set lines [split $indata \n]
    foreach line $lines {
	if {![string match {[0-9]*} $line] \
		|| [string match {*milliseconds} $line]} {
	    puts stdout $line
	    continue
	}
	scan $line %d num
	if {$num == 0} {
	    # guess format based on first line of version input
	    if {[string match "0,VER*" $line]} {
		set format csv
	    } elseif {[string match "0 VER*" $line]} {
		set format list
	    } elseif {[string match "000*VER*" $line]} {
		set format text
	    } else {
		puts stderr "Unrecognized runbench format input file"
		exit
	    }
	}
	switch -exact -- $format {
	    text { puts stdout [normalize-text $norm $line] }
	    list { puts stdout [normalize-list $norm $line] }
	    csv  {
		puts -nonewline stdout [list2csv [list \
			[normalize-list $norm [csv2list $line]]]]
	    }
	}
    }
}

normalize $opts(norm) [read -nonewline $opts(fid)]
