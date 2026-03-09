##############################[ TVmaze.com Eggdrop Script ]######################
#                                                                               #
variable tvmazeversion 1.25
#                                                                               #
# Author   : x0x a.k.a. ericNL (freenode + EFnet)                               #
# Source   : http://forum.egghelp.org/viewtopic.php?t=20045                     #
#            Latest version of this script always in the 1st post of the topic! #
#                                                                               #
# Activate : Party line command: .chanset #channel +tvmaze                      #
# Commands : !tv or !t <show>    !last or !l <show>    !next or !n <show>       #
#                                                                               #
# Credits  : GaveUp, dlx, Znuff, speechles, nrt, Chokladkakan                   #
#            Viper (Jan Milants), thommey, GPenguin                             #
#                                                                               #
# Greets   : Everyone over at http://forum.egghelp.org                          #
#            The freenode #eggdrop crowd                                        #
#            My friends in #<translate-shark-to-dutch> on EFnet ;)              #
#                                                                               #
#################################################################################

# We'll be needing these to run the script.
package require http
package require json

# Don't forget to activate the script by setting .chanset #channel +tvmaze
setudef flag tvmaze

# The channel triggers.
bind pub - !tv tv
bind pub - !t tv

bind pub - !last tvlast
bind pub - !l tvlast

bind pub - !next tvnext
bind pub - !n tvnext

