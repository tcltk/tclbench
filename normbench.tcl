#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

# normbench.tcl ?options?
#
set RCS {RCS: @(#) $Id: normbench.tcl,v 1.5 2007/11/17 01:51:32 hobbs Exp $}
#
# Copyright (c) 2000-2007 Jeffrey Hobbs.

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
	    \n\t-delta			# delta range for wiki highlight (default: 0.05)\
	    \n\t-normalize <version>	# normalize numbers to given version\
	    \n\t-output <text|list|csv|wiki> # style of output (default: match input format)\
	    \n\t?file?			# runbench output file to normalize (or stdin)"
    exit 1
}

#
# Process args
#
array set opts {
    norm	{}
    fid		stdin
    output	{}
    delta	{0.05}
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
	    -delta	{
		set opts(delta) [lindex $argv 1]
		set argv [lreplace $argv 0 1]
	    }
	    -out*	{
		# Output style
		set opts(output) [lindex $argv 1]
		if {![regexp {^(text|list|csv|wiki)$} $opts(output)]} { usage }
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

proc list2text {l} {
    global DESCLEN
    set num   [lindex $l 0]
    set desc  [lindex $l 1]
    set times [lrange $l 2 end]
    if {![info exists DESCLEN]} {
	# make desclen max available for 80 char display
	set DESCLEN [expr {74 - 9*[llength $times]}]
	if {$DESCLEN < 40} { set DESCLEN 40 }
    }
    set text [format "%.3d %-*s" $num $DESCLEN $desc]
    foreach t $times {
	if {[string is double -strict $t]} {
	    append text [format " %8.2f" $t]
	} else {
	    append text [format " %8s" $t]
	}
    }
    return $text
}

proc text2list {str} {
    global DESCLEN
    if {![info exists DESCLEN]} {
	# first creation - determine desclen on distance to first datapoint
	# At this point we have to guess ...
	set DESCLEN [expr {[string first 1: $str]-1}]
    }
    set times [string range $str $DESCLEN end]
    regexp {\d+} $str num ; # use RE to catch 0-prefaced nums
    set desc  [string trim [string range $str [string length $num] $DESCLEN]]
    return [concat [list $num $desc] $times]
}

proc min {times} {
    set min [expr {1<<16}]
    foreach t $times {
	if {[string is double -strict $t]} { if {$t < $min} { set min $t } }
    }
    return $min
}

proc max {times} {
    set max 0
    foreach t $times {
	if {[string is double -strict $t]} { if {$t > $max} { set max $t } }
    }
    return $max
}

proc wikisafe {str} {
    return [string map [list | <<pipe>>] $str]
}

proc wiki2list {str} {
    # remove first and last 2 chars and split on | symbol
    set out [list]
    foreach elem [split [string range $str 2 end-2] "|"] {
	lappend out [string trim $elem '] ; # remove wiki highlighting
    }
    return $out
}

proc list2wiki {l} {
    if {[lsearch -regexp $l {(VER|BENCH)}] != -1} {
	return "%|[join [wikisafe $l] |]|%\n" ; # header
    } else {
	return "&|[join [wikisafe $l] |]|&\n"
    }
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
    global col opts
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
	if {$opts(output) == "wiki"} {
	    set min [min $times]
	    set max [max $times]
	}
	foreach t $times {
	    if {[string is double -strict $t]} {
		set elem [format "%.2f" [expr {double($t) / double($ntime)}]]
		if {$opts(output) == "wiki"} {
		    # do magic highlighting within DELTA% of min or max
		    if {$t < ($min*(1.0+$opts(delta)))} {
			set elem "''$elem''" ; # italic
		    } elseif {$t > ($max*(1.0-$opts(delta)))} {
			set elem "'''$elem'''" ; # bold
		    }
		}
		lappend out $elem
	    } else {
		lappend out $t
	    }
	}
	return $out
    }
}

proc normalize {norm indata outformat} {
    set lines [split $indata \n]
    foreach line $lines {
	if {!([string match {[0-9]*} $line] || [string match {?|[0-9]*} $line])
	    || [string match {*milliseconds} $line]} {
	    if {$outformat == "wiki"} {
		puts stdout " [string trimleft $line]"
	    } else {
		puts stdout $line
	    }
	    continue
	}
	regexp {\d+} $line num ; # gets first number in line
	if {$num == 0} {
	    # guess format based on first line of version input
	    if {[string match "0,VER*" $line]} {
		set informat csv
	    } elseif {[string match "0 VER*" $line]} {
		set informat list
	    } elseif {[string match "?|0|VER*" $line]} {
		set informat wiki
	    } elseif {[string match "0*VER*" $line]} {
		set informat text
	    } else {
		puts stderr "Unrecognized runbench format input file"
		exit
	    }
	    if {$outformat == ""} {
		set outformat $informat
	    }
	}
	# Allow separate input/output format, so convert input to list form
	if {($informat == $outformat) && $informat == "text"} {
	    puts stdout [normalize-text $norm $line]
	} else {
	    switch -exact -- $informat {
		text { set line [text2list $line] }
		csv  { set line [csv2list $line] }
		wiki { set line [wiki2list $line] }
	    }
	    set line [normalize-list $norm $line]
	    switch -exact -- $outformat {
		text { puts stdout [list2text $line] }
		list { puts stdout $line }
		csv  { puts -nonewline stdout [list2csv [list $line]] }
		wiki { puts -nonewline stdout [list2wiki $line] }
	    }
	}
    }
}

fconfigure stdout -encoding iso8859-1 ; # avoid utf-8 output
normalize $opts(norm) [read -nonewline $opts(fid)] $opts(output)
