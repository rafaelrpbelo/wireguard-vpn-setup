#!/bin/bash
# Notification dispatcher. Source this file, then call: notify "title" "message"
# Add new provider blocks below to support additional services.

notify() {
  local title="$1" message="$2"

  # Pushover
  if [ -n "$PUSHOVER_USER" ] && [ -n "$PUSHOVER_TOKEN" ]; then
    curl -s -o /dev/null \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      https://api.pushover.net/1/messages.json
  fi
}
