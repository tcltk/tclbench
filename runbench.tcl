#!/usr/bin/env tclsh

# runbench.tcl ?options?
#
set RCS {RCS: @(#) $Id: runbench.tcl,v 1.28 2010/12/04 00:28:02 hobbs Exp $}
#
# Copyright (c) 2000-2010 Jeffrey Hobbs.

#
# Run the main script from an 8.3+ interp
#
if {[catch {package require Tcl 8.3}]} {
    set me [file tail [info script]]
    puts stderr "$me requires 8.3+ to run, although it can benchmark\
	    any Tcl v7+ interpreter"
    exit 1
}

regexp {,v (\d+\.\d+)} $RCS -> VERSION
set MYDIR [file dirname [info script]]
set ME [file tail [info script]]

proc usage {} {
    puts stderr "Usage (v$::VERSION): $::ME ?options?\
	    \n\t-help			# print out this message\
	    \n\t-autoscale <bool>	# autoscale runtime iters to 0.1s..4s (default on)\
	    \n\t-repeat <#>		# repeat X times and collate results (default 1)
	    \n\t-collate min|max|avg	# collate command (default min)
	    \n\t-delta			# delta range for wiki highlight (default: 0.05)\
	    \n\t-iterations <#>		# max X of iterations to run any benchmark\
	    \n\t-minversion <version>	# minimum interp version to use\
	    \n\t-maxversion <version>	# maximum interp version to use\
	    \n\t-match <glob>		# only run tests matching this pattern\
	    \n\t-rmatch <regexp>	# only run tests matching this pattern\
	    \n\t-normalize <version>	# normalize numbers to given version\
	    \n\t-notcl			# do not run tclsh tests\
	    \n\t-notk			# do not run wish tests\
	    \n\t-output <text|list|csv|wiki> # style of output (default: match input format)\
	    \n\t-paths <pathList>	# path or list of paths to search for interps\
	    \n\t-single <bool>		# whether to run all tests in same interp instance\
	    \n\t-threads <numThreads>	# num of threads to use (where possible)\
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
# Default process options
#
array set opts {
    paths	{}
    delta	0.05
    minver	0.0
    maxver	10.0
    match	{}
    rmatch	{}
    tcllist	{}
    tklist	{}
    tclsh	"tclsh*"
    wish	"wish*"
    usetk	1
    usetcl	1
    usethreads	0
    errors	0
    verbose	0
    output	text
    iters	5000
    single	1
    autoscale	1
    norm	{}
    repeat	0
    ccmd	collate_min
}

proc parseOpts {} {
    global argv opts
    if {[llength $argv]} {
	set theargs $argv
	while {[llength $theargs]} {
	    set key [lindex $theargs 0]
	    set val [lindex $theargs 1]
	    set consumed 1
	    switch -glob -- $key {
		-help*	{ usage }
		-throw*	{
		    # throw errors when they occur in benchmark files
		    set opts(errors) 1
		    set consumed 0
		}
		-thread*	{
		    set opts(usethreads) [string is true -strict $val]
		}
		-globt*	{
		    set opts(tclsh) $val
		}
		-globw*	{
		    set opts(wish) $val
		}
		-auto*	{
		    set opts(autoscale) [string is true -strict $val]
		}
		-rep*	{
		    if {![string is integer -strict $val] || $val < 0} { usage }
		    set opts(repeat) $val
		    # Repeats and soft-errors don't mix
		    if {$val} { set opts(errors) 1 }
		}
		-col*	{
		    set ccmd [info commands collate_$val]
		    if {[llength $ccmd] != 1} { usage }
		    set opts(ccmd) $ccmd
		}
		-iter*	{
		    # Maximum iters to run a test
		    # The test may set a smaller iter run, but anything larger
		    # will be reduced.
		    set opts(iters) $val
		}
		-min*	{
		    # Allow a minimum version to search for,
		    # restricted to version, not patchlevel
		    set opts(minver) [convertVersion $val]
		}
		-max*	{
		    # Allow a maximum version to search for,
		    # restricted to version, not patchlevel
		    set opts(maxver) [convertVersion $val]
		}
		-match*	{
		    set opts(match) $val
		}
		-rmatch*	{
		    set opts(rmatch) $val
		}
		-norm*	{
		    set opts(norm) $val
		}
		-notcl	{
		    set opts(usetcl) 0
		    set consumed 0
		}
		-notk	{
		    set opts(usetk) 0
		    set consumed 0
		}
		-delta	{
		    set opts(delta) $val
		}
		-single*	{
		    set opts(single) [string is true -strict $val]
		}
		-out*	{
		    # Output style
		    if {![regexp {^(text|list|csv|wiki)$} $val]} { usage }
		    set opts(output) $val
		}
		-path*	{
		    # Support single dir path or multiple paths as a list
		    if {[file isdir $val]} { set val [list $val] }
		    foreach path $val {
			if {[file isdir $val]} { lappend opts(paths) $path }
		    }
		}
		-v*	{
		    set opts(verbose) 1
		    set consumed 0
		}
		default {
		    foreach arg $theargs {
			if {![file exists $arg]} {
			    usage
			}
			if {[string match *tk* $arg]} {
			    lappend opts(tklist) $arg
			} else {
			    lappend opts(tcllist) $arg
			}
		    }
		    vputs stdout "ARGS [lrange $argv 0 end-[llength $theargs]]"
		    break
		}
	    }
	    set theargs [lreplace $theargs 0 $consumed]
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
	set pathSep [expr {($::tcl_platform(platform)=="windows") ? ";" : ":"}]
	set opts(paths) [split $::env(PATH) $pathSep]
    }
}

#
# Collect interp info from path(s)
#
proc getInterps {optArray pattern iArray} {
    upvar 1 $optArray opts $iArray var
    set evalString {puts [info patchlevel] ; exit}
    foreach path $opts(paths) {
	foreach interp [glob -nocomplain -directory $path $pattern] {
	    if {$::tcl_version > 8.4} {
		set interp [file normalize $interp]
	    }
	    # Root out the soft-linked exes
	    while {[string equal link [file type $interp]]} {
		set link [file readlink $interp]
		if {[string match relative [file pathtype $link]]} {
		    set interp [file join [file dirname $interp] $link]
		} else {
		    set interp $link
		}
	    }
	    if {[file executable $interp] && ![info exists var($interp)]} {
		if {[catch {exec $interp << $evalString} patchlevel]} {
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
		}
	    }
	}
    }
    set var(ORDERED) [lsort -dictionary -decreasing -index 0 $var(ORDERED)]

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
	if {$opts(output) == "wiki"} {
	    set args [lreplace $args end end " [lindex $args end]"]
	}
	uplevel 1 [list puts] $args
    }
}

catch {
    lappend ::auto_path /usr/local/ActiveTcl/lib
    package require Tclx
}

#
# Do benchmarking
#
proc collectData {iArray dArray oArray fileList} {
    upvar 1 $iArray ivar $dArray DATA $oArray opts

    array set DATA {MAXLEN 0}
    catch {
	lappend ::auto_path /usr/local/ActiveTcl/lib
	package require Tclx
    }
    if {$opts(repeat)} {
	if {$opts(repeat) < 3 && $opts(autoscale)} {
	    # We'll waste one run not autoscaled to get good elapsed time
	    incr opts(repeat)
	}
    } elseif {$opts(autoscale)} {
	# Warn users that with autoscaling, you can't compare elapsed time
	# to each other because the system will run different iters based
	# on interp speed
	vputs stdout "AUTOSCALING ON - total elapsed time may be skewed"
    }
    for {set i 0} {$i <= $opts(repeat)} {incr i} {
	if {$i} {
	    vputs -nonewline stdout "R$i "
	}
	# Don't autoscale the first run if repeating
	set auto [expr {($opts(repeat)&&$i) ? $opts(autoscale) : 0}]
	foreach label $ivar(VERSION) {
	    set interp $ivar($label)
	    if {$i == 0} {
		vputs stdout "Benchmark $label $interp"
	    }
	    set cmd [list $interp [file join $::MYDIR libbench.tcl]]
	    lappend cmd -match $opts(match) \
		-rmatch $opts(rmatch) \
		-autos $auto \
		-iters $opts(iters) \
		-interp $interp \
		-errors $opts(errors) \
		-threads $opts(usethreads)
	    array set tmp {}
	    #vputs stderr "exec $cmd $fileList"
	    set start [clock seconds]
	    catch { set cstart [lindex [times] 2] }
	    if {$opts(usethreads)} {
		if {[catch {eval exec $cmd $fileList} output]} {
		    if {$opts(errors)} {
			error $::errorInfo
		    } else {
			puts stderr $output
		    }
		} else {
		    array set tmp $output
		}
	    } else {
		if {$opts(single)} {
		    foreach file $fileList {
			if {$i == 0} {
			    vputs -nonewline stdout \
				[string index [file tail $file] 0]
			}
			flush stdout
			if {[catch {eval exec $cmd [list $file]} output]} {
			    if {$opts(errors)} {
				error $::errorInfo
			    } else {
				puts stderr $output
				continue
			    }
			} else {
			    array set tmp $output
			}
		    }
		} else {
		    if {$i == 0} {
			vputs -nonewline "running all"
		    }
		    flush stdout
		    if {[catch {eval exec $cmd $fileList} output]} {
			if {$opts(errors)} {
			    error $::errorInfo
			} else {
			    puts stderr $output
			    continue
			}
		    } else {
			array set tmp $output
		    }
		}
	    }
	    catch { set celapsed [expr {[lindex [times] 2] - $cstart}] }
	    set elapsed [expr {[clock seconds] - $start}]
	    set hour [expr {$elapsed / 3600}]
	    set min [expr {$elapsed / 60}]
	    set sec [expr {$elapsed % 60}]
	    if {$i == 0} {
		vputs stdout " [format %.2d:%.2d:%.2d $hour $min $sec] elapsed"
		if {[info exists celapsed]} {
		    vputs stdout "$celapsed milliseconds"
		}
	    }
	    catch { unset tmp(Sourcing) }
	    if {$opts(autoscale) != $auto} {
		# Toss data where autoscale is tweaked (e.g. if we are
		# repeating, this is the first run, and it is not autoscaled)
		unset tmp
		continue
	    }
	    foreach desc [array names tmp] {
		set DATA(desc:${desc}) {}
		set key :$desc$label ; set val $tmp($desc)
		if {![info exists DATA($key)]} {   # $i == 0
		    set DATA($key) $val
		} elseif {[string is double -strict $val]} {
		    # Call user-request collation type
		    set DATA($key) [$opts(ccmd) $DATA($key) $val $i]
		}
		if {[string length $desc] > $DATA(MAXLEN)} {
		    set DATA(MAXLEN) [string length $desc]
		}
	    }
	    unset tmp
	}
    }
    if {$i > 1} {
	vputs stdout ""
    }
}

proc collate_min {cur new runs} {
    # Minimum
    return [expr {$cur > $new ? $new : $cur}]
}
proc collate_avg {cur new runs} {
    # Average
    return [expr {($cur * $i + $new)/($i+1)}]
}
proc collate_max {cur new runs} {
    # Maximum
    return [expr {$cur < $new ? $new : $cur}]
}

#
# Various data output styles
#
proc outputData-text-item {val} {
    set LEN 8
    if {[string is double -strict $val]} {
	if {$val > 1e6} {
	    return [format " %8.0f" $val]
	} elseif {$val > 1e5} {
	    return [format " %8.1f" $val]
	} else {
	    return [format " %8.2f" $val]
	}
    } else {
	return [format " %8s" $val]
    }
}

proc outputData-text {iArray dArray {norm {}}} {
    upvar 1 $iArray ivar $dArray DATA

    set fmt "%.3d %-$DATA(MAXLEN)s"
    set i 0
    set out [format $fmt $i "VERSIONS:"]
    foreach lbl $ivar(VERSION) { append out [outputData-text-item $lbl] }
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
		set val $DATA(:$desc$lbl)
		if {[string is double -strict $val]} {
		    set val [expr {$val / double($DATA(:$desc$norm))}]
		}
		append out [outputData-text-item $DATA(:$desc$lbl)]
	    }
	} else {
	    foreach lbl $ivar(VERSION) {
		# not %d to allow non-int result codes
		append out [outputData-text-item $DATA(:$desc$lbl)]
	    }
	}
	append out "\n"
    }

    append out [format $fmt $i "BENCHMARKS"]
    foreach lbl $ivar(VERSION) { append out [outputData-text-item $lbl] }
    append out \n
    return $out
}

