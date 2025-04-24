#!/bin/bash

set -euo pipefail

SQL_FILE=""
DRY_RUN=false
MODE=""
fixes=0

# ===== Colors =====
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# ===== Print Help =====
print_help() {
  echo "${CYAN}Usage:${RESET} $0 path/to/file.sql [--dry-run]"
  echo "  --dry-run    Preview changes without modifying the file"
  exit 0
}

# ===== Parse Arguments =====
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    -h|--help) print_help ;;
    *) [[ -z "$SQL_FILE" && "$arg" != -* ]] && SQL_FILE="$arg" ;;
  esac
done

# ===== Validate SQL File =====
if [[ -z "$SQL_FILE" ]]; then
  echo "${RED}❌ No SQL file provided.${RESET}"
  print_help
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "${RED}❌ File not found: $SQL_FILE${RESET}"
  exit 1
fi

if ! file "$SQL_FILE" | grep -q "ASCII text"; then
  echo "${YELLOW}⚠️ Warning: File may not be plain text. Please check encoding.${RESET}"
fi

# ===== Backup File =====
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${SQL_FILE}.bak.$TIMESTAMP"
cp "$SQL_FILE" "$BACKUP_FILE"
echo "${GREEN}📂 Backup created:${RESET} $BACKUP_FILE"

# ===== Detect Conversion Mode =====
detect_mode() {
  if grep -qiE 'utf8mb4_0900|INVISIBLE|STORED GENERATED|histogram' "$SQL_FILE"; then
    echo "2"  # MySQL → MariaDB
  elif grep -qiE 'Aria|ROW_FORMAT|KEY_BLOCK_SIZE|DEFINER=|NO_AUTO_CREATE_USER' "$SQL_FILE"; then
    echo "1"  # MariaDB → MySQL
  else
    echo "0"  # Unknown
  fi
}

DEFAULT_MODE=$(detect_mode)

# ===== Prompt User for Mode (if needed) =====
echo ""
echo "${CYAN}🚀 SQL Compatibility Fixer${RESET}"
echo "Detected mode:"

case "$DEFAULT_MODE" in
  1) echo "🔁 Suggested: ${YELLOW}MariaDB → MySQL${RESET}" ;;
  2) echo "🔁 Suggested: ${YELLOW}MySQL → MariaDB${RESET}" ;;
  *) echo "${YELLOW}❓ Type unknown${RESET}" ;;
esac

if [[ -z "$MODE" ]]; then
  echo ""
  echo "Select conversion mode:"
  echo "1) MariaDB → MySQL"
  echo "2) MySQL → MariaDB"
  echo "3) Cancel"
  read -rp "Enter choice [1/2/3]: " MODE

  if [[ "$MODE" == "3" || -z "$MODE" ]]; then
    echo "${RED}❌ Cancelled by user.${RESET}"
    exit 0
  fi
fi

# ===== Apply Fixes =====
apply_fix() {
  local pattern="$1"
  local replacement="$2"
  local matches

  matches=$(grep -oE "$pattern" "$SQL_FILE" || true)
  local count=$(echo "$matches" | wc -l)

  if (( count > 0 )); then
    ((fixes+=count))
    if [[ "$DRY_RUN" == false ]]; then
      sed -i -E "s/$pattern/$replacement/g" "$SQL_FILE"
    fi
    echo "✅ Replaced $count instance(s) of '$pattern'"
  fi
}

echo ""
echo "🔧 Applying fixes..."

if [[ "$MODE" == "1" ]]; then
  apply_fix '\bENGINE=Aria\b' 'ENGINE=InnoDB'
  apply_fix '\bROW_FORMAT=[A-Z]+' ''
  apply_fix '\bKEY_BLOCK_SIZE=[0-9]+' ''
  apply_fix 'DEFINER=`[^`]+`@`[^`]+`' ''
  apply_fix '\bNO_AUTO_CREATE_USER\b' ''
elif [[ "$MODE" == "2" ]]; then
  apply_fix '\butf8mb4_0900_ai_ci\b' 'utf8mb4_general_ci'
  apply_fix '\butf8mb4_0900_bin\b' 'utf8mb4_bin'
  apply_fix '\butf8mb4_0900_as_cs\b' 'utf8mb4_general_ci'
  apply_fix '\butf8mb3\b' 'utf8mb4'
  apply_fix '\bENGINE=MyISAM\b' 'ENGINE=InnoDB'
else
  echo "${RED}❌ Invalid mode selected.${RESET}"
  exit 1
fi

# ===== Report Summary =====
echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "${YELLOW}🔍 Dry run: no changes were made.${RESET}"
else
  echo "${GREEN}✅ Fixes applied successfully to:${RESET} $SQL_FILE"
fi

if (( fixes == 0 )); then
  echo "${YELLOW}ℹ️  No changes were necessary. The file seems compatible already.${RESET}"
else
  echo "🛠️  Total replacements: ${CYAN}$fixes${RESET}"
fi

echo "🗃️  Backup file saved as: ${CYAN}$BACKUP_FILE${RESET}"
