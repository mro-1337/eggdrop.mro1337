# =============================================================================
# nationalday.tcl    SUPER FUN v8.1 (daysoftheyear.com)
# Uses the PROVEN parser that gave 46 results + configurable IRC limit + full HTML export
# =============================================================================

package require http
package require tls

# --- CONFIGURATION ---
set nationalday(chan)         "#bbs"
set nationalday(hour)         6
set nationalday(minute)       0
set nationalday(timezone)     "America/Chicago"
set nationalday(color)        "09"     ;# bright green
set nationalday(cyellow)      "08"     ;# yellow
set nationalday(bold)         "\002"

# NEW: What you asked for
#set nationalday(max_irc)      15       ;# Change to 10, 20, 25... or 0 = show ALL in channel
#set nationalday(html_dir)     "/var/www/html/nationaldays"   ;# folder must exist and be writable by eggdrop
#set nationalday(html_file)    "today.html"
#set nationalday(html_baseurl) "https://your-domain.com/nationaldays"  ;#  CHANGE THIS TO YOUR REAL URL

# NEW: What you asked for
set nationalday(max_irc)      10       ;# Change to 10, 20, 25... or 0 = show ALL in channel
set nationalday(html_dir)     "/web/irc.bbses.info/nationaldays"   ;# folder must exist and be writable by eggdrop
set nationalday(html_file)    "index.html"
set nationalday(html_baseurl) "http://irc.bbses.info/nationaldays"  ;#  CHANGE THIS TO YOUR REAL URL


# Cache
set nationalday(cache_html) ""
set nationalday(cache_date) ""

putlog "=== NationalDay SUPER FUN v8.1 (proven parser + limit + HTML) loading ==="

catch {http::register https 443 ::tls::socket}

