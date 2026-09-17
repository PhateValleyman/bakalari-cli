#!/bin/bash
# Script to check pending homeworks and trigger Android termux-notification

USERNAME="Mulle08410"
PASSWORD="7f9CjHMM"
LOGIN_URL="https://zssumava.bakalari.cz/api/login"
HOMEWORKS_URL="https://zssumava.bakalari.cz/api/3/homeworks"

# Automatically fetch token if not set or empty
if [ -z "$TOKEN" ]; then
    RESPONSE=$(curl -s -X POST "$LOGIN_URL" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=ANDR&grant_type=password&username=${USERNAME}&password=${PASSWORD}")
    export TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')
fi

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to obtain access token."
    exit 1
fi

# Fetch homework list from API
RESPONSE=$(curl -s -X GET "$HOMEWORKS_URL" -H "Authorization: Bearer $TOKEN")

# Validate if response is a valid JSON object containing 'Homeworks'
if ! echo "$RESPONSE" | jq -e '.Homeworks' >/dev/null 2>&1; then
    echo "Error: Invalid response from Bakalari API."
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

# Filter unfinished homeworks using jq
UNFINISHED=$(echo "$RESPONSE" | jq -r '
  .Homeworks[]? | select(.IsDone == false or .IsDone == null) | 
  "[" + .Subject.Abbrev + "] " + .Content + " (do: " + .DateEnd[0:10] + ")"
')

if [ -n "$UNFINISHED" ] && [ "$UNFINISHED" != "null" ]; then
    # Count total missing homeworks
    COUNT=$(echo "$UNFINISHED" | wc -l)
    
    # Format message body for notification
    MESSAGE=$(echo "$UNFINISHED" | head -n 3 | tr '\n' ' ')
    
    echo -e "\033[1;31m[!] Nalezeny nesplněné domácí úkoly ($COUNT):\033[0m"
    echo "$UNFINISHED"

    # Send Android notification if termux-api tool exists
    if command -v termux-notification &> /dev/null; then
        termux-notification \
          --title "Bakaláři: Nesplněný úkol ($COUNT)" \
          --content "$MESSAGE" \
          --priority high \
          --sound \
          --vibrate 500,200,500 \
          --id "bakalari_hw_alert"
    fi
else
    echo -e "\033[1;32m[✓] Všechny domácí úkoly jsou hotové nebo žádné nejsou zadány.\033[0m"
fi
