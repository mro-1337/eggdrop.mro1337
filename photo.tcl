################################################################
# AI Image Generator - Hugging Face Router (Updated API)
################################################################

# --- CONFIGURATION ---
set ai_hf_token "GET IT FROM HUGGING FACE"
set ai_save_path "/web/CHANGEME/irc.pics"
set ai_web_url "http://CHANGEME/irc.pics"
set ai_model "stabilityai/stable-diffusion-xl-base-1.0"
# ---------------------

bind pub - "!make" pub_ai_image
bind pubm - "* make me a photo of *" pubm_ai_image

proc pubm_ai_image {nick host hand chan text} {
    if {[regexp -nocase {make me a photo of (.+)} $text match prompt]} {
        process_ai_image $nick $chan $prompt
    }
}

proc pub_ai_image {nick host hand chan text} {
    if {$text == ""} {
        putserv "PRIVMSG $chan :Usage: !make <description>"
        return
    }
    process_ai_image $nick $chan $text
}

proc process_ai_image {nick chan prompt} {
    global ai_save_path ai_web_url ai_hf_token ai_model

    # Clean prompt: remove quotes to avoid JSON breaks
    set clean_prompt [string map {"\"" ""} $prompt]
    
    set filename "ai_[clock seconds].jpg"
    set full_dest "$ai_save_path/$filename"

    putserv "PRIVMSG $chan :$nick: Sending request to the new AI router... please wait."

    # NEW Hugging Face Router Endpoint
    set api_url "https://router.huggingface.co/hf-inference/models/$ai_model"
    
    # Construct the JSON payload string safely
    set json_payload "{\"inputs\": \"$clean_prompt\"}"

    # Executing curl with the new URL
    if {[catch {exec curl -s -L -X POST $api_url \
        -H "Authorization: Bearer $ai_hf_token" \
        -H "Content-Type: application/json" \
        --data-raw $json_payload \
        --max-time 120 \
        -o $full_dest} err]} {
        putlog "AI Error: Curl crash: $err"
    }

    if {[file exists $full_dest]} {
        set fsize [file size $full_dest]
        
        # Check for error message
        set fp [open $full_dest r]
        set header [read $fp 20]
        close $fp

        # Look for the JSON "error" indicator
        if {[string match "*\"error\"*" $header] || $fsize < 3000} {
            set fp [open $full_dest r]
            set full_err [read $fp 200]
            close $fp
            
            putlog "AI Error: API returned: $full_err"
            file delete $full_dest

            if {[string match "*loading*" $full_err]} {
                 putserv "PRIVMSG $chan :$nick: The AI lab is warming up. Try again in 20 seconds!"
            } else {
                 putserv "PRIVMSG $chan :$nick: The AI router rejected the request. (Check Logs)"
            }
        } else {
            putserv "PRIVMSG $chan :$nick: $ai_web_url/$filename"
        }
    } else {
        putserv "PRIVMSG $chan :$nick: Something went wrong with the download."
    }
}

putlog "AI Image Script (HF Router Version) Loaded."
