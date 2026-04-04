# =============================================================================
# nationalday.tcl    SUPER FUN v9.0 (daysoftheyear.com)
# Cleaned "Wide-Net" Parser with UI Blacklist
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

set nationalday(max_irc)      10       
set nationalday(html_dir)     "/web/irc.bbses.info/nationaldays"
set nationalday(html_file)    "index.html"
set nationalday(html_baseurl) "http://irc.bbses.info/nationaldays"

# Cache
set nationalday(cache_html) ""
set nationalday(cache_date) ""

putlog "=== NationalDay SUPER FUN v9.0 (cleaned parser) loading ==="

catch {http::register https 443 ::tls::socket}

# =============================================================================
# Fetch page - Browser Emulation Mode
# =============================================================================
proc nationalday:fetch_page {} {
    global nationalday
    set today [clock format [clock seconds] -format "%Y-%m-%d"]

    if {$nationalday(cache_date) eq $today && $nationalday(cache_html) ne ""} {
        return $nationalday(cache_html)
    }

    set url "https://www.daysoftheyear.com/today/"
    putlog "NationalDay: Fetching $url"

    if {[catch {
        set full_output [exec curl -s -k -L --max-time 30 \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
            -H "Referer: https://www.google.com/" \
            -w "\nHTTPSTATUS:%{http_code}" \
            $url 2>@1 ]

        set lines [split $full_output "\n"]
        set html [join [lrange $lines 0 end-1] "\n"]
        
        if {![regexp {HTTPSTATUS:200} $full_output]} {
            putlog "NationalDay: HTTP error fetching site."
            return ""
        }
    } err]} {
        putlog "NationalDay: CURL ERROR - $err"
        return ""
    }

    set nationalday(cache_html) $html
    set nationalday(cache_date) $today
    return $html
}

# =============================================================================
# CLEANED PARSER v9.0
# =============================================================================
proc nationalday:get_todays_holidays {} {
    global nationalday
    set html [nationalday:fetch_page]
    if {$html eq ""} { return [list] }

    set days [list]
    set blacklist {
        "days by month" "choose month" "previous month" "next month" 
        "open calendar" "submit" "search" "login" "menu" "logo" "twitter"
        "facebook" "instagram" "pinterest" "share" "policy" "contact"
    }

    # Extract from aria-labels, alt tags, and link text
    set patterns {
        {aria-label="([^"]*(?:Day|Week|Month|Eve|Festival)[^"]*)"}
        {alt="([^"]*(?:Day|Week|Month|Eve|Festival)[^"]*)"}
        {<a[^>]*>([^<]*(?:Day|Week|Month|Eve|Festival)[^<]*)</a>}
    }

    foreach pattern $patterns {
        set start 0
        while {[regexp -nocase -start $start -indices $pattern $html match sub]} {
            set dayname [string range $html [lindex $sub 0] [lindex $sub 1]]
            
            # Remove HTML tags and fix encoding
            regsub -all {<[^>]+>} $dayname "" dayname
            set dayname [string map {
                &amp; & &lt; < &gt; > &#039; ' &quot; \" &nbsp; " " 
                &#x20; " " &#8217; ' &#8211; - 
            } $dayname]
            set dayname [regsub -all {\s+} $dayname " "]
            set dayname [string trim $dayname]

            # Filter logic
            set skip 0
            foreach item $blacklist {
                if {[string match -nocase "*$item*" $dayname]} { set skip 1; break }
            }

            if {!$skip && [string length $dayname] > 5 && [string length $dayname] < 80} {
                if {[lsearch -exact $days $dayname] == -1} {
                    lappend days $dayname
                }
            }
            set start [expr {[lindex $match 1] + 1}]
        }
    }

    putlog "NationalDay: Found [llength $days] clean entries."
    return $days
}

# =============================================================================
# IRC Output & HTML Generation
# =============================================================================
proc nationalday:announce {{target_chan ""}} {
    global nationalday
    set chan [expr {$target_chan ne "" ? $target_chan : $nationalday(chan)}]
    set datestr [clock format [clock seconds] -format "%A, %B %d, %Y" -timezone :$nationalday(timezone)]
    
    set days [nationalday:get_todays_holidays]

    if {[llength $days] == 0} {
        puthelp "PRIVMSG $chan :\003$nationalday(color)$nationalday(bold) National Days\003 Data unavailable for $datestr."
        return
    }

    set count [llength $days]
    puthelp "PRIVMSG $chan :\003$nationalday(color)$nationalday(bold) TODAY'S NATIONAL DAYS  $datestr ($count total)\003"

    set num 1
    foreach d [lrange $days 0 [expr {$nationalday(max_irc)-1}]] {
        puthelp "PRIVMSG $chan :  \003$nationalday(cyellow)$nationalday(bold)$num.\003 $d"
        incr num
    }

    if {$count > $nationalday(max_irc)} {
        puthelp "PRIVMSG $chan :   \00312... and [expr {$count - $nationalday(max_irc)}] more at:\003 $nationalday(html_baseurl)/$nationalday(html_file)"
    }

    nationalday:generate_html $days $datestr
}

proc nationalday:generate_html {days datestr} {
    global nationalday
    catch {file mkdir $nationalday(html_dir)}
    set filepath [file join $nationalday(html_dir) $nationalday(html_file)]
    if {[catch {
        set fd [open $filepath w]
        puts $fd "<html><head><meta charset=\"utf-8\"><title>National Days - $datestr</title>"
        puts $fd "<style>body{font-family:sans-serif;background:#eee;padding:20px}ul{background:white;padding:20px;border-radius:10px}</style></head>"
        puts $fd "<body><h1>$datestr</h1><ul>"
        foreach d $days { puts $fd "<li>$d</li>" }
        puts $fd "</ul></body></html>"
        close $fd
    } err]} { putlog "NationalDay: HTML error $err" }
}

# --- Scheduler ---
proc nationalday:tick {} {
    global nationalday
    set h [string trimleft [clock format [clock seconds] -format "%H" -timezone :$nationalday(timezone)] 0]
    set m [string trimleft [clock format [clock seconds] -format "%M" -timezone :$nationalday(timezone)] 0]
    if {$h eq ""} {set h 0}; if {$m eq ""} {set m 0}
    if {$h == $nationalday(hour) && $m == $nationalday(minute)} {
        set nationalday(cache_html) ""; nationalday:announce
    }
    utimer 60 nationalday:tick
}

bind pub - !nationalday nationalday:trig_today
proc nationalday:trig_today {nick host hand chan text} { nationalday:announce $chan }

if {![string match "*nationalday:tick*" [utimers]]} { utimer 60 nationalday:tick }
putlog "=== NationalDay v9.0 READY ==="
