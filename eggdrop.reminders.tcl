# =============================================================================
# Eggdrop Reminder Script - EST/CST/MST/PST 
# Full timezone + calendar event support
# =============================================================================

# --------------------------- CONFIG & GLOBALS -------------------------------
set reminder_file "reminders.dat"
set ::daynames {monday tuesday wednesday thursday friday saturday sunday}

# --------------------------- TIMEZONE MAPPING (EST/CST/MST/PST) -------------
array set ::tz_map {
  est "America/New_York"
  cst "America/Chicago"
  mst "America/Denver"
  pst "America/Los_Angeles"
  utc "UTC"
}

proc normalize_timezone {tz} {
  set lower [string tolower $tz]
  if {[info exists ::tz_map($lower)]} {
    return $::tz_map($lower)
  }
  return $tz
}

proc is_valid_timezone {tz} {
  set lower [string tolower $tz]
  if {$lower eq "utc" || [string match "*/*" $tz] || $lower in {est cst mst pst}} {
    return 1
  }
  if {[regexp {^[+-][0-9]{2}:?[0-9]{2}$} $tz]} { return 1 }
  return 0
}

# --------------------------- SAFE TIMEZONE LAYER ---------------------------
proc with_timezone {tz script} {
  global env
  set old_tz [expr {[info exists env(TZ)] ? $env(TZ) : ""}]
  set env(TZ) $tz
  set code [catch {uplevel 1 $script} result]
  if {$old_tz ne ""} {
    set env(TZ) $old_tz
  } else {
    unset -nocomplain env(TZ)
  }
  if {$code} {
    return -code $code $result
  }
  return $result
}

# --------------------------- LOAD / SAVE ------------------------------------
proc load_reminders {} {
  global reminder_list reminder_file
  set reminder_list {}
  if {[file exists $reminder_file]} {
    source $reminder_file
  }
  set new_list {}
  foreach rec $reminder_list {
    if {[llength $rec] == 6} {
      lappend new_list [list [lindex $rec 0] [lindex $rec 1] [lindex $rec 2] [lindex $rec 3] "UTC" [lindex $rec 4] [lindex $rec 5] ""]
    } elseif {[llength $rec] == 7} {
      lappend new_list [linsert $rec 7 ""]
    } else {
      lappend new_list $rec
    }
  }
  set reminder_list $new_list
  save_reminders
}

proc save_reminders {} {
  global reminder_list reminder_file
  set fd [open $reminder_file w]
  puts $fd "set reminder_list [list $reminder_list]"
  close $fd
}

# --------------------------- MAIN COMMAND (!reminder) ----------------------
proc reminder:cmd {nick uhost hand chan text} {
  global reminder_list

  if {[catch {
    set args [split [string trim $text]]
    set subcmd [string tolower [lindex $args 0]]

    if {[llength $args] == 0 || $subcmd eq "help"} {
      putserv "PRIVMSG $chan :\00312Reminder script help (timezone + calendar events):\003"
      putserv "PRIVMSG $chan :!reminder add <username> <YYYY-MM-DD|dayname> <HH:MM> \[TZ\] <text...>"
      putserv "PRIVMSG $chan :   TZ can be: America/Chicago, EST, CST, MST, PST, UTC, +0530, -0800 ..."
      putserv "PRIVMSG $chan :   EST  America/New_York (DST auto)"
      putserv "PRIVMSG $chan :   CST  America/Chicago (DST auto)"
      putserv "PRIVMSG $chan :   MST  America/Denver"
      putserv "PRIVMSG $chan :   PST  America/Los_Angeles"
      putserv "PRIVMSG $chan :!reminders <username>  list reminders"
      putserv "PRIVMSG $chan :!reminderdel <#>  delete your reminder"
      putserv "PRIVMSG $chan :\00303EST/CST/MST/PST now fully working and crash-proof.\003"
      return
    }

    if {$subcmd eq "add"} {
      if {[llength $args] < 5} {
        putserv "PRIVMSG $chan :\00304Usage: !reminder add <username> <YYYY-MM-DD|day> <HH:MM> [TZ] <text...>\003"
        return
      }

      set target  [lindex $args 1]
      set trigger [lindex $args 2]
      set hhmm    [lindex $args 3]

      # Detect optional TZ (EST/CST/MST/PST now safe)
      set candidate_tz [lindex $args 4]
      set tz "UTC"
      set msg_start 4
      if {$candidate_tz ne "" && [is_valid_timezone $candidate_tz]} {
        set normalized [normalize_timezone $candidate_tz]
        if {![catch {with_timezone $normalized {clock scan "2024-01-01 12:00" -format {%Y-%m-%d %H:%M}}}]} {
          set tz $normalized
          set msg_start 5
        }
      }
      set msgtext [join [lrange $args $msg_start end]]

      if {![regexp {^([01][0-9]|2[0-3]):[0-5][0-9]$} $hhmm]} {
        putserv "PRIVMSG $chan :\00304Invalid HH:MM\003"
        return
      }

      set lower_trigger [string tolower $trigger]
      set is_repeat 0
      set trigger_info $trigger

      if {$lower_trigger in $::daynames} {
        set is_repeat 1
        set trigger_info $lower_trigger
      } else {
        if {![regexp {^\d{4}-\d{2}-\d{2}$} $trigger]} {
          putserv "PRIVMSG $chan :\00304Use YYYY-MM-DD or a day name (monday etc.)\003"
          return
        }
        set is_repeat 0
        set trigger_info $trigger
      }

      if {!$is_repeat} {
        if {[catch {with_timezone $tz {clock scan "$trigger $hhmm" -format {%Y-%m-%d %H:%M}}}]} {
          putserv "PRIVMSG $chan :\00304Invalid date/time in $tz\003"
          return
        }
      }

      lappend reminder_list [list $target $is_repeat $trigger_info $hhmm $tz $msgtext $nick $chan]
      save_reminders

      putserv "PRIVMSG $chan :\00303Reminder added for $target in $tz\003"
      if {$is_repeat} {
        putserv "PRIVMSG $chan :Repeats every $trigger_info at $hhmm $tz"
      } else {
        putserv "PRIVMSG $chan :One-time calendar event on $trigger at $hhmm $tz"
      }
      return
    }

    putserv "PRIVMSG $chan :\00304Unknown command. Use !reminder for help.\003"
  } err]} {
##    putserv "PRIVMSG $chan :\00304Error adding reminder (script safe): $err\003"
    putlog "Reminder add error: $err"
  }
}

