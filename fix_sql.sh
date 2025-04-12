#!/bin/bash

SQL_FILE="$1"
DRY_RUN=false
BACKUP_FILE=""

if [[ "$2" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [[ -z "$SQL_FILE" ]]; then
  echo "🔍 Enter path to SQL file:"
  read SQL_FILE
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "❌ File not found: $SQL_FILE"
  exit 1
fi

# ==================== Backup ====================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${SQL_FILE}.bak.$TIMESTAMP"
cp "$SQL_FILE" "$BACKUP_FILE"
echo "📂 Backup created at $BACKUP_FILE"

# ==================== Detect Type ====================
detect_mode() {
  if grep -qiE 'utf8mb4_0900|utf8mb3' "$SQL_FILE"; then
    echo "2" # MySQL → MariaDB
  elif grep -qiE 'Aria|ROW_FORMAT|KEY_BLOCK_SIZE|DEFINER=[^ ]+' "$SQL_FILE"; then
    echo "1" # MariaDB → MySQL
  else
    echo "0" # Unknown
  fi
}

DEFAULT_MODE=$(detect_mode)
MODE_LABEL=""

if [[ "$DEFAULT_MODE" == "1" ]]; then
  MODE_LABEL="(suggested: MariaDB → MySQL)"
elif [[ "$DEFAULT_MODE" == "2" ]]; then
  MODE_LABEL="(suggested: MySQL → MariaDB)"
else
  MODE_LABEL="(type unknown)"
fi

echo "🚀 SQL Fixer"
echo "Select conversion mode $MODE_LABEL"
echo "1) MariaDB → MySQL"
echo "2) MySQL → MariaDB"
echo "3) Cancel"
read -p "Enter choice: " MODE

if [[ "$MODE" == "3" || -z "$MODE" ]]; then
  echo "❌ Cancelled."
  exit 0
fi

# ==================== Process ====================
fixes=0

apply_fix() {
  pattern="$1"
  replace="$2"
  count=$(grep -oE "$pattern" "$SQL_FILE" | wc -l)
  if (( count > 0 )); then
    ((fixes+=count))
    if [[ "$DRY_RUN" == false ]]; then
      sed -i -E "s/$pattern/$replace/g" "$SQL_FILE"
    fi
  fi
}

echo "🔧 Applying fixes..."

if [[ "$MODE" == "1" ]]; then
  apply_fix "ENGINE=Aria" "ENGINE=InnoDB"
  apply_fix "ROW_FORMAT=[A-Z]+" ""
  apply_fix "KEY_BLOCK_SIZE=[0-9]+" ""
  apply_fix "DEFINER=[^ ]+" ""
  apply_fix "NO_AUTO_CREATE_USER" ""
fi

if [[ "$MODE" == "2" ]]; then
  apply_fix "utf8mb4_0900_ai_ci" "utf8mb4_general_ci"
  apply_fix "utf8mb4_0900_bin" "utf8mb4_bin"
  apply_fix "utf8mb4_0900_as_cs" "utf8mb4_general_ci"
  apply_fix "utf8mb3" "utf8mb4"
  apply_fix "ENGINE=MyISAM" "ENGINE=InnoDB"
fi

# ==================== Done ====================
echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "🔍 Dry run mode: no changes applied to '$SQL_FILE'"
else
  echo "✅ Fixes applied to '$SQL_FILE'"
fi
echo "🛠️  Total replacements: $fixes"
echo "📦 Backup saved as: $BACKUP_FILE"