# Handle the !tv and !t triggers.
proc tv { nick host hand chan arg } {

	# Basic warez scene formatting support.
	# Translate 'The.Big.Bang.Theory.S09E01.720p.HDTV.X264-DIMENSION' to 'The Big Bang Theory' so that TVmaze understands your query.
	regsub -nocase -all {(\.| )([[:digit:]]{4}(\.| )|)(S[[:digit:]]{2}E[[:digit:]]{2}(\.| )|)(INTERNAL|INT|1080p|720p|HDTV|x264|WEBRip|REPACK|REAL|PROPER)(\.| ).*} $arg "" arg
	regsub -all "\\." $arg " " arg

	# This is where we contact TVmaze.
	set url "http://api.tvmaze.com/singlesearch/shows?[::http::formatQuery q $arg embed\[\] nextepisode embed\[\] previousepisode]"
	set timeout "5000"

	if {[catch { ::http::geturl $url -timeout $timeout } token]} {
	putquick "privmsg $chan :$nick, there was a fatal error :$token."
	return 0
	}

	if {![string equal -nocase [::http::status $token] "ok"] || ![string equal [::http::ncode $token] 200]} {
	putquick "privmsg $chan :$nick, there was an http error: ( [http::ncode $token] ) [::http::status $token]"
	http::cleanup $token
	return 0
	}

	# Translate the TVmaze JSON data to Tcl dict which makes it possible for us to display the requested info in the IRC channel(s).
	set tvmaze [::json::json2dict [::http::data $token]]
	::http::cleanup $token

	dict with tvmaze {

	# Set the network name.
	# Is the show you're looking for available on Amazon/Netflix etc. or a network like ABC/HBO/Showtime etc.?
	if {[string equal "null" $webChannel]} { set network [dict get $tvmaze network name] } else { set network [dict get $tvmaze webChannel name] }

	# If there is any info on a next episode, make sure we can use that info later on.
	if { [dict exists $tvmaze _embedded nextepisode url] } { set nextepurl [dict get $tvmaze _embedded nextepisode url] }
	if { [dict exists $tvmaze _embedded nextepisode name] } { set nextepname [dict get $tvmaze _embedded nextepisode name] }
	if { [dict exists $tvmaze _embedded nextepisode season] } { set nextepseason [dict get $tvmaze _embedded nextepisode season] }
	if { [dict exists $tvmaze _embedded nextepisode number] } { set nextepnumber [dict get $tvmaze _embedded nextepisode number] }
	if { [dict exists $tvmaze _embedded nextepisode airdate] } { set nextepairdate [dict get $tvmaze _embedded nextepisode airdate] }
	if { [dict exists $tvmaze _embedded nextepisode airtime] } { set nextepairtime [dict get $tvmaze _embedded nextepisode airtime] }
	if { [dict exists $tvmaze _embedded nextepisode runtime] } { set nextepruntime [dict get $tvmaze _embedded nextepisode runtime] }
	if { [dict exists $tvmaze _embedded nextepisode summary] } { set nextepsummary [dict get $tvmaze _embedded nextepisode summary] }

	# Same as above but now for the last/previous episode.
	if { [dict exists $tvmaze _embedded previousepisode url] } { set prevepurl [dict get $tvmaze _embedded previousepisode url] }
	if { [dict exists $tvmaze _embedded previousepisode name] } { set prevepname [dict get $tvmaze _embedded previousepisode name] }
	if { [dict exists $tvmaze _embedded previousepisode season] } { set prevepseason [dict get $tvmaze _embedded previousepisode season] }
	if { [dict exists $tvmaze _embedded previousepisode number] } { set prevepnumber [dict get $tvmaze _embedded previousepisode number] }
	if { [dict exists $tvmaze _embedded previousepisode airdate] } { set prevepairdate [dict get $tvmaze _embedded previousepisode airdate] }
	if { [dict exists $tvmaze _embedded previousepisode airtime] } { set prevepairtime [dict get $tvmaze _embedded previousepisode airtime] }
	if { [dict exists $tvmaze _embedded previousepisode runtime] } { set prevepruntime [dict get $tvmaze _embedded previousepisode runtime] }
	if { [dict exists $tvmaze _embedded previousepisode summary] } { set prevepsummary [dict get $tvmaze _embedded previousepisode summary] }

	# Set the airtime (if exists) and reformat the 24-hour clock data supplied by TVmaze to a 12-hour clock format.
	if { [dict exists $tvmaze _embedded nextepisode airstamp] } {
	set airstamp [clock scan [dict get $tvmaze _embedded nextepisode airstamp] -format {%Y-%m-%dT%H:%M:%S%z}]
	set airstampnyc [clock format $airstamp -format {%I:%M %p %Z} -timezone :America/New_York]
	}

	if { ![info exists name] } {
		putquick "privmsg $chan :$nick, nothing happened, try something different? :)"
		return 0
	}

	# Add a leading 0 if the season number is 1-9. Do the same for episode numbers 1-9. This formats S1E1 to S01E01 to match warez scene formatting.
	if { [info exists prevepseason] } { set prevepseason [format S%02d $prevepseason] }
	if { [info exists prevepnumber] } { set prevepnumber [format E%02d $prevepnumber] }
	if { [info exists nextepseason] } { set nextepseason [format S%02d $nextepseason] }
	if { [info exists nextepnumber] } { set nextepnumber [format E%02d $nextepnumber] }

	if { [info exists nextepname] && [info exists prevepname] && ![llength $genres] == 1 } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Previous: $prevepseason$prevepnumber aired $prevepairdate \u2022 Next: $nextepseason$nextepnumber airs $nextepairdate at $airstampnyc"
    	return 0
		}

	if { [info exists nextepname] && [info exists prevepname] } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network \u2022 Genre: $genres"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Previous: $prevepseason$prevepnumber aired $prevepairdate \u2022 Next: $nextepseason$nextepnumber airs $nextepairdate at $airstampnyc"
		return 0
		}

	if { ![info exists nextepname] && [info exists prevepname] && ![llength $genres] == 1 } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Last: $prevepseason$prevepnumber aired $prevepairdate"
		return 0
        }

	if { ![info exists nextepname] && [info exists prevepname] } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network \u2022 Genre: $genres"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Last: $prevepseason$prevepnumber aired $prevepairdate"
		return 0
		}

	if { [info exists nextepname] && ![info exists prevepname] && ![llength $genres] == 1 } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Next episode: $nextepseason$nextepnumber airs $nextepairdate at $airstampnyc"
		return 0
		}

	if { [info exists nextepname] && ![info exists prevepname] } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network \u2022 Genre: $genres"
		putquick "privmsg $chan :Premiered: $premiered \u2022 Status: $status \u2022 URL: $url"
		putquick "privmsg $chan :Next episode: $nextepseason$nextepnumber airs $nextepairdate at $airstampnyc"
		return 0
		}

	if { ![info exists nextepname] && ![info exists previousepname] && ![llength $genres] == 1 } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network"
		putquick "privmsg $chan :Status: $status \u2022 URL: $url"
		return 0
		}

	if { ![info exists nextepname] && ![info exists previousepname] } {
		putquick "privmsg $chan :Show: \002$name\002 \u2022 Network: $network \u2022 Genre: $genres"
		putquick "privmsg $chan :Status: $status \u2022 URL: $url"
		return 0
		}

	}

}