# --------------------------- LIST & DELETE ----------------------------------
proc reminder:listcmd {nick uhost hand chan text} {
  global reminder_list
  set target [lindex [split [string trim $text]] 0]
  if {$target eq ""} { set target $nick }

  set user_rems {}
  foreach rec $reminder_list {
    if {[string equal -nocase [lindex $rec 0] $target]} { lappend user_rems $rec }
  }

  if {[llength $user_rems] == 0} {
    putserv "PRIVMSG $chan :No reminders for \00312$target\003."
    return
  }

  putserv "PRIVMSG $chan :\00312Reminders for $target\003:"
  set num 1
  foreach rec $user_rems {
    set type [expr {[lindex $rec 1] ? "Repeating every [lindex $rec 2]" : "One-time on [lindex $rec 2]"}]
    putserv "PRIVMSG $chan :\00303$num.\003 $type at [lindex $rec 3] [lindex $rec 4]  [lindex $rec 5] \00307(set by [lindex $rec 6])\003"
    incr num
  }
}

proc reminder:delcmd {nick uhost hand chan text} {
  global reminder_list
  set num_str [lindex [split [string trim $text]] 0]
  if {![string is integer -strict $num_str] || $num_str < 1} {
    putserv "PRIVMSG $chan :\00304Usage: !reminderdel <number> (see !reminders $nick)\003"
    return
  }
  set del_num [expr {$num_str - 1}]

  set user_indices {}
  set idx 0
  foreach rec $reminder_list {
    if {[string equal -nocase [lindex $rec 0] $nick]} { lappend user_indices $idx }
    incr idx
  }

  if {$del_num >= [llength $user_indices]} {
    putserv "PRIVMSG $chan :\00304No reminder #$num_str for you.\003"
    return
  }

  set global_idx [lindex $user_indices $del_num]
  set reminder_list [lreplace $reminder_list $global_idx $global_idx]
  save_reminders
  putserv "PRIVMSG $chan :\00303Reminder #$num_str deleted.\003"
}

# --------------------------- CRASH-PROOF CHECKER ---------------------------
proc reminder:check {} {
  global reminder_list

  if {[catch {
    set now [clock seconds]
    set to_remove {}

    set idx -1
    foreach rec $reminder_list {
      incr idx
      set target      [lindex $rec 0]
      set is_repeat   [lindex $rec 1]
      set trigger_info [lindex $rec 2]
      set hhmm        [lindex $rec 3]
      set tz          [lindex $rec 4]
      set text        [lindex $rec 5]
      set setter      [lindex $rec 6]
      set rem_chan    [lindex $rec 7]

      set due 0

      if {$is_repeat} {
        catch {
          set local_day  [string tolower [with_timezone $tz {clock format $now -format %A}]]
          set local_time [with_timezone $tz {clock format $now -format %H:%M}]
          if {$local_day eq $trigger_info && $local_time eq $hhmm} {
            set due 1
          }
        }
      } else {
        catch {
          set target_unix [with_timezone $tz {clock scan "$trigger_info $hhmm" -format {%Y-%m-%d %H:%M}}]
          set diff [expr {$now - $target_unix}]
          if {$diff >= 0 && $diff < 300} {
            set due 1
            lappend to_remove $idx
          }
        }
      }

      if {$due} {
        set alert "Reminder for $target: $text"
        if {$rem_chan ne ""} {
          putserv "PRIVMSG $rem_chan :$alert"
        }
        putserv "PRIVMSG $target :$alert (set by $setter)"
      }
    }

    if {[llength $to_remove] > 0} {
      set to_remove [lsort -integer -decreasing $to_remove]
      foreach i $to_remove {
        set reminder_list [lreplace $reminder_list $i $i]
      }
      save_reminders
    }
  } err]} {
    putlog "Reminder checker error (safe): $err"
  }

  utimer 60 reminder:check
}

# --------------------------- INIT --------------------------------------------
load_reminders

foreach ut [utimers] {
  if {[lindex $ut 1] eq "reminder:check"} {
    killutimer [lindex $ut 2]
  }
}

utimer 60 reminder:check

bind pub - !reminder    reminder:cmd
bind pub - !reminders   reminder:listcmd
bind pub - !reminderdel reminder:delcmd

putlog "Reminder script (EST/CST/MST/PST) loaded - Tcl [info tclversion]"
putlog "Use !reminder for help. "
