#!/usr/bin/env bash

#             .--.             .---.
#            /:.  '.         .' ..  '._.---.
#           /:::-.  \.-"""-;` .-:::.     .::\
#          /::'|  `\/  _ _  \'   `\:'   ::::|
#      __.'    |   /  (o|o)  \     `'.   ':/
#     /    .:. /   |   ___   |        '---'
#    |    ::::'   /:  (._.) .:\
#    \    .='    |:'        :::|
#     `""`       \     .-.   ':/
#                 '---`|I|`---'
#                      '-'
# Logdog, an e-dog that sniffs through logs for interesting stuff. Woof!
#
# ####
# TODO:
# - make logdog work with bzgrep. (done)
# - pull out psp if available and print to summary
# - maybe as a summary block to output.
# -- other useful consistent log data could also be displayed in some type of summary block
# - read in log paths, patterns and greps from cfg ile to make it easier to swap out cfg
# ####
PATH="/usr/bin:$PATH"
export PATH
### CONSTANTS ###
OUTPUT_DIR="$HOME/logdog/"
YELLOW="\e[93m"
WHITE="\e[39m"
GREP="/bin/grep"
ZGREP="/bin/zgrep"
BZGREP="/bin/bzgrep"
CAT="/bin/cat"
ZCAT="/bin/zcat"
BZCAT="/bin/bzcat"

### HOSTS ###
CIVI1001="civi1001"
FRLOG1001="frlog1001"

# DEBUG HOST
if [[ $HOSTNAME == 'mwv' ]]; then
  DEBUG=true
else
  DEBUG=false
fi

function display_help() {
  echo -e "$WHITE"
  echo "Logdog helps you find stuff in the logs!"
  echo
  echo "Syntax: logdog [-d|o|h] query"
  echo "options:"
  echo "-d 20201201   add a custom YYYYMMDD date filter when searching (defaults to yesterday's date)"
  echo "-o output_folder_name   dump log file hits to a custom folder name (defaults to query as folder name)"
  echo "-h    Print this Help."
  exit 0
}

### ARGUMENTS ###
while getopts "d:o:h" opt; do
  case ${opt} in
  d) DATE="$OPTARG" ;;
  o) FOLDERNAME="$OPTARG" ;;
  h) display_help ;;
  \?)
    echo "Error: Invalid option"
    exit
    ;;
  esac
done
shift $((OPTIND - 1))

### DEFAULT CHECKS ###
if [[ -z "$1" ]]; then
  echo "Enter a search query to fetch!"
  exit 1
else
  # the actual search query
  QUERY="$1"
fi