# =============================================================================
# Fetch (same as before)
# =============================================================================
proc nationalday:fetch_page {} {
    global nationalday
    set today [clock format [clock seconds] -format "%Y-%m-%d"]

    if {$nationalday(cache_date) eq $today && $nationalday(cache_html) ne ""} {
        putlog "NationalDay: Using cached page for $today"
        return $nationalday(cache_html)
    }

    set url "https://www.daysoftheyear.com/today/"
    putlog "NationalDay: Fetching daysoftheyear.com/today/ via curl (with -k)"

    if {[catch {
        set full_output [exec curl -s --max-time 30 -L -k -f \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0" \
            -w "\nHTTPSTATUS:%{http_code}" \
            $url 2>@1 ]

        set lines [split $full_output "\n"]
        set html [join [lrange $lines 0 end-1] "\n"]
        if {![regexp {HTTPSTATUS:200} $full_output]} { return "" }
    } err]} {
        putlog "NationalDay: CURL FAILED  $err"
        return ""
    }

    putlog "NationalDay: Page fetched OK ([string length $html] bytes)"
    set nationalday(cache_html) $html
    set nationalday(cache_date) $today
    return $html
}

# =============================================================================
# Parser  THE SAME ONE THAT GAVE YOU 46 RESULTS
# =============================================================================
proc nationalday:get_todays_holidays {} {
    global nationalday

    set html [nationalday:fetch_page]
    if {$html eq ""} { return [list] }

    regsub -all {<[^>]+>} $html {} text
    set text [string map {&amp; & &lt; < &gt; > &#039; ' &quot; \" &nbsp; " "} $text]

    set lines [split $text "\n"]
    set days [list]

    foreach raw $lines {
        set line [string trim $raw]
        if {$line eq ""} continue

        # Catches every real holiday (National..., International..., World..., etc.)
        if {[regexp {^(.*?(National|International|World|Global|Fun|Happy|Official|We Love|International Day of|National Day of).*?(Day|Week|Month|Hour|Night|Awareness))$} $line -> name]} {
            set name [string trim $name]
            if {[string length $name] > 5 && [string length $name] < 100} {
                if {[lsearch -exact $days $name] == -1} {
                    lappend days $name
                }
            }
        }
    }
    return $days
}

# =============================================================================
# Generate beautiful full HTML file (all events)
# =============================================================================
proc nationalday:generate_html {days datestr} {
    global nationalday
    if {$nationalday(html_dir) eq ""} return

    catch {file mkdir $nationalday(html_dir)}
    set filepath [file join $nationalday(html_dir) $nationalday(html_file)]

    if {[catch {
        set fd [open $filepath w]
        puts $fd "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>National Days  $datestr</title>"
        puts $fd {<style>body{font-family:Arial,sans-serif;max-width:800px;margin:40px auto;background:#f9f9f9}h1{text-align:center;color:#0066cc}ul{list-style:none;padding:0}li{margin:12px 0;padding:15px;background:white;border-radius:8px;box-shadow:0 2px 6px rgba(0,0,0,0.08)}</style>}
        puts $fd "</head><body><h1> National Days Today  $datestr</h1><p style=\"text-align:center\">[llength $days] celebrations</p><ul>"

        set n 1
        foreach d $days {
            puts $fd "<li><strong>$n. $d</strong></li>"
            incr n
        }
        puts $fd "</ul></body></html>"
        close $fd
        putlog "NationalDay: Full HTML saved  $filepath"
    } err]} {
        putlog "NationalDay: HTML save failed  $err"
    }
}

# =============================================================================
# Announce to IRC (limited + link to full HTML)
# =============================================================================
proc nationalday:announce {{target_chan ""}} {
    global nationalday

    set chan    [expr {$target_chan ne "" ? $target_chan : $nationalday(chan)}]
    set c       $nationalday(color)
    set cy      $nationalday(cyellow)
    set b       $nationalday(bold)
    set datestr [clock format [clock seconds] -format "%A, %B %d, %Y" -timezone :$nationalday(timezone)]

    set days [nationalday:get_todays_holidays]
    if {[llength $days] == 0} {
        puthelp "PRIVMSG $chan :\003${c}${b} National Days\003 No events found for ${datestr}."
        return
    }

    set count [llength $days]
    set display [expr {$nationalday(max_irc) > 0 ? [lrange $days 0 [expr {$nationalday(max_irc)-1}]] : $days}]

    puthelp "PRIVMSG $chan :\003${c}${b} TODAY'S NATIONAL DAYS  ${datestr} (${count} total) ${b}\003"

    set num 1
    foreach d $display {
        puthelp "PRIVMSG $chan :  \003${cy}${b}${num}.\003${b} $d"
        incr num
    }

    if {$nationalday(max_irc) > 0 && $count > $nationalday(max_irc)} {
        set more [expr {$count - $nationalday(max_irc)}]
        set fullurl "$nationalday(html_baseurl)/$nationalday(html_file)"
        puthelp "PRIVMSG $chan :   \00312... and $more more! See the full list here:\003 $fullurl"
    }

    # Always create the full HTML file
    nationalday:generate_html $days $datestr
}

# =============================================================================
# Scheduler + commands (unchanged)
# =============================================================================
proc nationalday:tick {} {
    global nationalday
    set now_h [string trimleft [clock format [clock seconds] -format "%H" -timezone :$nationalday(timezone)] "0"]
    set now_m [string trimleft [clock format [clock seconds] -format "%M" -timezone :$nationalday(timezone)] "0"]
    if {$now_h eq ""} {set now_h 0}
    if {$now_m eq ""} {set now_m 0}

    if {$now_h == $nationalday(hour) && $now_m == $nationalday(minute)} {
        set nationalday(cache_html) ""
        set nationalday(cache_date) ""
        nationalday:announce
    }
    utimer 60 nationalday:tick
}

bind pub - !nationalday nationalday:trig_today
proc nationalday:trig_today {nick host hand chan text} { nationalday:announce $chan }

bind pub - !ndhelp nationalday:trig_help
proc nationalday:trig_help {nick host hand chan text} {
    puthelp "PRIVMSG $chan :=== NationalDay v8.1 (max $::nationalday(max_irc) in IRC + full HTML) ==="
    puthelp "PRIVMSG $chan :  !nationalday    Today's days"
    puthelp "PRIVMSG $chan :  !ndsetchan     Set channel (ops)"
    puthelp "PRIVMSG $chan :  !ndsethour     Set time (ops)"
    puthelp "PRIVMSG $chan :  !ndhelp        Help"
}

# !ndsetchan and !ndsethour (copy from your previous working script if needed  they are identical)

bind pub o !ndsetchan nationalday:trig_setchan
proc nationalday:trig_setchan {nick host hand chan text} {
    global nationalday
    set newchan [string trim [lindex [split $text] 0]]
    if {$newchan eq "" || ![string match "#*" $newchan]} {
        puthelp "PRIVMSG $chan :Usage: !ndsetchan <#channel>"
        return
    }
    set nationalday(chan) $newchan
    puthelp "PRIVMSG $chan :NationalDay: Auto channel set to $newchan"
}

bind pub o !ndsethour nationalday:trig_sethour
proc nationalday:trig_sethour {nick host hand chan text} {
    global nationalday
    set parts [split [string trim $text]]
    set h [lindex $parts 0]
    set m [expr {[llength $parts] > 1 ? [lindex $parts 1] : 0}]
    if {![string is integer -strict $h] || $h < 0 || $h > 23} {
        puthelp "PRIVMSG $chan :Usage: !ndsethour <0-23> \[0-59\]"
        return
    }
    if {![string is integer -strict $m] || $m < 0 || $m > 59} {
        puthelp "PRIVMSG $chan :Usage: !ndsethour <0-23> \[0-59\]"
        return
    }
    set nationalday(hour)   $h
    set nationalday(minute) $m
    puthelp "PRIVMSG $chan :NationalDay: Auto time set to [format "%02d:%02d" $h $m] Central"
}

# START
if {![string match "*nationalday:tick*" [utimers]]} {
    utimer 60 nationalday:tick
}

putlog "=== NationalDay v8.1 READY  max $nationalday(max_irc) shown in IRC + full list at $nationalday(html_baseurl)/$nationalday(html_file) ==="

