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
# Logdog, an e-dog that sniffs through logs on civi1002 & frlog1002 for interesting stuff. Woof!

PATH="/usr/bin:$PATH"
export PATH

### CONSTANTS ###
OUTPUT_DIR="$HOME/logdog/"
FILENAME_SEARCH_LIMIT=50
YELLOW="\e[93m"
WHITE="\e[39m"
BOLDB="\e[1m"
BOLDE="\e[0m"
GREP="/bin/grep"
ZGREP="/bin/zgrep"
BZGREP="/bin/bzgrep"

### HOSTS ###
CIVIHOST="civi1002"
FRLOGHOST="frlog1002"

trap ctrl_c INT
function ctrl_c() {
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
  echo -e "\nSyntax: logdog [options] query\n"
  echo -e "Options:"
  echo -e "  -d YYYYMMDD      Add a custom date filter when searching (defaults to yesterday's date)"
  echo -e "  -o folder_name   Write file hits to a custom folder name (defaults to query as folder name)"
  echo -e "  -i               Display the directories on the host it will search in"
  echo -e "  -f, --file       Search for filenames instead of file contents"
  echo -e "  -h               Print this help"
  echo -e "\nFlags:"
  echo -e "  --first          Limit results to the first hit for each file scanned"
  echo -e "\nExamples:"
  echo -e "  logdog -f donations_queue_consume"
  echo -e "  logdog 'order_id_12345'"
  exit 0
}

### ARGUMENT PARSING ###
FILENAME_SEARCH="false"
SINGLE_RESULT="false"
INFO_FLAG="false"

# Handle long options
for arg in "$@"; do
  case "$arg" in
    --first)
      SINGLE_RESULT="true"
      shift
      ;;
    --file)
      FILENAME_SEARCH="true"
      shift
      ;;
    *)
      ;;
  esac
done

# Handle short options
while getopts ":fid:o:h" opt; do
  case ${opt} in
    f)
      FILENAME_SEARCH="true"
      ;;
    d)
      DATE="$OPTARG"
      ;;
    i)
      INFO_FLAG="true"
      ;;
    o)
      FOLDERNAME="$OPTARG"
      ;;
    h)
      display_help
      ;;
    \?)
      echo "Error: Invalid option -$OPTARG"
      exit 1
      ;;
    :)
      echo "Error: Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