### DATE STUFF ###
TODAY=$(date +"%Y%m%d")
PREVIOUSDAY=$(date +"%Y%m%d" -d "yesterday")
if [[ -z "$DATE" ]]; then
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$PREVIOUSDAY
else
  # if a partial date is supplied treat it as a wildcard
  if [[ ${#DATE} -lt 8 ]]; then
    DATE="*$DATE*"
  fi
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$DATE
fi

if [[ -z "$FOLDERNAME" ]]; then
  FOLDERNAME=$(echo "$QUERY" | /bin/sed 's/ *$//g' | /bin/sed 's/ /_/g' | /bin/sed 's/\//__/g')
  OUTPUT_FOLDER="$OUTPUT_DIR""$FOLDERNAME""/"
else
  FOLDERNAME=$(echo "$FOLDERNAME" | /bin/sed 's/ *$//g' | /bin/sed 's/ /_/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
fi

### FRLOG PATHS, PATTERNS AND GREPPERS ###
FRLOG_CURRENT_PATH="/var/log/remote"
FRLOG_CURRENT_PATTERN="*" # all actual files in dir e.g. fundraising-misc
FRLOG_CURRENT_GREP="$GREP"

FRLOG_ARCHIVE_PATH="/srv/archive/frlog1001/logs"
FRLOG_ARCHIVE_PATTERN="*-$ARCHIVE_DATE.gz" # e.g. payments-20200807.gz
FRLOG_ARCHIVE_GREP="$ZGREP"

# civi process-control logs are archived on frlog1001
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH="/srv/archive/civi/process-control/$ARCHIVE_DATE"
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATTERN="*.bz2" # e.g. 20200805/thank_you_mail_send-20200805-235902.log.civi1001.bz2
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_GREP="$BZGREP"

### CIVI PATHS, PATTERNS AND GREPPERS ###
CIVI_CURRENT_PROCESS_CONTROL_PATH="/var/log/process-control" # job folders e.g. silverpop_daily
CIVI_CURRENT_PROCESS_CONTROL_PATTERN="*-$CURRENT_DATE*.log"  # e.g. silverpop_daily-20200807-154459.log
CIVI_CURRENT_PROCESS_CONTROL_GREP="$GREP"

# this path holds soon-to-be-archived logs (previous day's only)
CIVI_CURRENTISH_PROCESS_CONTROL_PATH="/srv/archive/civi1001/process-control/$PREVIOUSDAY"
CIVI_CURRENTISH_PROCESS_CONTROL_PATTERN="*.bz2" # e.g. 20200805/thank_you_mail_send-20200805-235902.log.civi1001.bz2
CIVI_CURRENTISH_PROCESS_CONTROL_GREP="$BZGREP"

### FUNCS ####
function logdog() {
  local FILE_PATH=$1
  local FILENAME_PATTERN=$2
  local GREPPER=$3
  local QUERY=$4
  local GREPCOLOUR='--color=always'
  FILES=$(/usr/bin/find "$FILE_PATH" -name "$FILENAME_PATTERN" -type f 2>/dev/null)
  echo -e "$YELLOW ##################################################################"
  echo -e "\e[93m# Sniffing $FILE_PATH for files matching '$FILENAME_PATTERN' containing '$QUERY'"
  TOTAL_COUNT=0
  for file in $FILES; do
    RESULT=$("$GREPPER" -i "$QUERY" "$file")
    if [[ $? -eq 0 ]]; then
      COUNT=$(echo "$RESULT" | /usr/bin/wc -l)
      if [[ "$COUNT" -gt 0 ]]; then
        echo -e "\n"
        echo -e "$YELLOW# $file hits: $COUNT"
        /bin/mkdir -p "$OUTPUT_FOLDER"
        echo "$RESULT" >"$OUTPUT_FOLDER""/""${file##*/}"".txt"
        echo -e "$YELLOW# Results written to $OUTPUT_FOLDER${file##*/}.txt"
        echo -e "$WHITE$(echo "$RESULT" | "$GREP" -i "$GREPCOLOUR" "$QUERY")"
        TOTAL_COUNT=$((TOTAL_COUNT + COUNT))
      fi
    fi
  done
  echo -e "\n"
  echo -e "$YELLOW# Total hits in $FILE_PATH: $TOTAL_COUNT"
  echo -e "$YELLOW------------------------------------------------------------------"
  echo -e "$WHITE"
}

### HOST-BASED SELECTIONS ###
if [[ $HOSTNAME == "$CIVI1001" || $DEBUG == true ]]; then
  PATHS=("$CIVI_CURRENT_PROCESS_CONTROL_PATH" "$CIVI_CURRENTISH_PROCESS_CONTROL_PATH")
  PATTERNS=("$CIVI_CURRENT_PROCESS_CONTROL_PATTERN" "$CIVI_CURRENTISH_PROCESS_CONTROL_PATTERN")
  GREPPERS=("$CIVI_CURRENT_PROCESS_CONTROL_GREP" "$CIVI_CURRENTISH_PROCESS_CONTROL_GREP")
elif [[ $HOSTNAME == "$FRLOG1001" ]]; then
  PATHS=("$FRLOG_CURRENT_PATH" "$FRLOG_ARCHIVE_PATH" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH")
  PATTERNS=("$FRLOG_CURRENT_PATTERN" "$FRLOG_ARCHIVE_PATTERN" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATTERN")
  GREPPERS=("$FRLOG_CURRENT_GREP" "$FRLOG_ARCHIVE_GREP" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_GREP")
else
  echo "Running logdog on an invalid host!"
  exit 1
fi

### MAIN ###
for i in "${!PATHS[@]}"; do
  logdog "${PATHS[i]}" "${PATTERNS[i]}" "${GREPPERS[i]}" "$QUERY"
done
