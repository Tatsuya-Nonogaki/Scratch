#!/bin/bash
# Searches and replaces JDK location strings among files in $DOMAIN_HOME,
# and can report or update JAVA_HOME in Oracle OUI ($ORACLE_HOME).
# Version 2.1.4

### Edit JAVA_HOME strings here:
NEW_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_451-oracle-x64
# Below is used only for DOMAIN_HOME
OLD_DOMAIN_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_411-oracle-x64

MYBASENAME=$(basename "$0")
LIST_ONLY=0
VERBOSE_LIST=0
AUTO_YES_ALL=0
DO_DOMAIN=0
DO_OUI=0

show_help() {
   cat <<EOM
Usage: $MYBASENAME [OPTION]
  -l: List-only mode. List matching files and exit without modification.
  -v: Verbose list-only mode. Print matching lines with filenames (use with -l).
  -d: Process files under DOMAIN_HOME.
  -o: Process ORACLE_HOME (OUI JAVA_HOME property).
      If neither or both -d and -o are specified, both locations are processed.
  -h: Show this help.

Note: Environment variables DOMAIN_HOME and/or ORACLE_HOME must be defined,
depending on the processing options.
EOM
}

# Option parsing
while getopts "ldovh" opt; do
  case $opt in
    l) LIST_ONLY=1 ;;
    v) VERBOSE_LIST=1 ;;
    d) DO_DOMAIN=1 ;;
    o) DO_OUI=1 ;;
    h|*) show_help; exit 0 ;;
  esac
done

# If neither or both -d/-o given, process both
if [ $DO_DOMAIN -eq 0 ] && [ $DO_OUI -eq 0 ]; then
  DO_DOMAIN=1
  DO_OUI=1
fi

# Global environment variable checks
if [ $DO_DOMAIN -eq 1 ] && [ -z "$DOMAIN_HOME" ]; then
    echo "Environment variable DOMAIN_HOME must be defined."
    exit 1
fi
if [ $DO_OUI -eq 1 ] && [ -z "$ORACLE_HOME" ]; then
    echo "Environment variable ORACLE_HOME must be defined."
    exit 1
fi

# Escape the old/new JDK strings for Perl regex and replacement (DOMAIN_HOME)
escape_perl_regex() {
    printf '%s' "$1" | perl -pe 's/([\[\]\(\)\{\}\^\$\.\|\?\*\+\\\/])/\\$1/g'
}
escape_perl_replace() {
    printf '%s' "$1" | perl -pe 's/([\\\$\@])/\\$1/g'
}

# String summary for each target
if [ $DO_DOMAIN -eq 1 ]; then
    NEW_DOMAIN_JDK_STRING="$NEW_JDK_STRING"
    PERL_DOMAIN_OLD=$(escape_perl_regex "$OLD_DOMAIN_JDK_STRING")
    PERL_DOMAIN_NEW=$(escape_perl_replace "$NEW_DOMAIN_JDK_STRING")
    echo "We are processing DOMAIN_HOME: $DOMAIN_HOME"
    echo "OLD_DOMAIN_JDK_STRING: $OLD_DOMAIN_JDK_STRING"
    echo "NEW_DOMAIN_JDK_STRING: $NEW_DOMAIN_JDK_STRING"
fi

if [ $DO_OUI -eq 1 ]; then
    echo "We are processing ORACLE_HOME: $ORACLE_HOME"
    OUI_BIN="$ORACLE_HOME/oui/bin"
    OLD_OUI_JDK_STRING=$("$OUI_BIN/getProperty.sh" JAVA_HOME 2>/dev/null)
    NEW_OUI_JDK_STRING="$NEW_JDK_STRING"
    echo "OLD_OUI_JDK_STRING: $OLD_OUI_JDK_STRING"
    echo "NEW_OUI_JDK_STRING: $NEW_OUI_JDK_STRING"
fi

# Function: find files in DOMAIN_HOME
find_files_domain() {
    if [ "$VERBOSE_LIST" = "1" ]; then
        grep -Fnr "$OLD_DOMAIN_JDK_STRING" "$DOMAIN_HOME" --exclude-dir logs --exclude-dir tmp --exclude-dir adr | grep -Ev "\.log|\.out"
    else
        grep -FIlr "$OLD_DOMAIN_JDK_STRING" "$DOMAIN_HOME" --exclude-dir logs --exclude-dir tmp --exclude-dir adr | grep -Ev "\.log|\.out"
    fi
}

# Function: find files in ORACLE_HOME (for report only)
find_files_oracle() {
    if [ "$VERBOSE_LIST" = "1" ]; then
        grep -Fnr "$OLD_OUI_JDK_STRING" "$ORACLE_HOME" --exclude-dir .patch_storage --exclude-dir logs --exclude-dir tmp | grep -Ev "\.log|\.out"
    else
        grep -FIlr "$OLD_OUI_JDK_STRING" "$ORACLE_HOME" --exclude-dir .patch_storage --exclude-dir logs --exclude-dir tmp | grep -Ev "\.log|\.out"
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
    file_list_domain=$(find_files_domain)
    if [ $LIST_ONLY -eq 1 ]; then
        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "List-only+verbose mode: listing files and matching lines containing OLD_DOMAIN_JDK_STRING ('$OLD_DOMAIN_JDK_STRING') in DOMAIN_HOME"
        else
            echo "List-only mode: listing files containing OLD_DOMAIN_JDK_STRING ('$OLD_DOMAIN_JDK_STRING') in DOMAIN_HOME"
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
    if [ $LIST_ONLY -eq 1 ]; then
        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "List-only+verbose mode: listing files and matching lines containing OLD_OUI_JDK_STRING ('$OLD_OUI_JDK_STRING') in ORACLE_HOME"
        else
            echo "List-only mode: listing files containing OLD_OUI_JDK_STRING ('$OLD_OUI_JDK_STRING') in ORACLE_HOME"
        fi
        echo "-----------------------------------------------------------------------"
        file_list_oracle=$(find_files_oracle)
        if [ -z "$file_list_oracle" ]; then
            echo "No matching files found."
        else
            echo "$file_list_oracle"
        fi
        echo "-----------------------------------------------------------------------"
        exit 0
    fi

    # Interactive confirmation before backup and update
    local OUI_ACK
    read -t 10 -p "Backup and update OUI JAVA_HOME? ([y]/n): " OUI_ACK </dev/tty
    : ${OUI_ACK:=y}

    if [ "$OUI_ACK" = "y" ] || [ "$OUI_ACK" = "Y" ]; then
        echo "Backing up current JAVA_HOME to OLD_JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name OLD_JAVA_HOME -value "$OLD_OUI_JDK_STRING"
        echo "Updating JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name JAVA_HOME -value "$NEW_OUI_JDK_STRING"
        echo "OUI JAVA_HOME updated."
    else
        echo "OUI JAVA_HOME update skipped."
    fi
fi
