#!/bin/bash

# Audio 1: AudioTrack.kind = "main"; AudioTrack.language = "en"
# Audio 2: AudioTrack.kind = "alternative"; AudioTrack.language = "es"

# Video 1: VideoTrack.kind = "main" (black background)
# Video 2: VideoTrack.kind = "alternative" (blue background)

set -eu
DIR="$(realpath "$(dirname "$0")")"
ASSETS_DIR="$(realpath $DIR/assets)"
INGREDIENTS_DIR="$(realpath $DIR/assets-ingredients)"

set -x
mkdir -p "$ASSETS_DIR"
cd "$INGREDIENTS_DIR"

if [ ! -f "video-alternative.webm" ]; then
  gcc $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-app-1.0 cairo) gen-video.c -o gen-video
  ./gen-video 0 mp4 && mv video.mp4 video-main.mp4
  ./gen-video 1 mp4 && mv video.mp4 video-alternative.mp4
  ./gen-video 0 webm && mv video.webm video-main.webm
  ./gen-video 1 webm && mv video.webm video-alternative.webm
fi

AUDIO_EN_AAC='filesrc location=counting-en.flac ! flacparse ! flacdec ! audioconvert ! avenc_aac ! taginject tags="language-code=en"'
AUDIO_ES_AAC='filesrc location=counting-es.flac ! flacparse ! flacdec ! audioconvert ! avenc_aac ! taginject tags="language-code=es"'

VIDEO_MAIN_H264="filesrc location=video-main.mp4 ! qtdemux name=videodemuxmain videodemuxmain.video_0"
VIDEO_ALTERNATIVE_H264="filesrc location=video-alternative.mp4 ! qtdemux name=videodemuxalternative videodemuxalternative.video_0"

AUDIO_EN_OPUS='filesrc location=counting-en.flac ! flacparse ! flacdec ! audioconvert ! audioresample ! opusenc ! taginject tags="language-code=en"'
AUDIO_ES_OPUS='filesrc location=counting-es.flac ! flacparse ! flacdec ! audioconvert ! audioresample ! opusenc ! taginject tags="language-code=es"'

VIDEO_MAIN_VP9="filesrc location=video-main.webm ! matroskademux name=videodemuxmain videodemuxmain.video_0"
VIDEO_ALTERNATIVE_VP9="filesrc location=video-alternative.webm ! matroskademux name=videodemuxalternative videodemuxalternative.video_0"

TEXT_EN='filesrc location='$ASSETS_DIR'/en.subviewer ! subparse ! taginject tags="language-code=en"'
TEXT_ES='filesrc location='$ASSETS_DIR'/es.subviewer ! subparse ! taginject tags="language-code=es"'

function retry() {
  # There is some flakiness in mp4mux when handling several video tracks. Try again if it fails.
  local attempts=0
  while ! "$@"; do
    attempts=$(($attempts + 1))
    if [ $attempts -ge 10 ]; then
      echo "Failed too many times, giving up."
      exit 1
    fi
  done
}

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-1video-1audio.mp4 \
 $VIDEO_MAIN_H264 ! mux.video_0 \
 $AUDIO_EN_AAC ! mux.

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-1video-2audio.mp4 \
 $VIDEO_MAIN_H264 ! mux.video_0 \
 $AUDIO_EN_AAC ! mux.audio_0 \
 $AUDIO_ES_AAC ! mux.audio_1

gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2audio.mp4 \
 $AUDIO_EN_AAC ! mux.audio_0 \
 $AUDIO_ES_AAC ! mux.audio_1

retry gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2video.mp4 \
 $VIDEO_MAIN_H264 ! mux.video_0 \
 $VIDEO_ALTERNATIVE_H264 ! mux.video_1

retry gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio.mp4 \
 $VIDEO_MAIN_H264 ! mux.video_0 \
 $VIDEO_ALTERNATIVE_H264 ! mux.video_1 \
 $AUDIO_EN_AAC ! mux.audio_0 \
 $AUDIO_ES_AAC ! mux.audio_1

