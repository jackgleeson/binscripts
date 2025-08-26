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

START_TIME=$(date +%s)

PATH="/usr/bin:$PATH"
export PATH

### CONSTANTS ###
OUTPUT_DIR="$HOME/logdog/"
FILENAME_SEARCH_LIMIT=50
YELLOW="\e[93m"
RESET="\e[0m"
BOLDB="\e[1m"
BOLDE="\e[0m"
GREP="/bin/grep"
ZGREP="/bin/zgrep"
BZGREP="/bin/bzgrep"

### HOSTS ###
CIVIHOST="civi1002"
FRLOGHOST="frlog1002"

# Added to reset terminal on script exit
trap 'tput sgr0' EXIT
trap ctrl_c INT

function ctrl_c() {
  tput sgr0
  exit
}

function display_help() {
  echo -e "${RESET}"
  echo -e "${BOLDB}Logdog helps you find stuff in the logs!${BOLDE}"
  echo -e "\nSyntax:"
  echo -e "  logdog [options] query"
  echo -e "  logdog -f filename"
  echo -e "  logdog -f filename [filtered_query]"
  echo -e "\nOptions:"
  echo -e "  -d YYYYMMDD      Add a custom date filter when searching (defaults to yesterday's date)"
  echo -e "  -o folder_name   Write file hits to a custom folder name (defaults to query as folder name)"
  echo -e "  -i               Display the directories on the host it will search in"
  echo -e "  -f, --file       Search for filenames instead of file contents. If a second argument is provided, it is used as a filtered query within the matched files."
  echo -e "  -h               Print this help"
  echo -e "\nFlags:"
  echo -e "  --first          Limit results to the first hit for each file scanned"
  echo -e "\nExamples:"
  echo -e "  logdog order_id_12345"
  echo -e "  logdog -f payments-paypal"
  echo -e "  logdog -f payments-paypal-202411 paypal_order_id_sometime_in_november"
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

if [[ "$FILENAME_SEARCH" == "true" ]]; then
  if [[ $# -eq 0 && "$INFO_FLAG" != "true" ]]; then
    echo "Enter a filename query to search!"
    exit 1
  elif [[ $# -eq 1 ]]; then
    QUERY="$1"
  else
    QUERY="$1"
    CONTENT_QUERY="$2"
  fi
else
  if [[ $# -eq 0 && "$INFO_FLAG" != "true" ]]; then
    echo "Enter a search query to fetch!"
    exit 1
  else
    QUERY="$1"
  fi
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

function configure_civi_paths() {
  # Common paths for civi
  CIVI_LOG_PATH="/srv/org.wikimedia.civicrm/private/log"
  CIVI_CURRENT_PROCESS_CONTROL_PATH="/var/log/process-control"
  CIVI_CURRENTISH_PROCESS_CONTROL_PATH="/srv/archive/civi1002/process-control/$ARCHIVE_DATE"
  FRLOG_ARCHIVE_PATH="/srv/archive/frlog/logs"


  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    # Paths for filename search
    PATHS=(
      "$CIVI_LOG_PATH"
      "$CIVI_CURRENT_PROCESS_CONTROL_PATH"
      "/srv/archive/civi1002/process-control/"
      "$FRLOG_ARCHIVE_PATH"
    )
    PATTERNS=("*" "*" "*" "*")
  else
    if [[ -z "$DATE" ]]; then
      # No date specified; search current logs and today's archives
      PATHS=(
        "$CIVI_LOG_PATH"
        "$CIVI_CURRENT_PROCESS_CONTROL_PATH"
        "$CIVI_CURRENTISH_PROCESS_CONTROL_PATH"
        "$FRLOG_ARCHIVE_PATH"
      )
      PATTERNS=(
        "CiviCRM*.log*"
        "*.log"
        "*.bz2"
        "*-$CURRENT_DATE.gz"
      )
      GREPPERS=(
        "$GREP"
        "$BZGREP"
        "$GREP"
        "$ZGREP"
      )
    else
      # Date specified; search only archives matching the date
      PATHS=(
        "$CIVI_LOG_PATH"
        "$CIVI_CURRENTISH_PROCESS_CONTROL_PATH"
        "$FRLOG_ARCHIVE_PATH"
      )
      PATTERNS=(
        "CiviCRM*.log*"
        "*.bz2"
        "*-$CURRENT_DATE.gz"
      )
      GREPPERS=(
        "$BZGREP"
        "$GREP"
        "$ZGREP"
      )
    fi
  fi
}

function configure_frlog_paths() {
  # Common paths for frlog
  FRLOG_CURRENT_PATH="/var/log/remote"
  FRLOG_ARCHIVE_PATH="/srv/archive/frlog1002/logs"
  FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH="/srv/archive/civi/process-control/$ARCHIVE_DATE"

  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    # Paths for filename search
    PATHS=(
      "$FRLOG_CURRENT_PATH"
      "$FRLOG_ARCHIVE_PATH"
      "/srv/archive/civi/process-control/"
    )
    PATTERNS=("*" "*" "*")
  else
    if [[ -z "$DATE" ]]; then
      # No date specified; search current logs and today's archives
      PATHS=(
        "$FRLOG_CURRENT_PATH"
        "$FRLOG_ARCHIVE_PATH"
        "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH"
      )
      PATTERNS=(
        "*"
        "*-$CURRENT_DATE.gz"
        "*.bz2"
      )
      GREPPERS=(
        "$GREP"
        "$ZGREP"
        "$BZGREP"
      )
    else
      # Date specified; search only archives matching the date
      PATHS=(
        "$FRLOG_ARCHIVE_PATH"
        "$FRLOG_CIVI_PROCESS_CONTROL_ARCHIVE_PATH"
      )
      PATTERNS=(
        "*-$ARCHIVE_DATE.gz"
        "*.bz2"
      )
      GREPPERS=(
        "$ZGREP"
        "$BZGREP"
      )
    fi
  fi
}

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

function display_directories() {
  echo "Directories that will be searched on $HOSTNAME:"
  echo
  for path in "${PATHS[@]}"; do
    echo "- $path"
  done
}

configure_paths

if [[ "$INFO_FLAG" == "true" ]]; then
  display_directories
  exit 0
fi

if [[ -z "$FOLDERNAME" ]]; then
  FOLDERNAME=$(echo "$QUERY" | sed 's/ *$//g; s/ /_/g; s/\//__/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
else
  FOLDERNAME=$(echo "$FOLDERNAME" | sed 's/ *$//g; s/ /_/g')
  OUTPUT_FOLDER="$OUTPUT_DIR$FOLDERNAME/"
fi

# Progress counter function
# Usage: show_progress <current> <total> [message]
function show_progress() {
  local current=$1
  local total=$2
  local message=${3:-"Processing"}

  if [[ $total -eq 0 ]]; then
    echo -ne "\r${YELLOW}# $message: No items to process${RESET}"
    return 0
  fi

  local percent=$((current * 100 / total))
  echo -ne "\r${YELLOW}# $message: ${percent}% ($current/$total)${RESET}"

  # Add newline when complete
  if [[ $current -eq $total ]]; then
    echo
  fi
}

function filename_search() {
  local file_path=$1
  local query=$2

  echo -e "$YELLOW ##################################################################"
  echo -e "${YELLOW}# Searching for files in $file_path matching '*$query*'${RESET}"

  local matching_files=()
  local matching_files_list

  matching_files_list=$(ls -1 "$file_path" 2>/dev/null | grep "$query" | head -n "$FILENAME_SEARCH_LIMIT")
  local total_matching_files
  total_matching_files=$(ls -1 "$file_path" 2>/dev/null | grep "$query" | wc -l)

  if [[ -n "$matching_files_list" ]]; then
    echo -e "${YELLOW}# Found $total_matching_files files (limited to $FILENAME_SEARCH_LIMIT):${RESET}"
    echo "$matching_files_list"

    # Build the array of full paths
    while IFS= read -r filename; do
      matching_files+=("$file_path/${filename}")
    done <<< "$matching_files_list"
  else
    echo -e "${YELLOW}# No files matching '*$query*' found in $file_path${RESET}"
    return 0
  fi
  echo -e "${YELLOW}------------------------------------------------------------------${RESET}"

  # If an additional content search query is provided, search within the matched files
  if [[ -n "$CONTENT_QUERY" ]]; then
    echo -e "${YELLOW}# Searching within matched files for query matching '$CONTENT_QUERY'${RESET}"
    local total_count=0
    for file in "${matching_files[@]}"; do
      local result
      # Choose the appropriate grepper based on file extension
      if [[ "$file" == *.gz ]]; then
        GREPPER="$ZGREP"
      elif [[ "$file" == *.bz2 ]]; then
        GREPPER="$BZGREP"
      else
        GREPPER="$GREP"
      fi

      if [[ "$SINGLE_RESULT" == "true" ]]; then
        result=$("$GREPPER" -i -m 1 "$CONTENT_QUERY" "$file")
      else
        result=$("$GREPPER" -i "$CONTENT_QUERY" "$file")
      fi

      if [[ $? -eq 0 && -n "$result" ]]; then
        local count
        count=$(echo "$result" | wc -l)
        echo -e "\n${YELLOW}# $file hits: $count${RESET}"
        /bin/mkdir -p "$OUTPUT_FOLDER"
        echo "$result" >"$OUTPUT_FOLDER""${file##*/}.txt"
        echo -e "${YELLOW}# Results written to $OUTPUT_FOLDER${file##*/}.txt${RESET}"
        echo -e "${RESET}$(echo "$result" | "$GREP" -i --color=always "$CONTENT_QUERY")"
        total_count=$((total_count + count))
      fi
    done
    echo -e "\n${YELLOW}# Total hits in matched files: $total_count${RESET}"
    echo -e "${YELLOW}------------------------------------------------------------------${RESET}"
  fi
}

function content_search() {
  local file_path=$1
  local filename_pattern=$2
  local grepper=$3
  local query=$4

  echo -e "$YELLOW ##################################################################"
  echo -e "${YELLOW}# Searching in $file_path for files matching '$filename_pattern' containing '$query'${RESET}"

  local files
  files=$(cd "$file_path" && find . -name "$filename_pattern" -type f 2>/dev/null | sed "s|^\./|$file_path/|")

  local file_count=0
  local total_files=$(cd "$file_path" && find . -name "$filename_pattern" -type f 2>/dev/null | wc -l)
  local total_count=0

  if [[ $total_files -eq 0 ]]; then
    echo -e "${YELLOW}# No files found matching '$filename_pattern' in $file_path${RESET}"
    return 0
  fi

  for file in $files; do
    file_count=$((file_count + 1))
    show_progress $file_count $total_files "Scanning files"
    local result
    if [[ "$SINGLE_RESULT" == "true" ]]; then
      result=$("$grepper" -i -m 1 "$query" "$file")
    else
      result=$("$grepper" -i "$query" "$file")
    fi

    if [[ $? -eq 0 && -n "$result" ]]; then
      local count
      count=$(echo "$result" | wc -l)
      echo -e "\n${YELLOW}# $file hits: $count${RESET}"
      /bin/mkdir -p "$OUTPUT_FOLDER"
      echo "$result" >"$OUTPUT_FOLDER""${file##*/}.txt"
      echo -e "${YELLOW}# Results written to $OUTPUT_FOLDER${file##*/}.txt${RESET}"
      echo -e "${RESET}$(echo "$result" | "$GREP" -i --color=always "$query")"
      total_count=$((total_count + count))
    fi
  done
  echo -e "\n${YELLOW}# Total hits in $file_path: $total_count${RESET}"
  echo -e "${YELLOW}------------------------------------------------------------------${RESET}"
}

### MAIN ###
for index in "${!PATHS[@]}"; do
  if [[ "$FILENAME_SEARCH" == "true" ]]; then
    filename_search "${PATHS[index]}" "$QUERY"
  else
    content_search "${PATHS[index]}" "${PATTERNS[index]}" "${GREPPERS[index]}" "$QUERY"
  fi
done

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
echo -e "\n$YELLOW# Total execution time: ${ELAPSED_TIME} seconds"
echo -e "$RESET"
