#!/bin/zsh
# cert-check.sh — macOS-safe TLS certificate expiry checker
# Place this in the same directory as your goose recipes
# Usage: ./cert-check.sh <namespace> [namespace2 ...]
# Output: one line per cert, then a SUMMARY line

WARN_DAYS=${WARN_DAYS:-30}
CRIT_DAYS=${CRIT_DAYS:-7}
TODAY=$(date +%s)

RED=0
AMBER=0
GREEN=0
TOTAL=0

parse_date_epoch() {
  local date_str="$1"
  local epoch=""

  # Try macOS date first (BSD date)
  epoch=$(date -j -f "%b %e %H:%M:%S %Y %Z" "$date_str" +%s 2>/dev/null)
  [ -n "$epoch" ] && echo "$epoch" && return

  # Try with single-digit day padding variant
  epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$date_str" +%s 2>/dev/null)
  [ -n "$epoch" ] && echo "$epoch" && return

  # Fallback: GNU date (Linux)
  epoch=$(date -d "$date_str" +%s 2>/dev/null)
  [ -n "$epoch" ] && echo "$epoch" && return

  # Last resort: python3
  epoch=$(python3 -c "
from datetime import datetime
import sys
try:
    s = '$date_str'.strip()
    for fmt in ['%b %d %H:%M:%S %Y %Z', '%b  %d %H:%M:%S %Y %Z']:
        try:
            import calendar, time
            t = time.strptime(s, fmt)
            print(int(calendar.timegm(t)))
            sys.exit(0)
        except: pass
except: pass
" 2>/dev/null)
  [ -n "$epoch" ] && echo "$epoch" && return

  echo ""
}

for NS in "$@"; do
  # Get TLS secret names
  TLS_SECRETS=$(kubectl get secrets -n "$NS" \
    --field-selector type=kubernetes.io/tls \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

  # Get secrets with ca.crt (CFK CA secrets)
  CA_SECRETS=$(kubectl get secrets -n "$NS" -o json 2>/dev/null | \
    jq -r '.items[] | select(.data | has("ca.crt")) | .metadata.name' 2>/dev/null)

  ALL_SECRETS=$(printf "%s\n%s" "$TLS_SECRETS" "$CA_SECRETS" | sort -u | grep -v '^$')

  for SECRET in ${(f)ALL_SECRETS}; do
    for KEY in "tls.crt" "ca.crt"; do
      JSONPATH=".data[\"${KEY}\"]"
      CERT_B64=$(kubectl get secret "$SECRET" -n "$NS" \
        -o json 2>/dev/null | jq -r "$JSONPATH" 2>/dev/null)
      [ -z "$CERT_B64" ] || [ "$CERT_B64" = "null" ] && continue

      EXPIRY_STR=$(echo "$CERT_B64" | base64 -d 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      [ -z "$EXPIRY_STR" ] && continue

      EXPIRY_EPOCH=$(parse_date_epoch "$EXPIRY_STR")
      if [ -z "$EXPIRY_EPOCH" ]; then
        echo "UNKNOWN|${NS}|${SECRET}|${KEY}|?|${EXPIRY_STR}"
        continue
      fi

      DAYS_LEFT=$(( (EXPIRY_EPOCH - TODAY) / 86400 ))
      TOTAL=$((TOTAL + 1))

      if [ "$DAYS_LEFT" -le "$CRIT_DAYS" ]; then
        STATUS="RED"
        RED=$((RED + 1))
      elif [ "$DAYS_LEFT" -le "$WARN_DAYS" ]; then
        STATUS="AMBER"
        AMBER=$((AMBER + 1))
      else
        STATUS="GREEN"
        GREEN=$((GREEN + 1))
      fi

      echo "${STATUS}|${NS}|${SECRET}|${KEY}|${DAYS_LEFT} days|${EXPIRY_STR}"
    done
  done
done

echo "---"
echo "SUMMARY | Total: ${TOTAL} | RED: ${RED} | AMBER: ${AMBER} | GREEN: ${GREEN}"
