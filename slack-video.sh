#!/bin/bash

######################
# CONFIGURATION
######################
# Run in channel #video-player
CHANNEL="C1KSMEQ76"
MESSAGE="Let's watch a video!"
TITLE="ETI SlackBot Video"
APPDIR=~/.slack-video/
LOCK=$APPDIR/lock
FPS=1
WIDTH=60

function videoToJpgs {
    # Convert video to images using FFMPEG
    ffmpeg -i $1 -vf fps=$FPS $2/thumb%04d.jpg >/dev/null 2>/dev/null
}

function newMsg {
    # $1 is message
    curl https://slack.com/api/chat.postMessage -X POST \
    -d "token=$TOKEN" \
    -d "channel=$CHANNEL" \
    -d "text=\`\`\`$MESSAGE\`\`\`" \
    -d "pretty=1" 2> /dev/null | jq '.ts'
}

function updateMsg {
    # $1 is timestamp, $2 is message
    curl https://slack.com/api/chat.update -X POST \
    -d "token=$TOKEN" \
    -d "ts=$1" \
    -d "channel=$CHANNEL" \
    -d "text=\`\`\`$2\`\`\`" \
    -d "pretty=1" 1> /dev/null 2> /dev/null
}

###########
# MAIN
###########

if [ -z "$TOKEN" ]; then
    echo "Must set TOKEN environment variable with slack API token."
    exit 1
fi

if [ ! $# -eq 1 ]; then
    echo "Must provide video file as only argument"
    exit 1
fi

mkdir -p $APPDIR

# mkdir is be atomic on *nix, so we use it for a mutex.
# See http://wiki.bash-hackers.org/howto/mutex
if mkdir $LOCK; then
  echo "Locking succeeded" >&2
else
  echo "Video player already running. Only one video at a time allowed." >&2
  exit 1
fi

# Extract basename without extension of the video file
# See SO #2664740
videoname=$(basename $1)
videoname=${s%.*}

# Create dir for the thumbnails and convert to JPG
if [ ! -e "$APPDIR/thumbs/$videoname/" ]; then
    echo "Video not yet converted to thumbs. Converting, please wait..."
    mkdir -p "$APPDIR/thumbs/$videoname/"
    videoToJpgs $1 "$APPDIR/thumbs/$videoname/"
fi

echo "Creating new slack message player in #video-player. Playback starts in 10s."
timestamp=$(newMsg $MESSAGE)

sleep 10

FILES="$APPDIR/thumbs/$videoname/*"
for f in $FILES
do
  echo "Displaying file $f..."
  updateMsg $timestamp "$(jp2a --width=$WIDTH $f)"
#   sleep 1
done

updateMsg $timestamp "[End of video]"

# Release the lock
rmdir $LOCK

echo "Done playing. Lock released."