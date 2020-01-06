#!/bin/bash

# Audio 1: AudioTrack.kind = "main"; AudioTrack.language = "en"
# Audio 2: AudioTrack.kind = "alternative"; AudioTrack.language = "es"

# Video 1: VideoTrack.kind = "main" (black background)
# Video 2: VideoTrack.kind = "alternative" (blue background)

set -eu
DIR="$(realpath "$(dirname "$0")")"
ASSETS_DIR="$(realpath $DIR/assets)"

set -x
mkdir -p "$ASSETS_DIR"
cd "$DIR/assets-ingredients"

if [ ! -f "video-alternative.webm" ]; then
  gcc $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-app-1.0 cairo) gen-video.c -o gen-video
  ./gen-video 0 mp4 && mv video.mp4 video-main.mp4
  ./gen-video 1 mp4 && mv video.mp4 video-alternative.mp4
  ./gen-video 0 webm && mv video.webm video-main.webm
  ./gen-video 1 webm && mv video.webm video-alternative.webm
fi

AUDIO_EN_AAC='filesrc location=counting-en.flac ! flacparse ! flacdec ! audioconvert ! avenc_aac ! taginject tags="language-code=en"'
AUDIO_ES_AAC='filesrc location=counting-es.flac ! flacparse ! flacdec ! audioconvert ! avenc_aac ! taginject tags="language-code=es"'

VIDEO_MAIN_H264="filesrc location=video-main.mp4 ! qtdemux"
VIDEO_ALTERNATIVE_H264="filesrc location=video-alternative.mp4 ! qtdemux"

AUDIO_EN_OPUS='filesrc location=counting-en.flac ! flacparse ! flacdec ! audioconvert ! audioresample ! opusenc ! taginject tags="language-code=en"'
AUDIO_ES_OPUS='filesrc location=counting-es.flac ! flacparse ! flacdec ! audioconvert ! audioresample ! opusenc ! taginject tags="language-code=es"'

VIDEO_MAIN_VP9="filesrc location=video-main.webm ! matroskademux"
VIDEO_ALTERNATIVE_VP9="filesrc location=video-alternative.webm ! matroskademux"

function retry() {
  # There is some flakiness in mp4mux when handling several video tracks. Try again if it fails.
  local attempts=0
  while ! "$@"; do
    (( attempts++ ))
    if [ $attempts -ge 10 ]; then
      echo "Failed too many times, giving up."
      exit 1
    fi
  done
}

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-1video-1audio.mp4 \
 $VIDEO_MAIN_H264 ! mux. \
 $AUDIO_EN_AAC ! mux.

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-1video-2audio.mp4 \
 $VIDEO_MAIN_H264 ! mux. \
 $AUDIO_EN_AAC ! mux. \
 $AUDIO_ES_AAC ! mux.

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2audio.mp4 \
 $AUDIO_EN_AAC ! mux. \
 $AUDIO_ES_AAC ! mux.

retry gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2video.mp4 \
 $VIDEO_MAIN_H264 ! mux. \
 $VIDEO_ALTERNATIVE_H264 ! mux.

retry gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio.mp4 \
 $VIDEO_MAIN_H264 ! mux. \
 $VIDEO_ALTERNATIVE_H264 ! mux. \
 $AUDIO_EN_AAC ! mux. \
 $AUDIO_ES_AAC ! mux.

gst-launch-1.0 webmmux name=mux ! filesink location="$ASSETS_DIR/"media-1video-1audio.webm \
 $VIDEO_MAIN_VP9 ! mux. \
 $AUDIO_EN_OPUS ! mux.

gst-launch-1.0 webmmux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio.webm \
 $VIDEO_MAIN_VP9 ! mux. \
 $VIDEO_ALTERNATIVE_VP9 ! mux. \
 $AUDIO_EN_OPUS ! mux. \
 $AUDIO_ES_OPUS ! mux.