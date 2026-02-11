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

# ===== Help =====
print_help() {
  echo "${CYAN}Usage:${RESET} $0 path/to/file.sql [--dry-run]"
  echo "  --dry-run    Preview changes without modifying the file"
  exit 0
}

# ===== Args =====
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    -h|--help) print_help ;;
    *) [[ -z "$SQL_FILE" && "$arg" != -* ]] && SQL_FILE="$arg" ;;
  esac
done

[[ -z "$SQL_FILE" ]] && { echo "${RED}❌ No SQL file provided${RESET}"; exit 1; }
[[ ! -f "$SQL_FILE" ]] && { echo "${RED}❌ File not found: $SQL_FILE${RESET}"; exit 1; }

# ===== Backup =====
TS=$(date +%Y%m%d_%H%M%S)
BACKUP="${SQL_FILE}.bak.${TS}"
cp "$SQL_FILE" "$BACKUP"
echo "${GREEN}📦 Backup created:${RESET} $BACKUP"

# ===== Detect Mode =====
detect_mode() {
  if grep -qiE 'utf8mb4_0900|utf8mb3' "$SQL_FILE"; then
    echo "2"
  else
    echo "0"
  fi
}

DEFAULT_MODE=$(detect_mode)

echo ""
echo "${CYAN}🚀 SQL Compatibility Fixer${RESET}"
echo "Detected mode: MySQL → MariaDB"

MODE=2

# ===== Replace helper =====
apply_fix() {
  local pattern="$1"
  local replace="$2"
  local count
  count=$(grep -oiE "$pattern" "$SQL_FILE" | wc -l || true)

  (( count == 0 )) && return

  ((fixes+=count))
  [[ "$DRY_RUN" == false ]] && sed -i -E "s/$pattern/$replace/gI" "$SQL_FILE"
  echo "✅ $pattern  →  $replace  ($count)"
}

echo ""
echo "🔧 Applying fixes..."

# ===== MySQL 8 → MariaDB fixes =====

# 1️⃣ mysql8-only collations
apply_fix '\butf8mb4_0900_ai_ci\b' 'utf8mb4_unicode_ci'
apply_fix '\butf8mb4_0900_as_cs\b' 'utf8mb4_unicode_ci'
apply_fix '\butf8mb4_0900_bin\b'    'utf8mb4_bin'

# 2️⃣ utf8mb3 → utf8mb4 (COLLATION first)
apply_fix '\butf8mb3_unicode_ci\b' 'utf8mb4_unicode_ci'
apply_fix '\butf8mb3_general_ci\b' 'utf8mb4_general_ci'

# 3️⃣ utf8mb3 charset
apply_fix '\bCHARACTER SET utf8mb3\b' 'CHARACTER SET utf8mb4'
apply_fix '\butf8mb3\b' 'utf8mb4'

# 4️⃣ Engine safety
apply_fix '\bENGINE=MyISAM\b' 'ENGINE=InnoDB'

# ===== Summary =====
echo ""
[[ "$DRY_RUN" == true ]] && echo "${YELLOW}🔍 Dry run only — no changes applied${RESET}"
echo "${GREEN}✅ Done${RESET}"
echo "🛠️  Total fixes: ${CYAN}$fixes${RESET}"
echo "🗂️  Backup: $BACKUP"
