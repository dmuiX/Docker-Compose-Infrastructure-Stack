#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="samba-dc"
DOMAIN="domain.org"
ADMIN_USER="Administrator"
ADMIN_PASS_FILE="$SCRIPT_DIR/samba_admin_pass"
INPUT="$SCRIPT_DIR/dns-records"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Read password from file (same as your docker secret)
if [ ! -f "$ADMIN_PASS_FILE" ]; then
  echo "Error: $ADMIN_PASS_FILE not found"
  exit 1
fi

ADMIN_PASS=$(cat "$ADMIN_PASS_FILE" | tr -d '\n\r')

if [ ! -f "$INPUT" ]; then
  echo "File $INPUT not found"
  exit 1
fi

# 1. Fetch ALL records once (High Performance)
echo "Fetching current DNS records..."
CACHE_FILE=$(mktemp)
PARSED_CACHE_FILE=$(mktemp)
docker exec "$CONTAINER" samba-tool dns query 127.0.0.1 "$DOMAIN" @ ALL \
  -U"${ADMIN_USER}%${ADMIN_PASS}" > "$CACHE_FILE"

# Parse raw samba output into: host<TAB>type<TAB>value
awk '
  /^  Name=/ {
    if (match($0, /Name=([^,]+)/, m)) host = m[1]
    next
  }
  {
    if (host != "" && match($0, /^[[:space:]]+([A-Z0-9]+):[[:space:]]+(.+)$/, m)) {
      type = m[1]
      value = m[2]
      sub(/[[:space:]]+\(flags=.*$/, "", value)
      print host "\t" type "\t" value
    }
  }
' "$CACHE_FILE" > "$PARSED_CACHE_FILE"

# 2. Process file
while IFS=, read -r TYPE HOST VALUE; do
  # Skip comments / empty lines and normalize whitespace
  TYPE=$(trim "$TYPE")
  HOST=$(trim "$HOST")
  VALUE=$(trim "$VALUE")

  [[ "$TYPE" =~ ^# ]] && continue
  [ -z "$TYPE" ] && continue
  [ -z "$HOST" ] && continue
  [ -z "$VALUE" ] && continue

  # Exact match: host + type + value already present
  if awk -F'\t' -v host="$HOST" -v type="$TYPE" -v value="$VALUE" \
    '$1 == host && $2 == type && $3 == value { found=1; exit } END { exit !found }' \
    "$PARSED_CACHE_FILE"; then
    echo "  [SKIP] $TYPE $HOST -> $VALUE (Already exists)"
    continue
  fi

  # If host/type exists with other values, delete them first to avoid round-robin accumulation.
  OLD_VALUES=$(awk -F'\t' -v host="$HOST" -v type="$TYPE" \
    '$1 == host && $2 == type { print $3 }' "$PARSED_CACHE_FILE")

  if [ -n "$OLD_VALUES" ]; then
    echo "  [UPDATE] $TYPE $HOST: deleting old values"
    while IFS= read -r OLD_VALUE; do
      [ -z "$OLD_VALUE" ] && continue
      docker exec "$CONTAINER" \
        samba-tool dns delete 127.0.0.1 "$DOMAIN" "$HOST" "$TYPE" "$OLD_VALUE" \
        -U"${ADMIN_USER}%${ADMIN_PASS}" >/dev/null 2>&1
    done <<< "$OLD_VALUES"
  fi

  echo "  [ADD]  $TYPE $HOST -> $VALUE"
  docker exec "$CONTAINER" \
      samba-tool dns add 127.0.0.1 "$DOMAIN" "$HOST" "$TYPE" "$VALUE" \
      -U"${ADMIN_USER}%${ADMIN_PASS}"

  # Keep parsed cache in sync for following lines in the same run
  awk -F'\t' -v host="$HOST" -v type="$TYPE" \
    '!( $1 == host && $2 == type )' "$PARSED_CACHE_FILE" > "${PARSED_CACHE_FILE}.tmp" && \
    mv "${PARSED_CACHE_FILE}.tmp" "$PARSED_CACHE_FILE"
  printf '%s\t%s\t%s\n' "$HOST" "$TYPE" "$VALUE" >> "$PARSED_CACHE_FILE"

done < "$INPUT"

rm -f "$CACHE_FILE"
rm -f "$PARSED_CACHE_FILE"
