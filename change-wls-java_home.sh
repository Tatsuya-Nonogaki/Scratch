#!/bin/bash
# This script updates JDK path references in WebLogic DOMAIN_HOME configuration 
# files, and can also report or update the JAVA_HOME property used by Oracle 
# Universal Installer (OUI).
#
# Designed for Oracle WebLogic Server and Oracle Fusion Middleware environments 
# where coordinated JDK path updates are needed.
#
# Version 2.1.12

### Edit JAVA_HOME strings here:
NEW_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_451-oracle-x64
OLD_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_411-oracle-x64

# --- SAFE_MODE: Prevent any accidental modification during testing or dry runs ---
# !!! WARNING !!!
# SAFE_MODE is enabled by default to prevent accidental modification of the Middleware environment.
# Set SAFE_MODE=0 **only after** you have reviewed and tested this script in your environment.
SAFE_MODE=1

MYBASENAME=$(basename "$0")
LIST_ONLY=0
VERBOSE_LIST=0
AUTO_YES_ALL=0
DO_DOMAIN=0
DO_OUI=0
TEST_JDK_STRING=""

show_help() {
   cat <<EOM
Usage: $MYBASENAME [OPTION]
  -l: List-only mode. List matching files and exit without modification.
  -v: Verbose list-only mode. Print matching lines with filenames. Use together
      with -l or -t ; -v alone has no effect.
  -d: Process files under DOMAIN_HOME.
  -o: Process ORACLE_HOME (OUI JAVA_HOME property).
      If neither or both -d and -o are specified, both locations are processed.
  -t <JAVA_HOME>: Test for occurrences of the given JAVA_HOME string under DOMAIN_HOME
      and/or ORACLE_HOME instantly, without editing OLD_JDK_STRING definition.
      No files will be modified, as this option always implies -l (list-only).
  -h: Show this help.

Note: Environment variables DOMAIN_HOME and/or ORACLE_HOME must be defined,
depending on the processing options.

Note: The ORACLE_HOME listing feature (-o + -l) is intended for reference only.
Manual replacement of JAVA_HOME under ORACLE_HOME is not recommended; this script
follows Oracle's official update method (setProperty.sh) only, for ORACLE_HOME.
Some old JAVA_HOME paths may remain after a change, but this is generally not an
issue --just leave them unless specifically instructed otherwise by Oracle Support.

*** WARNING: SAFE_MODE is enabled by default ***
    This prevents any modification of the Middleware environment.
    To allow actual changes, set SAFE_MODE=0 at the top of this script
    only after review and testing.
EOM
}

# Option parsing
while getopts "ldovht:" opt; do
  case $opt in
    l) LIST_ONLY=1 ;;
    v) VERBOSE_LIST=1 ;;
    d) DO_DOMAIN=1 ;;
    o) DO_OUI=1 ;;
    t) TEST_JDK_STRING="$OPTARG"; LIST_ONLY=1 ;;
    h|*) show_help; exit 0 ;;
  esac
done

# --- SAFE_MODE ENFORCEMENT ---
if [ "$SAFE_MODE" = "1" ]; then
    LIST_ONLY=1
    echo "Warning: Script is running in SAFE_MODE. No modifications will be made, regardless of what options are passed at runtime."
    if [ -n "$JAVA_HOME" ]; then
        NEW_JDK_STRING="$JAVA_HOME"
        OLD_JDK_STRING="$JAVA_HOME"
        echo "Both search and replace strings set to current system JAVA_HOME: $JAVA_HOME"
    fi
    echo
fi

# If neither or both -d/-o given, process both
if [ $DO_DOMAIN -eq 0 ] && [ $DO_OUI -eq 0 ]; then
    DO_DOMAIN=1
    DO_OUI=1
fi

# Global environment variable checks
if [ $DO_DOMAIN -eq 1 ] && [ -z "$DOMAIN_HOME" ]; then
    echo "Environment variable DOMAIN_HOME must be defined."
    exit 2
fi
if [ $DO_OUI -eq 1 ] && [ -z "$ORACLE_HOME" ]; then
    echo "Environment variable ORACLE_HOME must be defined."
    exit 2
