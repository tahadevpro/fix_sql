#!/bin/bash

SQL_FILE=""
DRY_RUN=false

# ========== Parse Args ==========
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      echo "Usage: $0 path/to/file.sql [--dry-run]"
      echo "  --dry-run    Preview changes without modifying the file"
      exit 0
      ;;
    *)
      if [[ -z "$SQL_FILE" && "$arg" != -* ]]; then
        SQL_FILE="$arg"
      fi
      ;;
  esac
done

# ========== Validate Input ==========
if [[ -z "$SQL_FILE" ]]; then
  echo "❌ No SQL file provided."
  echo "Usage: $0 path/to/file.sql [--dry-run]"
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "❌ File not found: $SQL_FILE"
  exit 1
fi

# ========== Backup ==========
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${SQL_FILE}.bak.$TIMESTAMP"
cp "$SQL_FILE" "$BACKUP_FILE"
echo "📂 Backup created: $BACKUP_FILE"

# ========== Detect Mode ==========
detect_mode() {
  if grep -qiE 'utf8mb4_0900|utf8mb3' "$SQL_FILE"; then
    echo "2"  # MySQL → MariaDB
  elif grep -qiE 'Aria|ROW_FORMAT|KEY_BLOCK_SIZE|DEFINER=[^ ]+' "$SQL_FILE"; then
    echo "1"  # MariaDB → MySQL
  else
    echo "0"  # Unknown
  fi
}

DEFAULT_MODE=$(detect_mode)

# ========== Prompt for Mode ==========
echo ""
echo "🚀 SQL Fixer"
echo "Detected conversion mode:"

case "$DEFAULT_MODE" in
  1) echo "🔁 Suggested: MariaDB → MySQL" ;;
  2) echo "🔁 Suggested: MySQL → MariaDB" ;;
  *) echo "❓ Type unknown" ;;
esac

echo ""
echo "Select conversion mode:"
echo "1) MariaDB → MySQL"
echo "2) MySQL → MariaDB"
echo "3) Cancel"
read -p "Enter choice [1/2/3]: " MODE

if [[ "$MODE" == "3" || -z "$MODE" ]]; then
  echo "❌ Cancelled."
  exit 0
fi

# ========== Fix Patterns ==========
fixes=0

apply_fix() {
  pattern="$1"
  replacement="$2"
  count=$(grep -oE "$pattern" "$SQL_FILE" | wc -l)
  if (( count > 0 )); then
    ((fixes+=count))
    if [[ "$DRY_RUN" == false ]]; then
      sed -i -E "s/$pattern/$replacement/g" "$SQL_FILE"
    fi
  fi
}

echo ""
echo "🔧 Applying fixes..."

if [[ "$MODE" == "1" ]]; then
  apply_fix "ENGINE=Aria" "ENGINE=InnoDB"
  apply_fix "ROW_FORMAT=[A-Z]+" ""
  apply_fix "KEY_BLOCK_SIZE=[0-9]+" ""
  apply_fix "DEFINER=[^ ]+" ""
  apply_fix "NO_AUTO_CREATE_USER" ""
elif [[ "$MODE" == "2" ]]; then
  apply_fix "utf8mb4_0900_ai_ci" "utf8mb4_general_ci"
  apply_fix "utf8mb4_0900_bin" "utf8mb4_bin"
  apply_fix "utf8mb4_0900_as_cs" "utf8mb4_general_ci"
  apply_fix "utf8mb3" "utf8mb4"
  apply_fix "ENGINE=MyISAM" "ENGINE=InnoDB"
else
  echo "❌ Invalid mode selected."
  exit 1
fi

# ========== Done ==========
echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "🔍 Dry run: no changes were made."
else
  echo "✅ Fixes applied to '$SQL_FILE'"
fi
echo "🛠️  Total replacements: $fixes"
echo "📦 Backup saved as: $BACKUP_FILE"
