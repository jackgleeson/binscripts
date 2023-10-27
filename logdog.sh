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

# ####
# HOW TO USE (on civi1002 & frlog1002):
: <<'STEPS'

 1) Add script to $HOME/bin dir:
 - cd to $HOME
 - run `mkdir ./bin`
 - run `cat > ./bin/logdog`
 - select and copy the entire contents of this file
 - press Ctrl+Shift+V (to paste to cli)
 - press Ctrl+D (To save)
 - run `chmod +x ./bin/logdog`

 2) Add script to your PATH
 - run `echo 'if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi' >> .profile`
 - run `source .profile`

 3) Run Logdog
 - run `logdog -h`

STEPS
# ####
# TODO:
# - pull out psp if available
# - extend the above and add more as a summary block.
# -- other useful consistent log data such as ct_ids, emails, final status
# - read in log paths, patterns and greps from cfg ile to make it easier to swap out cfg
# ####
PATH="/usr/bin:$PATH"
export PATH
### CONSTANTS ###
OUTPUT_DIR="$HOME/logdog/"
FIRST_MATCH="false"
INFO_FLAG="false"
YELLOW="\e[93m"
WHITE="\e[39m"
BOLDB="\e[1m"
BOLDE="\e[0m"
WHITE="\e[39m"
GREP="/bin/grep"
ZGREP="/bin/zgrep"
BZGREP="/bin/bzgrep"
CAT="/bin/cat"
ZCAT="/bin/zcat"
BZCAT="/bin/bzcat"

### HOSTS ###
CIVIHOST="civi1002"
FRLOGHOST="frlog1002"

trap ctrl_c INT

ctrl_c() {
  tput sgr0
  exit
}

function display_directories() {
  echo "Directories that will be searched on $HOSTNAME:"
  echo
  for path in "${PATHS[@]}"; do
    echo "- $path"
  done
}

function display_help() {
    echo -e "${WHITE}"
    echo -e "${BOLDB}Logdog helps you find stuff in the logs!${BOLDE}"
    echo -e "\nSyntax: logdog [-d|o|i|h] query\n"
    echo -e "Options:"
    echo -e "  -d YYYYMMDD      Add a custom date filter when searching (defaults to yesterday's date)"
    echo -e "  -o folder_name   Write file hits to a custom folder name (defaults to query as folder name)"
    echo -e "  -i               Display the directories on the host it will search in"
    echo -e "  -h               Print this help"
    echo -e "\nFlags:"
    echo -e "  --first          Limit results to the first hit for each file scanned"
    echo -e "\n===============================================\n"
    echo -e "Examples:\n"
    echo -e "  Quick Search:"
    echo -e "      ${BOLDB}logdog order_id_12345${BOLDE}"
    echo -e "      Outputs results to $HOME/logdog/order_id_12345\n"
    echo -e "  Search and write results to a custom output directory:"
    echo -e "      ${BOLDB}logdog -o my_search order_id_12345${BOLDE}"
    echo -e "      Outputs results to $HOME/logdog/my_search\n"
    echo -e "  Search on a specific date:"
    echo -e "      ${BOLDB}logdog -d 20201201 order_id_12345${BOLDE}"
    echo -e "      Outputs results to $HOME/logdog/order_id_12345\n"
    echo -e "  Search across multiple dates:"
    echo -e "      ${BOLDB}logdog -d 202012 order_id_12345${BOLDE}"
    echo -e "      Outputs all results across December 2020 to $HOME/logdog/order_id_12345\n"
    echo -e "      ${BOLDB}logdog -d 2020121[23] order_id_12345${BOLDE}"
    echo -e "      Outputs all results across December 12th and 13th to $HOME/logdog/order_id_12345\n"
    exit 0
}


### ARGUMENTS ###
for arg in "$@"; do
  shift
  case "$arg" in
  "--first") set -- "$@" "-f" ;;
  *) set -- "$@" "$arg" ;;
  esac
done