fi

# Prepare OUI current JDK string if needed
if [ $DO_OUI -eq 1 ]; then
    OUI_BIN="$ORACLE_HOME/oui/bin"
    CURRENT_OUI_JDK_STRING=$("$OUI_BIN/getProperty.sh" JAVA_HOME 2>/dev/null)
    if [ -z "$CURRENT_OUI_JDK_STRING" ]; then
        echo "Error: Failed to fetch current JAVA_HOME from OUI. Either 'getProperty.sh' encountered an error, or the JAVA_HOME property is empty or missing."
        exit 2
    fi
fi

# Set active search variables and target labels
if [ -n "$TEST_JDK_STRING" ]; then
    SEARCH_JDK_STRING="$TEST_JDK_STRING"
    target_label="TEST"
else
    SEARCH_JDK_STRING="$OLD_JDK_STRING"
    target_label="OLD"
fi

# Function: Escape the old/new JDK strings for Perl regex and replacement (DOMAIN_HOME)
escape_perl_regex() {
    printf '%s' "$1" | perl -pe 's/([\[\]\(\)\{\}\^\$\.\|\?\*\+\\\/])/\\$1/g'
}
escape_perl_replace() {
    printf '%s' "$1" | perl -pe 's/([\\\$\@])/\\$1/g'
}

if [ $DO_DOMAIN -eq 1 ]; then
    if [ -z "$TEST_JDK_STRING" ]; then
        PERL_DOMAIN_OLD=$(escape_perl_regex "$OLD_JDK_STRING")
        PERL_DOMAIN_NEW=$(escape_perl_replace "$NEW_JDK_STRING")
    fi
fi

# Function: Find files containing the given path string
find_files() {
    # arg1:search_root arg2:string arg3-*:dirs_to_exclude(space-separated)
    local search_root="$1"
    local search_string="$2"
    shift 2
    local exclude_dirs=("$@")
    local grep_excludes=()
    for ex in "${exclude_dirs[@]}"; do
        grep_excludes+=(--exclude-dir "$ex")
    done

    if [ "$VERBOSE_LIST" = "1" ]; then
        grep -Fnr "${grep_excludes[@]}" "$search_string" "$search_root" | grep -Ev "\.log|\.out"
    else
        grep -FIlr "${grep_excludes[@]}" "$search_string" "$search_root" | grep -Ev "\.log|\.out"
    fi
}

# Function: replace string in DOMAIN_HOME files
replace_domain_string() {
    # If AUTO_YES_ALL is set, always proceed
    if [ $AUTO_YES_ALL -eq 1 ]; then
        echo "processing '$1'"
        perl -pi -e "s%$PERL_DOMAIN_OLD%$PERL_DOMAIN_NEW%g;" "$1"
        return
    fi

    local ACK
    echo "string found in '$1'"
    read -t 10 -p "Do you want me to proceed? ([y]/n/a(=all)): " ACK </dev/tty
    : ${ACK:=y}

    if [ "$ACK" = "y" ] || [ "$ACK" = "Y" ]; then
        echo -e "processing '$1'\n"
        perl -pi -e "s%$PERL_DOMAIN_OLD%$PERL_DOMAIN_NEW%g;" "$1"
    elif [ "$ACK" = "a" ] || [ "$ACK" = "A" ]; then
        echo "processing '$1'"
        echo -e "Continue processing in non-interactive mode.\n"
        AUTO_YES_ALL=1
        perl -pi -e "s%$PERL_DOMAIN_OLD%$PERL_DOMAIN_NEW%g;" "$1"
    else
        echo -e "skipped\n"
    fi
}

