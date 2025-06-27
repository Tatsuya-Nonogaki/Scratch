#!/bin/bash
# Searches and replaces JDK location strings among files in $DOMAIN_HOME.
# Edit $OLD_JDK_STRING and $NEW_JDK_STRING to fit.
# !! For JDK 11.0.19 or later, JAVA_HOME became /usr/lib/jvm/jdk-11-x64
#    without update number! So, this treatment is unnecessary.
# ! Mind this script won't work if interpreter is "sh", not bash !

### Edit here:
OLD_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_411-oracle-x64
NEW_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_451-oracle-x64

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

replace_string() {
    local ACK
    echo "string found in '$1'"
    read -p "Do you want me to proceed? ([y]/n): " -t 10 ACK
    : ${ACK:=y}

    if [ "$ACK" = "y" ] || [ "$ACK" = "Y" ]; then
        echo -e "processing\n"
        perl -pi -e "s/$PERL_OLD/$PERL_NEW/g;" "$1"
    else
        echo -e "skipped\n"
    fi
}

while read -u 9 FNAME; do
    if [ ! -f "$FNAME" ]; then
        echo "No such file '$FNAME'"
        continue
    fi

    replace_string "$FNAME"

done 9< <(grep -FIlr "$OLD_JDK_STRING" "$DOMAIN_HOME" --exclude-dir logs --exclude-dir tmp --exclude-dir adr | grep -Ev "\.log|\.out")