# Handle the !next and !n triggers.
proc tvnext { nick host hand chan arg } {

	set url "http://api.tvmaze.com/singlesearch/shows?[::http::formatQuery q $arg embed\[\] nextepisode embed\[\] previousepisode]"
	set timeout "5000"

	if {[catch { ::http::geturl $url -timeout $timeout } token]} {
	putquick "privmsg $chan :$nick, there was a fatal error :$token."
	return 0
	}

	if {![string equal -nocase [::http::status $token] "ok"] || ![string equal [::http::ncode $token] 200]} {
	putquick "privmsg $chan :$nick, there was an http error: ( [http::ncode $token] ) [::http::status $token]"
	http::cleanup $token
	return 0
	}

	set tvmaze [::json::json2dict [::http::data $token]]
	::http::cleanup $token

	dict with tvmaze {

	if {[string equal "null" $webChannel]} { set network [dict get $tvmaze network name] } else { set network [dict get $tvmaze webChannel name] }

	if { [dict exists $tvmaze _embedded nextepisode url] } { set nextepurl [dict get $tvmaze _embedded nextepisode url] }
	if { [dict exists $tvmaze _embedded nextepisode name] } { set nextepname [dict get $tvmaze _embedded nextepisode name] }
	if { [dict exists $tvmaze _embedded nextepisode season] } { set nextepseason [dict get $tvmaze _embedded nextepisode season] }
	if { [dict exists $tvmaze _embedded nextepisode number] } { set nextepnumber [dict get $tvmaze _embedded nextepisode number] }
	if { [dict exists $tvmaze _embedded nextepisode airdate] } { set nextepairdate [dict get $tvmaze _embedded nextepisode airdate] }
	if { [dict exists $tvmaze _embedded nextepisode airtime] } { set nextepairtime [dict get $tvmaze _embedded nextepisode airtime] }
	if { [dict exists $tvmaze _embedded nextepisode runtime] } { set nextepruntime [dict get $tvmaze _embedded nextepisode runtime] }
	if { [dict exists $tvmaze _embedded nextepisode summary] } { set nextepsummary [dict get $tvmaze _embedded nextepisode summary] }

	if { [dict exists $tvmaze _embedded nextepisode airstamp] } {
	set airstamp [clock scan [dict get $tvmaze _embedded nextepisode airstamp] -format {%Y-%m-%dT%H:%M:%S%z}]
	set airstampnyc [clock format $airstamp -format {%I:%M %p %Z} -timezone :America/New_York]
	}

	if { ![info exists nextepname] } {
        	putquick "privmsg $chan :$nick, no next episode information."
			return 0
		}

		set nextepseason [format S%02d $nextepseason]
		set nextepnumber [format E%02d $nextepnumber]

	putquick "privmsg $chan :Show: \002$name\002 \u2022 Next episode: $nextepseason$nextepnumber \"$nextepname\" airs $nextepairdate at $airstampnyc"

	}

}

# Handle the !last and !l triggers.
proc tvlast { nick host hand chan arg } {

	set url "http://api.tvmaze.com/singlesearch/shows?[::http::formatQuery q $arg embed\[\] nextepisode embed\[\] previousepisode]"
	set timeout "5000"

	if {[catch { ::http::geturl $url -timeout $timeout } token]} {
	putquick "privmsg $chan :$nick, there was a fatal error :$token."
	return 0
	}

	if {![string equal -nocase [::http::status $token] "ok"] || ![string equal [::http::ncode $token] 200]} {
	putquick "privmsg $chan :$nick, there was an http error: ( [http::ncode $token] ) [::http::status $token]"
	http::cleanup $token
	return 0
	}

	set tvmaze [::json::json2dict [::http::data $token]]
	::http::cleanup $token

	dict with tvmaze {

	if {[string equal "null" $webChannel]} { set network [dict get $tvmaze network name] } else { set network [dict get $tvmaze webChannel name] }

	if { [dict exists $tvmaze _embedded previousepisode url] } { set prevepurl [dict get $tvmaze _embedded previousepisode url] }
	if { [dict exists $tvmaze _embedded previousepisode name] } { set prevepname [dict get $tvmaze _embedded previousepisode name] }
	if { [dict exists $tvmaze _embedded previousepisode season] } { set prevepseason [dict get $tvmaze _embedded previousepisode season] }
	if { [dict exists $tvmaze _embedded previousepisode number] } { set prevepnumber [dict get $tvmaze _embedded previousepisode number] }
	if { [dict exists $tvmaze _embedded previousepisode airdate] } { set prevepairdate [dict get $tvmaze _embedded previousepisode airdate] }
	if { [dict exists $tvmaze _embedded previousepisode airtime] } { set prevepairtime [dict get $tvmaze _embedded previousepisode airtime] }
	if { [dict exists $tvmaze _embedded previousepisode runtime] } { set prevepruntime [dict get $tvmaze _embedded previousepisode runtime] }
	if { [dict exists $tvmaze _embedded previousepisode summary] } { set prevepsummary [dict get $tvmaze _embedded previousepisode summary] }

	if { ![info exists prevepname] } {
        	putquick "privmsg $chan :$nick, no last episode information."
			return 0
		}

		set prevepseason [format S%02d $prevepseason]
		set prevepnumber [format E%02d $prevepnumber]

        	putquick "privmsg $chan :Show: \002$name\002 \u2022 Last episode: $prevepseason$prevepnumber \"$prevepname\" aired $prevepairdate"

	}

}

putlog "TVmaze.com Eggdrop Script by x0x/ericNL version $tvmazeversion loaded!"

#eof