# Process DOMAIN_HOME files if requested
if [ $DO_DOMAIN -eq 1 ]; then
    echo "We are processing DOMAIN_HOME: $DOMAIN_HOME"
    echo "${target_label}_JDK_STRING: $SEARCH_JDK_STRING"
    if [ -z "$TEST_JDK_STRING" ]; then
        echo "NEW_JDK_STRING: $NEW_JDK_STRING"
    fi

    file_list_domain=$(find_files "$DOMAIN_HOME" "$SEARCH_JDK_STRING" logs tmp adr)
    if [ $LIST_ONLY -eq 1 ]; then
        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "Listing files and matching lines containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in DOMAIN_HOME"
        else
            echo "Listing files containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in DOMAIN_HOME"
        fi
        echo "-----------------------------------------------------------------------"
        if [ -z "$file_list_domain" ]; then
            echo "No matching files found."
        else
            echo "$file_list_domain"
        fi
        echo "-----------------------------------------------------------------------"
        # Do not exit here if DO_OUI=1; let OUI processing run too
    else
        while read -r FNAME; do
            [ -z "$FNAME" ] && continue
            if [ ! -f "$FNAME" ]; then
                echo "No such file '$FNAME'"
                continue
            fi
            replace_domain_string "$FNAME"
        done <<< "$file_list_domain"
    fi
fi

# Process ORACLE_HOME/OUI JAVA_HOME if requested
if [ $DO_OUI -eq 1 ]; then
    echo "We are processing ORACLE_HOME: $ORACLE_HOME"
    echo "${target_label}_JDK_STRING: $SEARCH_JDK_STRING"
    if [ -z "$TEST_JDK_STRING" ]; then
        echo "NEW_JDK_STRING: $NEW_JDK_STRING"
    fi

    file_list_oracle=$(find_files "$ORACLE_HOME" "$SEARCH_JDK_STRING" .patch_storage logs tmp)
    if [ $LIST_ONLY -eq 1 ]; then
        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "Listing files and matching lines containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in ORACLE_HOME"
        else
            echo "Listing files containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in ORACLE_HOME"
        fi
        echo "-----------------------------------------------------------------------"
        if [ -z "$file_list_oracle" ]; then
            echo "No matching files found."
        else
            echo "$file_list_oracle"
        fi
        echo "-----------------------------------------------------------------------"
        exit 0
    fi

    # Before actual replacement, check if OLD_JDK_STRING matches current JAVA_HOME property
    if [ -z "$TEST_JDK_STRING" ]; then
        if [ "$OLD_JDK_STRING" != "$CURRENT_OUI_JDK_STRING" ]; then
            echo "Error: OLD_JDK_STRING ('$OLD_JDK_STRING') does not match current OUI JAVA_HOME ('$CURRENT_OUI_JDK_STRING')."
            echo "Aborting to prevent incorrect update. Please verify your configuration."
            exit 2
        fi
    fi

    # Interactive confirmation before backup and update
    read -t 10 -p "Backup and update OUI JAVA_HOME? ([y]/n): " OUI_ACK
    : ${OUI_ACK:=y}

    if [ "$OUI_ACK" = "y" ] || [ "$OUI_ACK" = "Y" ]; then
        echo "Backing up current JAVA_HOME to OLD_JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name OLD_JAVA_HOME -value "$CURRENT_OUI_JDK_STRING"
        RESULT_OLD_JAVA_HOME=$("$OUI_BIN/getProperty.sh" OLD_JAVA_HOME 2>/dev/null)
        if [ "$RESULT_OLD_JAVA_HOME" != "$CURRENT_OUI_JDK_STRING" ]; then
            echo "Error: Failed to back up to OLD_JAVA_HOME property in OUI."
            echo "Expected: '$CURRENT_OUI_JDK_STRING'"
            echo "Actual:   '$RESULT_OLD_JAVA_HOME'"
            exit 1
        fi

        echo "Updating JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name JAVA_HOME -value "$NEW_JDK_STRING"
        RESULT_OUI_JDK_STRING=$("$OUI_BIN/getProperty.sh" JAVA_HOME 2>/dev/null)
        if [ "$RESULT_OUI_JDK_STRING" != "$NEW_JDK_STRING" ]; then
            echo "Error: JAVA_HOME property in OUI was not updated as expected."
            echo "Expected: '$NEW_JDK_STRING'"
            echo "Actual:   '$RESULT_OUI_JDK_STRING'"
            exit 1
        fi
        echo "OUI JAVA_HOME updated."
    else
        echo "OUI JAVA_HOME update skipped."
    fi
fi