retry gst-launch-1.0 mp4mux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio-2text.mp4 \
 $VIDEO_MAIN_H264 ! mux.video_0 \
 $VIDEO_ALTERNATIVE_H264 ! mux.video_1 \
 $AUDIO_EN_AAC ! mux.audio_0 \
 $AUDIO_ES_AAC ! mux.audio_1 \
 $TEXT_EN ! mux.subtitle_0 \
 $TEXT_ES ! mux.subtitle_1

gst-launch-1.0 webmmux name=mux ! filesink location="$ASSETS_DIR/"media-1video-1audio.webm \
 $VIDEO_MAIN_VP9 ! mux.video_0 \
 $AUDIO_EN_OPUS ! mux.audio_0

gst-launch-1.0 webmmux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio.webm \
 $VIDEO_MAIN_VP9 ! mux.video_0 \
 $VIDEO_ALTERNATIVE_VP9 ! mux.video_1 \
 $AUDIO_EN_OPUS ! mux.audio_0 \
 $AUDIO_ES_OPUS ! mux.audio_1

gst-launch-1.0 webmmux name=mux ! filesink location="$ASSETS_DIR/"media-2video-2audio-2text.webm \
 $VIDEO_MAIN_VP9 ! mux.video_0 \
 $VIDEO_ALTERNATIVE_VP9 ! mux.video_1 \
 $AUDIO_EN_OPUS ! mux.audio_0 \
 $AUDIO_ES_OPUS ! mux.audio_1 \
 $TEXT_EN ! mux.subtitle_0 \
 $TEXT_ES ! mux.subtitle_1

# MSE assets

gst-launch-1.0 mp4mux name=mux ! filesink location=audio-en.mp4 \
 $AUDIO_EN_AAC ! mux.audio_0

gst-launch-1.0 mp4mux name=mux ! filesink location=audio-es.mp4 \
 $AUDIO_ES_AAC ! mux.audio_0

cd "$DIR"

MakeFragmentedMP4() {
  # Usage: MakeFragmentedMP4 <output-path> {MP4Box arguments} ...
  # All paths given to MP4Box must be absolute.
    output_name="$1"
    shift
    mkdir -p tmp-mp4box
    pushd tmp-mp4box
    MP4Box "$@" out.mp4
    popd
    mv tmp-mp4box/out_dashinit.mp4 "$output_name"
}

MakeFragmentedMP4 "$ASSETS_DIR/mse-video-main.mp4" -dash 5000 -add "$INGREDIENTS_DIR/video-main.mp4"
MakeFragmentedMP4 "$ASSETS_DIR/mse-video-main-audio-en-text-en.mp4" -dash 5000 -add "$INGREDIENTS_DIR/video-main.mp4" \
  -add "$INGREDIENTS_DIR/audio-en.mp4" -add "$ASSETS_DIR/en.vtt":FMT=VTT:lang=en
MakeFragmentedMP4 "$ASSETS_DIR/mse-audio-en.mp4" -dash 5000 -add "$INGREDIENTS_DIR/audio-en.mp4"
MakeFragmentedMP4 "$ASSETS_DIR/mse-audio-es.mp4" -dash 5000 -add "$INGREDIENTS_DIR/audio-es.mp4"
MakeFragmentedMP4 "$ASSETS_DIR/mse-audio-en-es.mp4" -dash 5000 -add "$INGREDIENTS_DIR/audio-en.mp4" -add "$INGREDIENTS_DIR/audio-es.mp4"
MakeFragmentedMP4 "$ASSETS_DIR/mse-video-main-audio-en.mp4" -dash 5000 -add "$INGREDIENTS_DIR/video-main.mp4" -add "$INGREDIENTS_DIR/audio-en.mp4"
MakeFragmentedMP4 "$ASSETS_DIR/mse-text-en.mp4" -dash 5000 -add "$ASSETS_DIR/en.vtt":FMT=VTT:lang=en