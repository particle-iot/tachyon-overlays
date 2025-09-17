#!/usr/bin/expect -f
#
# test-gnss: run a GNSS signal capture and validation workflow.
#
# Usage:
#   test-gnss.sh [--sleep <seconds>] [--skip-validate]
#
# Description:
#   This script collects GNSS NMEA sentences and parses them to either
#   validate the expected simulated signal exists, or print all detected satellites.
#
# Options:
#   --sleep <seconds>   set data-collection timeout in seconds (default is 10)
#   --skip-validate     skip validation phase and only parse NMEA sentences (for use outside of factory test env)
#
# Environment Variables:
#   DEBUG=true          enable real-time logging of interactive prompts and NMEA output
#
# Exit Codes:
#   0    PASS – GNSS test passed and validation succeeded
#   1    FAIL – pre-check, parsing, or validation error occurred
#
set timeout 120

# enable logging if DEBUG=true, otherwise suppress all stdout until the end
if {[info exists env(DEBUG)] && $env(DEBUG) == "true"} {
    # DEBUG mode: show interactive prompts and NMEA sentences live
    # Note: you won't see the full output until the end, and there is a pause
    # between the last qlril-api-test prompt and the final output.
    log_user 1
} else {
    # normal mode: hide confusing interleaved output and show full buffered log at the end
    log_user 0
}

# === Parameters ===
set sleep_duration 10
set skip_validate 0

# parse flags
set argc [llength $argv]
set i 0
while {$i < $argc} {
    set arg [lindex $argv $i]
    switch -- $arg {
        "--sleep" {
            incr i
            if {$i < $argc} {
                set sleep_duration [lindex $argv $i]
            } else {
                puts "ERROR: --sleep requires a value"
                exit 1
            }
        }
        "--skip-validate" {
            set skip_validate 1
        }
        default {
            puts "ERROR: unrecognized argument: $arg"
            puts "Usage: test-gnss.sh [--sleep <seconds>] [--skip-validate]"
            exit 1
        }
    }
    incr i
}

set raw_log "/tmp/gnss_captured.log"
set inner_script "/tmp/gnss_inner.expect"
set FAIL 0

# === Cleanup ===
file delete -force $raw_log
file delete -force $inner_script

# === Pre-check: qlrild.service must be active ===
catch {exec systemctl is-active qlrild.service} qlrild_status
if { $qlrild_status ne "active" } {
    puts "ERROR: qlrild.service is not running (status: $qlrild_status)"
    set FAIL 1
}

# === Build inner Expect ===
if {!$FAIL} {
    set fh [open $inner_script w]
    puts $fh "#!/usr/bin/expect -f"
    puts $fh "set timeout 119"
    puts $fh "spawn qlril-api-test"
    puts $fh "expect \"Please input cmd index\"; send \"90\\r\""
    puts $fh "expect \"Please input cmd index\"; send \"95\\r\""
    puts $fh "sleep $sleep_duration"
    puts $fh "send \"\\003\""
    puts $fh "expect eof"
    close $fh
    exec chmod +x $inner_script
}

# === Run GNSS test inside script for TTY behavior ===
if {!$FAIL} {
    send_user "Running GNSS test for $sleep_duration seconds. Full output will appear when it finishes.\n"
    spawn script -q -c "/usr/bin/expect $inner_script" $raw_log
    expect eof
}

# === Run JS helper (parse or validate) ===
if {[file exists $raw_log]} {
    if {$skip_validate} {
        # not validating, just parsing the log for readable NMEA sentences
        set js_cmd "node /opt/particle/tests/gnss-log-helper.js $raw_log --parse"
    } else {
        # validating the log for expected NMEA sentences
        set js_cmd "node /opt/particle/tests/gnss-log-helper.js $raw_log"
    }

    puts "Running command: $js_cmd"
    set js_exit [catch {exec sh -c "$js_cmd 2>&1"} js_result]

    puts "===== LOG HELPER OUTPUT BEGIN ====="
    puts "$js_result"
    puts "===== LOG HELPER OUTPUT END ====="

    # fail if parser produced no output
    if {[string trim $js_result] eq ""} {
        puts "FAIL: log helper error (no output)"
        puts "Raw log contents:"
        puts [exec cat $raw_log]
        set FAIL 1
    }

    if {$js_exit != 0} {
        puts "FAIL: GNSS validation failed or unexpected error occurred"
        set FAIL 1
    }

    if {!$FAIL && $skip_validate} {
        puts "GNSS signal scan complete, validation skipped"
    }

    if {!$FAIL && !$skip_validate} {
        puts "GNSS signal validation complete"
    }
} else {
    puts "ERROR: GNSS test log does not exist"
    set FAIL 1
}

# === Final result logging ===
if {$FAIL} {
    puts "FAIL"
    exit 1
} else {
    puts "PASS"
    exit 0
}
