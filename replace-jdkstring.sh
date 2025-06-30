#!/bin/bash
# Searches and replaces JDK location strings among files in $DOMAIN_HOME.
# Edit $OLD_JDK_STRING and $NEW_JDK_STRING to fit.
# !! For JDK 11.0.19 or later, JAVA_HOME became /usr/lib/jvm/jdk-11-x64
#    without update number! So, this treatment is unnecessary.
# ! Mind this script won't work if interpreter is "sh", not bash !
# Version 1.4

### Edit here:
OLD_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_411-oracle-x64
NEW_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_451-oracle-x64

MYBASENAME=$(basename "$0")
DRY_RUN=0
AUTO_YES_ALL=0

show_help() {
   cat <<EOM
Usage: $MYBASENAME [-d] [-h]
  -d: Dry-run mode. List matching files and exit without modification.
  -h: Show this help.
EOM
}

while getopts "dh" opt; do
  case $opt in
    d)
      DRY_RUN=1
      ;;
    h|*)
      show_help
      exit 1
      ;;
  esac
done

if [ -z "$DOMAIN_HOME" ]; then
    echo "Set DOMAIN_HOME environment variable first."
    exit 1
fi

# Escape the old/new JDK strings for Perl regex and replacement
escape_perl_regex() {
    printf '%s' "$1" | perl -pe 's/([\[\]\(\)\{\}\^\$\.\|\?\*\+\\\/])/\\$1/g'
}
escape_perl_replace() {
    printf '%s' "$1" | perl -pe 's/([\\\$\@])/\\$1/g'
}

PERL_OLD=$(escape_perl_regex "$OLD_JDK_STRING")
PERL_NEW=$(escape_perl_replace "$NEW_JDK_STRING")

echo "OLD_JDK_STRING: $OLD_JDK_STRING"
echo "NEW_JDK_STRING: $NEW_JDK_STRING"

# Find files
file_list=$(grep -FIlr "$OLD_JDK_STRING" "$DOMAIN_HOME" --exclude-dir logs --exclude-dir tmp --exclude-dir adr | grep -Ev "\.log|\.out")

if [ $DRY_RUN -eq 1 ]; then
    echo "Dry-run mode: listing files containing OLD_JDK_STRING ('$OLD_JDK_STRING')"
    echo "-----------------------------------------------------------------------"
    if [ -z "$file_list" ]; then
        echo "No matching files found."
    else
        echo "$file_list"
    fi
    echo "-----------------------------------------------------------------------"
    exit 0
fi

replace_string() {
    # If AUTO_YES_ALL is set, always proceed
    if [ $AUTO_YES_ALL -eq 1 ]; then
        echo "processing '$1'"
        perl -pi -e "s%$PERL_OLD%$PERL_NEW%g;" "$1"
        return
    fi

    local ACK
    echo "string found in '$1'"
    read -t 10 -p "Do you want me to proceed? ([y]/n/a(=all)): " ACK </dev/tty
    : ${ACK:=y}

    if [ "$ACK" = "y" -o "$ACK" = "Y" ]; then
        echo -e "processing '$1'\n"
        perl -pi -e "s%$PERL_OLD%$PERL_NEW%g;" "$1"
    elif [ "$ACK" = "a" -o "$ACK" = "A" ]; then
        echo "processing '$1'"
        echo -e "Continue processing in non-interactive mode.\n"
        AUTO_YES_ALL=1
        perl -pi -e "s%$PERL_OLD%$PERL_NEW%g;" "$1"
    else
        echo -e "skipped\n"
    fi
}

while read -r FNAME; do
    [ -z "$FNAME" ] && continue
    if [ ! -f "$FNAME" ]; then
        echo "No such file '$FNAME'"
        continue
    fi

    replace_string "$FNAME"

done <<< "$file_list"