#
# List format is:
#  <num> <desc> <val1> <val2> ...
#
proc outputData-list {iArray dArray {norm {}}} {
    upvar 1 $iArray ivar $dArray DATA
    global opts

    set i 0
    set out [list [concat [list $i VERSIONS:] $ivar(VERSION)]]

    foreach elem [lsort -dictionary [array names DATA {desc*}]] {
	set desc [string range $elem 5 end]
	set name [incr i]
	set line [list $name $desc]
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
	    foreach lbl $ivar(VERSION) {
		lappend line $DATA(:$desc$lbl)
	    }
	    if {$opts(output) == "wiki"} {
		set line [lrange $line 2 end]
		set min [min $line]
		set max [max $line]
		set wline [list $name $desc]
		foreach elem $line {
		    if {[string is double -strict $elem]} {
			# do magic highlighting within DELTA% of min or max
			if {$elem < ($min*(1.0+$opts(delta)))} {
			    set elem "''$elem''" ; # italic
			} elseif {$elem > ($max*(1.0-$opts(delta)))} {
			    set elem "'''$elem'''" ; # bold
			}
		    }
		    lappend wline $elem
		}
		set line $wline
	    }
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

proc list2wiki {list} {
    set out ""
    append out "%|[join [lindex $list 0] |]|%\n" ; # VERSIONS
    foreach l [lrange $list 1 end-1] {
	append out "&|[join [wikisafe $l] |]|&\n"
    }
    append out "%|[join [lindex $list end] |]|%\n" ; # BENCHMARKS
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
	wiki {
	    puts -nonewline stdout \
		[list2wiki [outputData-list ivar DATA $opts(norm)]]
	}
    }
}

proc now {} {
    return [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
}

parseOpts

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