while getopts "fid:o:h" opt; do
  case ${opt} in
  f) FIRST_MATCH="true" ;;
  d) DATE="$OPTARG" ;;
  i) INFO_FLAG="true" ;;
  o) FOLDERNAME="$OPTARG" ;;
  h) display_help ;;
  \?)
    echo "Error: Invalid option"
    exit
    ;;
  esac
done
shift $((OPTIND - 1))

### DATE STUFF ###
TODAY=$(date +"%Y%m%d")
PREVIOUSDAY=$(date +"%Y%m%d" -d "yesterday")
if [[ -z "$DATE" ]]; then
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$PREVIOUSDAY
else
  # if a partial date is supplied treat it as a wildcard
  if [[ ${#DATE} -lt 8 ]]; then
    DATE="$DATE*"
  fi
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$DATE
fi

### FRLOG PATHS, PATTERNS AND GREPPERS ###
FRLOG_CURRENT_PATH="/var/log/remote/"
FRLOG_CURRENT_PATTERN="*" # all actual files in dir e.g. fundraising-misc
FRLOG_CURRENT_GREP="$GREP"

FRLOG_ARCHIVE_PATH_TODAY="/srv/archive/frlog1002/logs"
FRLOG_ARCHIVE_PATTERN_TODAY="*-$CURRENT_DATE.gz" # e.g. payments-20200807.gz
FRLOG_ARCHIVE_GREP_TODAY="$ZGREP"

FRLOG_ARCHIVE_PATH_OTHER="/srv/archive/frlog1002/logs"
FRLOG_ARCHIVE_PATTERN_OTHER="*-$ARCHIVE_DATE.gz" # e.g. payments-20200807.gz
FRLOG_ARCHIVE_GREP_OTHER="$ZGREP"

FRLOG_1001_ARCHIVE_PATH="/srv/archive/frlog1001/logs"
FRLOG_1001_ARCHIVE_PATTERN="*-$ARCHIVE_DATE.gz" # e.g. payments-20200807.gz
FRLOG_1001_ARCHIVE_GREP="$ZGREP"

# civi process-control logs are archived on frlog1002
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH="/srv/archive/civi/process-control/$ARCHIVE_DATE"
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATTERN="*.bz2" # e.g. 20200805/thank_you_mail_send-20200805-235902.log.civi1002.bz2
FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_GREP="$BZGREP"

### CIVI PATHS, PATTERNS AND GREPPERS ###
CIVI_CURRENT_PROCESS_CONTROL_PATH="/var/log/process-control/" # job folders e.g. silverpop_daily
CIVI_CURRENT_PROCESS_CONTROL_PATTERN="*-$CURRENT_DATE*.log"   # e.g. silverpop_daily-20200807-154459.log
CIVI_CURRENT_PROCESS_CONTROL_GREP="$GREP"

# this path holds soon-to-be-archived logs
CIVI_CURRENTISH_PROCESS_CONTROL_PATH="/srv/archive/civi1002/process-control/$ARCHIVE_DATE/"
CIVI_CURRENTISH_PROCESS_CONTROL_PATTERN="*.bz2" # e.g. 20200805/thank_you_mail_send-20200805-235902.log.civi1002.bz2
CIVI_CURRENTISH_PROCESS_CONTROL_GREP="$BZGREP"

# CiviCRM ConfigAndLog logs
CIVI_CONFIG_AND_LOG_PATH="/srv/org.wikimedia.civicrm-files/civicrm/ConfigAndLog/"
CIVI_CONFIG_AND_LOG_PATTERN="CiviCRM*.log*" # e.g. CiviCRM.7a880382d2e1d80611365ce1.log.202009010000
CIVI_CONFIG_AND_LOG_GREP="$GREP"

### HOST-BASED SELECTIONS ###
if [[ $HOSTNAME == "$CIVIHOST" ]]; then
  if [[ -z "$DATE" ]]; then
    PATHS=("$CIVI_CURRENT_PROCESS_CONTROL_PATH" "$CIVI_CURRENTISH_PROCESS_CONTROL_PATH" "$CIVI_CONFIG_AND_LOG_PATH")
    PATTERNS=("$CIVI_CURRENT_PROCESS_CONTROL_PATTERN" "$CIVI_CURRENTISH_PROCESS_CONTROL_PATTERN" "$CIVI_CONFIG_AND_LOG_PATTERN")
    GREPPERS=("$CIVI_CURRENT_PROCESS_CONTROL_GREP" "$CIVI_CURRENTISH_PROCESS_CONTROL_GREP" "$CIVI_CONFIG_AND_LOG_GREP")
  else
    PATHS=("$CIVI_CURRENTISH_PROCESS_CONTROL_PATH")
    PATTERNS=("$CIVI_CURRENTISH_PROCESS_CONTROL_PATTERN")
    GREPPERS=("$CIVI_CURRENTISH_PROCESS_CONTROL_GREP")
  fi
elif [[ $HOSTNAME == "$FRLOGHOST" ]]; then
  if [[ -z "$DATE" ]]; then
    PATHS=("$FRLOG_CURRENT_PATH" "$FRLOG_ARCHIVE_PATH_TODAY" "$FRLOG_ARCHIVE_PATH_OTHER" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH")
    PATTERNS=("$FRLOG_CURRENT_PATTERN" "$FRLOG_ARCHIVE_PATTERN_TODAY" "$FRLOG_ARCHIVE_PATTERN_OTHER" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATTERN")
    GREPPERS=("$FRLOG_CURRENT_GREP" "$FRLOG_ARCHIVE_GREP_TODAY" "$FRLOG_ARCHIVE_GREP_OTHER" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_GREP")
  else
    PATHS=("$FRLOG_ARCHIVE_PATH_OTHER" "$FRLOG_1001_ARCHIVE_PATH" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH")
    PATTERNS=("$FRLOG_ARCHIVE_PATTERN_OTHER" "$FRLOG_1001_ARCHIVE_PATTERN" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATTERN")
    GREPPERS=("$FRLOG_ARCHIVE_GREP_OTHER" "$FRLOG_1001_ARCHIVE_GREP" "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_GREP")
  fi
else
  echo "Running logdog on an invalid host!"
  exit 1
fi

if [[ "$INFO_FLAG" == "true" ]]; then
  display_directories
  exit 0
fi

### DEFAULT CHECKS ###
if [[ -z "$1" ]]; then
  echo "Enter a search query to fetch!"
  exit 1
else
  # the actual search query
  QUERY="$1"
fi

if [[ -z "$FOLDERNAME" ]]; then
  FOLDERNAME=$(echo "$QUERY" | /bin/sed 's/ *$//g' | /bin/sed 's/ /_/g' | /bin/sed 's/\//__/g')
  OUTPUT_FOLDER="$OUTPUT_DIR""$FOLDERNAME""/"
else
  FOLDERNAME=$(echo "$FOLDERNAME" | /bin/sed 's/ *$//g' | /bin/sed 's/ /_/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
fi

### FUNC ####
function logdog() {
  local FILE_PATH=$1
  local FILENAME_PATTERN=$2
  local GREPPER=$3
  local QUERY=$4
  local GREPCOLOUR='--color=always'
  FILES=$(/usr/bin/find $FILE_PATH -name "$FILENAME_PATTERN" -type f 2>/dev/null)
  echo -e "$YELLOW ##################################################################"
  echo -e "\e[93m# Sniffing $FILE_PATH for files matching '$FILENAME_PATTERN' containing '$QUERY'"
  TOTAL_COUNT=0
  for file in $FILES; do
    if [[ "$FIRST_MATCH" == "true" ]]; then
        RESULT=$("$GREPPER" -i -m 1 "$QUERY" "$file")
    else
        RESULT=$("$GREPPER" -i "$QUERY" "$file")
    fi
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

### MAIN ###
for i in "${!PATHS[@]}"; do
  logdog "${PATHS[i]}" "${PATTERNS[i]}" "${GREPPERS[i]}" "$QUERY"
done
