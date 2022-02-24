#!/usr/bin/env bash

#
# Version adapted from 2020 Ryan Richard
#
# Note: Requires ffmpeg and jq
#
# This script is safe to run multiple times for the same output directory. It will retain your previous files
# and will only download photos and videos that were not previously downloaded.
#

set -eo pipefail

# The user should set these environment variables or else it will use these defaults
: "${HIKVISION_USERNAME:=Wyndhurst}"
: "${HIKVISION_PASSWORD:=Moocow21}"
: "${HIKVISION_HOST:=10.70.66.6:8081}"

# Get the command-line arguments
NUM_DAYS=$1
DOWNLOAD_DIR=$2

if [[ -z "$NUM_DAYS" ]] || ! [[ $NUM_DAYS =~ ^[0-9]+$ ]]; then
  echo "ERROR: Please use number of days to download as the first argument." >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_DIR" ]]; then
  echo "ERROR: Please specify download destination directory as the second argument." >&2
  exit 1
fi

set -u

IFS=$'\n'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
INDEX_FILENAME="index.html"

mkdir -p "$DOWNLOAD_DIR"

for DAYS_AGO in $(seq 0 "$NUM_DAYS"); do

  if [[ $DAYS_AGO -eq 0 ]]; then
    from="10 seconds ago"
    to="now"
  else
    from="$DAYS_AGO days ago at 12:00:00 AM"
    to="$DAYS_AGO days ago at 11:59:59 PM"
  fi

  SEARCH_RESULT=$(java -jar "$SCRIPT_DIR/importer.jar" \
    "$HIKVISION_HOST" "$HIKVISION_USERNAME" "$HIKVISION_PASSWORD" \
    --from-time "$from" --to-time "$to" \
    --output json --quiet)

  RESULT_DATE=$(echo "$SEARCH_RESULT" | jq -r .metadata.fromTime | cut -c1-10)

  DAY_DIR="$DOWNLOAD_DIR/$RESULT_DATE"
  mkdir -p "$DAY_DIR"
  pushd "$DAY_DIR" >/dev/null

  for RESULT in $(echo "$SEARCH_RESULT" | jq -r --compact-output '.results[]'); do

    CURL_COMMAND=$(echo "$RESULT" | jq -r '.curlCommand')
    DOWNLOAD_FILENAME=$(echo "$CURL_COMMAND" | rev | cut -d ' ' -f 1 | rev)

    if [[ $DOWNLOAD_FILENAME == *mp4 ]]; then

      # For videos, download and transcode
      FIXED_FILENAME="$(basename "$DOWNLOAD_FILENAME" .mp4).fixed.mp4"
      SEGMENT_FILENAME="$(basename "$DOWNLOAD_FILENAME" .mp4)+%05d.avi"

      # SEGMENT_FOLDER="$(dirname "$DOWNLOAD_FILENAME")/frames/$(basename "$DOWNLOAD_FILENAME" .mp4)"
      # mkdir -p "$SEGMENT_FOLDER"
      # SEGMENT_FILENAME="$(dirname "$DOWNLOAD_FILENAME")/frames/$(basename "$DOWNLOAD_FILENAME" .mp4)+%05d.jpg"

      if ! [[ -f $FIXED_FILENAME ]]; then
        echo "Downloading $DOWNLOAD_FILENAME"
        eval "$CURL_COMMAND -s"
        echo "Transcoding $DOWNLOAD_FILENAME"
        ffmpeg -err_detect ignore_err -i "$DOWNLOAD_FILENAME" -c copy "$FIXED_FILENAME" -hide_banner -loglevel warning
        # ffmpeg -err_detect ignore_err -i "$FIXED_FILENAME" -vf fps=1/20 "$SEGMENT_FILENAME" -hide_banner -loglevel warning
        ffmpeg -err_detect ignore_err -i "$FIXED_FILENAME" -c copy -map 0 -segment_time 00:01:00 -f segment -reset_timestamps 1 "$SEGMENT_FILENAME"
        rm "$DOWNLOAD_FILENAME"
      else
        echo "Already downloaded $DOWNLOAD_FILENAME"
      fi

    else

      # For photos, just download
      if ! [[ -f $DOWNLOAD_FILENAME ]]; then
        echo "Downloading $DOWNLOAD_FILENAME"
        eval "$CURL_COMMAND -s"
      else
        echo "Already downloaded $DOWNLOAD_FILENAME"
      fi
    fi

  done # done downloading all files in the day directory
  popd >/dev/null
done

echo "Outputting frames"
python3 Cows2021/make_data/1video_to_frames.py
echo "Building JSON"
python3 Cows2021/make_data/2output_dt_json.py

