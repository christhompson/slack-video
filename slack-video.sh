#!/bin/bash

# set -x

#################
# CONFIGURATION #
#################
CHANNEL="C1KSMEQ76"  # Run in channel #video-player
MESSAGE="Let's watch a video! Expand attachment to watch!"
ENDMESSAGE="Thanks for watching!"
FPS=2
WIDTH=70
APPDIR=~/.slack-video/
LOCK=$APPDIR/lock

# FUNCTIONS
function videoToJpgs {
    # Convert video to images using FFMPEG
    # $1 is path of video file to convert
    ffmpeg -i "$1" -vf fps=$FPS "$2/thumb%10d.jpg" >/dev/null 2>/dev/null
}

function newMsg {
    # $1 is videoname
    # Creates a new slack message and returns the timestamp.
    curl https://slack.com/api/chat.postMessage -X POST \
    -d "token=$TOKEN" \
    -d "channel=$CHANNEL" \
    -d "text=$MESSAGE" \
    --data-urlencode "attachments=
    [
        {
             \"pretext\": \"Video will start in 10s...\",
             \"title\": \"$1\",
             \"text\": \"\`\`\`Expand attachment to watch\\n\\n\\n\\n\\n\`\`\`\",
             \"mrkdwn_in\": [
                 \"text\"
             ]
         }
     ]" \
    -d "pretty=1" 2> /dev/null | jq '.ts'
}

function showFrame {
    # $1 is videoname, $2 is timestamp, $3 is frame, $4 is current subtitle
    # Displays frame as an attachment to the message.
    curl https://slack.com/api/chat.update -X POST \
    -d "token=$TOKEN" \
    -d "ts=$2" \
    -d "channel=$CHANNEL" \
    -d "text=$MESSAGE" \
    --data-urlencode "attachments=
    [
        {
             \"pretext\": \"Video is playing...\",
             \"title\": \"$1\",
             \"text\": \"\`\`\`$3\`\`\`\",
             \"mrkdwn_in\": [
                 \"text\"
             ]
         },
         {
             \"title\": \"subtitle\",
             \"text\": \"\`\`\`$4\`\`\`\",
             \"mrkdwn_in\": [
                 \"text\"
             ]
         }
     ]" \
    -d "pretty=1" 1> /dev/null 2> /dev/null
}

function endVideo {
    # $1 is timestamp
    # Thanks the viewer, removes attachment.
    curl https://slack.com/api/chat.update -X POST \
    -d "token=$TOKEN" \
    -d "ts=$1" \
    -d "channel=$CHANNEL" \
    -d "text=$ENDMESSAGE" \
    --data-urlencode "attachments=[]" \
    -d "pretty=1" 1> /dev/null 2> /dev/null
}

function secToTime {
    # $1 is time in seconds
    i=$1
    ((sec=i%60, i/=60, min=i%60, hrs=i/60))
    printf "%01d:%02d:%02d" $hrs $min $sec
}

########
# MAIN #
########

# ARGS
if [ -z "$TOKEN" ]; then
    echo "Must set TOKEN environment variable with slack API token"
    exit 1
fi

if [ ! $# -ge 1 ]; then
    echo "Must provide at least video file as an argument."
    exit 1
fi

videofile=$1
subfile=$2

mkdir -p $APPDIR

# mkdir is be atomic on *nix, so we use it for a mutex.
# See http://wiki.bash-hackers.org/howto/mutex
if mkdir $LOCK; then
  echo "Locking succeeded."
else
  echo "Video player already running. Only one video at a time allowed."
  exit 1
fi

# Extract basename without extension of the video file
# See SO #2664740
videoname=$(basename "$videofile")
videoname=${videoname%.*}

# Create dir for the thumbnails and convert to JPG
if [ ! -e "$APPDIR/thumbs/$videoname" ]; then
    echo "Video not yet converted to thumbs. Converting, please wait..."
    mkdir -p "$APPDIR/thumbs/$videoname/"
    videoToJpgs "$videofile" "$APPDIR/thumbs/$videoname/"
fi

echo "Creating new slack message player in #video-player. Playback starts in 10s."
timestamp=$(newMsg $videoname)

sleep 10

for f in "$APPDIR/thumbs/$videoname"/*
do
  echo "Displaying file $f..."
  ASCII=`jp2a --width=$WIDTH "$f"`

  # int(basename($f)) / $fps = time in video in seconds, then convert to H:MM:SS
  seconds=$(expr $(basename -s .jpg $f | cut -b6-) / $FPS)
  before=$(expr $time - 1)
  after=$(expr $time + 1)
  currentTime=$(secToTime $time)
  beforeTime=$(secToTime $before)
  afterTime=$(secToTime $after)

  # Extract dialog from matching timestamps, remove formatting
  lines=$(egrep "($currentTime\.\d\d)|($beforeTime\.\d\d)|($afterTime\.\d\d)" $subfile)
  linesDialog=$(printf "$lines" | cut -d',' -f10-)
  linesDialog=$(printf "$linesDialog" | sed -e 's/{[^}]*}//g' | sed -e 's/\\N/ /g')

  # Pad with newlines to 5 lines to reduce display jitter
  numLines=$(echo $linesDialog | egrep '.+' | wc -l | tr -dc '0-9')
  numPad=$(expr 5 - $numLines)
  for i in $(seq 1 $numPad); do linesDialog="$linesDialog\n"; done

  # Show frame and all matching subs
  showFrame "$videoname" "$timestamp" "$ASCII" "$linesDialog"

  # Frame rate limit by sleeping a short bit
  sleep $(echo "scale=2;1.0/$FPS" | bc)
done

endVideo $timestamp

# Release the lock.
rmdir $LOCK

echo "Done playing. Lock released."