# Output folder setup
if [[ -z "$FOLDERNAME" ]]; then
  FOLDERNAME=$(echo "$QUERY" | sed 's/ *$//g; s/ /_/g; s/\//__/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
else
  FOLDERNAME=$(echo "$FOLDERNAME" | sed 's/ *$//g; s/ /_/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
fi

### Date Stuff ###
TODAY=$(date +"%Y%m%d")
PREVIOUSDAY=$(date +"%Y%m%d" -d "yesterday")
if [[ -z "$DATE" ]]; then
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$PREVIOUSDAY
else
  # Treat partial date as wildcard
  if [[ ${#DATE} -lt 8 ]]; then
    DATE="$DATE*"
  fi
  CURRENT_DATE=$TODAY
  ARCHIVE_DATE=$DATE
fi

### PATH AND PATTERN CONFIGURATION ###
function configure_paths() {
  if [[ "$HOSTNAME" == "$CIVIHOST" ]]; then
    configure_civi_paths
  elif [[ "$HOSTNAME" == "$FRLOGHOST" ]]; then
    configure_frlog_paths
  else
    echo "Running logdog on an invalid host!"
    exit 1
  fi
}

function configure_civi_paths() {
  # Common paths for civi
  CIVI_CURRENT_PROCESS_CONTROL_PATH="/var/log/process-control/"
  CIVI_CURRENTISH_PROCESS_CONTROL_PATH="/srv/archive/civi1002/process-control/$ARCHIVE_DATE/"
  CIVI_CONFIG_AND_LOG_PATH="/srv/org.wikimedia.civicrm-files/civicrm/ConfigAndLog/"

  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    # Paths for filename search
    PATHS=(
      "$CIVI_CURRENT_PROCESS_CONTROL_PATH"
      "/srv/archive/civi1002/process-control/"
      "$CIVI_CONFIG_AND_LOG_PATH"
    )
    PATTERNS=("*" "*" "*")
  else
    # Paths for content search
    PATHS=(
      "$CIVI_CURRENT_PROCESS_CONTROL_PATH"
      "$CIVI_CURRENTISH_PROCESS_CONTROL_PATH"
      "$CIVI_CONFIG_AND_LOG_PATH"
    )
    PATTERNS=("*.log" "*.bz2" "CiviCRM*.log*")
    GREPPERS=("$GREP" "$BZGREP" "$GREP")
  fi
}

function configure_frlog_paths() {
  # Common paths for frlog
  FRLOG_CURRENT_PATH="/var/log/remote/"
  FRLOG_ARCHIVE_PATH_TODAY="/srv/archive/frlog1002/logs"
  FRLOG_ARCHIVE_PATH_OTHER="/srv/archive/frlog1002/logs"
  FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH="/srv/archive/civi/process-control/$ARCHIVE_DATE"

  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    # Paths for filename search
    PATHS=(
      "$FRLOG_CURRENT_PATH"
      "/srv/archive/frlog1002/logs"
      "/srv/archive/civi/process-control/"
    )
    PATTERNS=("*" "*" "*")
  else
    # Paths for content search
    PATHS=(
      "$FRLOG_CURRENT_PATH"
      "$FRLOG_ARCHIVE_PATH_TODAY"
      "$FRLOG_ARCHIVE_PATH_OTHER"
      "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH"
    )
    PATTERNS=(
      "*"
      "*-$CURRENT_DATE.gz"
      "*-$ARCHIVE_DATE.gz"
      "*.bz2"
    )
    GREPPERS=("$GREP" "$ZGREP" "$ZGREP" "$BZGREP")
  fi
}

configure_paths

if [[ "$INFO_FLAG" == "true" ]]; then
  display_directories
  exit 0
fi

if [[ -z "$1" ]]; then
  echo "Enter a search query to fetch!"
  exit 1
else
  QUERY="$1"
fi

### SEARCH FUNCTIONS ###
function filename_search() {
  local file_path=$1
  local query=$2

  echo -e "$YELLOW ##################################################################"
  echo -e "\e[93m# Searching for files in $file_path matching '*$query*'"

  local total_matching_files
  total_matching_files=$(/usr/bin/find "$file_path" -type f -name "*$query*" 2>/dev/null | wc -l)

  local matching_files
  matching_files=$(/usr/bin/find "$file_path" -type f -name "*$query*" 2>/dev/null | head -n "$FILENAME_SEARCH_LIMIT")

  if [[ -n "$matching_files" ]]; then
    echo -e "$YELLOW# Found $total_matching_files files (limited to $FILENAME_SEARCH_LIMIT):"
    echo "$matching_files"
  else
    echo -e "$YELLOW# No files matching '*$query*' found in $file_path"
  fi
  echo -e "$YELLOW------------------------------------------------------------------"
  echo -e "$WHITE"
}

function content_search() {
  local file_path=$1
  local filename_pattern=$2
  local grepper=$3
  local query=$4

  echo -e "$YELLOW ##################################################################"
  echo -e "\e[93m# Searching in $file_path for files matching '$filename_pattern' containing '$query'"

  local files
  files=$(/usr/bin/find "$file_path" -name "$filename_pattern" -type f 2>/dev/null)

  local total_count=0
  for file in $files; do
    local result
    if [[ "$SINGLE_RESULT" == "true" ]]; then
      result=$("$grepper" -i -m 1 "$query" "$file")
    else
      result=$("$grepper" -i "$query" "$file")
    fi

    if [[ $? -eq 0 && -n "$result" ]]; then
      local count
      count=$(echo "$result" | wc -l)
      echo -e "\n$YELLOW# $file hits: $count"
      /bin/mkdir -p "$OUTPUT_FOLDER"
      echo "$result" >"$OUTPUT_FOLDER""${file##*/}.txt"
      echo -e "$YELLOW# Results written to $OUTPUT_FOLDER${file##*/}.txt"
      echo -e "$WHITE$(echo "$result" | "$GREP" -i --color=always "$query")"
      total_count=$((total_count + count))
    fi
  done
  echo -e "\n$YELLOW# Total hits in $file_path: $total_count"
  echo -e "$YELLOW------------------------------------------------------------------"
  echo -e "$WHITE"
}

### MAIN EXECUTION ###
for index in "${!PATHS[@]}"; do
  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    filename_search "${PATHS[index]}" "$QUERY"
  else
    content_search "${PATHS[index]}" "${PATTERNS[index]}" "${GREPPERS[index]}" "$QUERY"
  fi
done
