#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <gst/app/gstappsink.h>
#include <unistd.h>
#include <string.h>
#include <cairo.h>
#include <stdio.h>

#ifndef M_PI
    #define M_PI 3.14159265358979323846
#endif

const cairo_format_t frame_format = CAIRO_FORMAT_RGB24;
const int frame_width = 640;
const int frame_height = 480;
const int fps = 30;
const int total_frames = fps * 20;

GMainLoop* loop;

#define WHITE 1.0, 1.0, 1.0
#define GRAY 0.5, 0.5, 0.5
#define BLACK 0.0, 0.0, 0.0

int trackNumber;

GstBuffer* draw_frame(int frame_number)
{
    cairo_surface_t *surface;
    cairo_t *cr;

    surface = cairo_image_surface_create (frame_format, frame_width, frame_height);
    cr = cairo_create (surface);

    // Fill the background
    if (trackNumber == 0)
        cairo_set_source_rgb (cr, 0.0, 0.0, 0.0); // Black
    else
        cairo_set_source_rgb (cr, 0.0, 0.0, 0.7); // Blue
    cairo_rectangle (cr, 0, 0, frame_width, frame_height);
    cairo_fill (cr);

    // Fill the circle background
    const double cx = frame_width / 2;
    const double cy = frame_height * 80 / 240;
    const double r = frame_height * 60 / 240;
    cairo_set_source_rgb(cr, GRAY);
    cairo_arc(cr, cx, cy, r, 0, 2 * M_PI);
    cairo_fill(cr);

    // Fill the pie
    double frame_progress = (double) (frame_number % fps) / fps;
    cairo_set_source_rgb(cr, WHITE);
    cairo_move_to(cr, cx, cy);
    cairo_arc(cr, cx, cy, r, -M_PI / 2, -M_PI / 2 + (frame_progress * 2 * M_PI));
    cairo_close_path(cr);
    cairo_fill(cr);

    // Print frame timestamp
    char text[80];
    snprintf(text, sizeof(text), "%.9f", (double) frame_number / fps);
    cairo_set_source_rgb(cr, WHITE);
    cairo_select_font_face(cr, "DejaVu Sans Mono", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, frame_height * 24 / 240);
    cairo_text_extents_t te;
    cairo_text_extents(cr, text, &te);
    cairo_move_to(cr, (frame_width - te.width) / 2, (frame_height * 160 / 240) + te.height);
    cairo_show_text(cr, text);

    // Wrap in a GstBuffer
    cairo_destroy (cr);
//    cairo_surface_write_to_png(surface, "/tmp/surf.png");
    const size_t surface_size = cairo_image_surface_get_stride(surface) * frame_width * frame_height;
    GstBuffer* buf = gst_buffer_new_wrapped_full(GST_MEMORY_FLAG_READONLY, cairo_image_surface_get_data(surface),
                                       surface_size, 0, surface_size, surface, (GDestroyNotify) cairo_surface_destroy);
    GST_BUFFER_PTS(buf) = gst_util_uint64_scale(frame_number, GST_SECOND, fps);
    return buf;
}

static void
print_error_message (GstMessage * msg)
{
    GError *err = NULL;
    gchar *name, *debug = NULL;

    name = gst_object_get_path_string (msg->src);
    gst_message_parse_error (msg, &err, &debug);

    g_printerr ("ERROR: from element %s: %s\n", name, err->message);
    if (debug != NULL)
        g_printerr ("Additional debug info:\n%s\n", debug);

    g_clear_error (&err);
    g_free (debug);
    g_free (name);
}

static GstBusSyncReply
bus_sync_handler (GstBus * bus, GstMessage * message, gpointer data)
{
    GstElement *pipeline = (GstElement *) data;

    switch (GST_MESSAGE_TYPE (message)) {
    case GST_MESSAGE_ERROR:{
        /* dump graph on error */
        GST_DEBUG_BIN_TO_DOT_FILE_WITH_TS (GST_BIN (pipeline),
                                           GST_DEBUG_GRAPH_SHOW_ALL, "error");

        print_error_message (message);

        /* we have an error */
        exit(1);
    }
    case GST_MESSAGE_EOS:
        g_main_loop_quit(loop);
    default:
        break;
    }
    return GST_BUS_PASS;
}

int main(int argc, char** argv) {
    gst_init(&argc, &argv);

    if (argc < 3) {
        fprintf(stderr, "Usage: ./gen-video <track number> {mp4|webm|xv}\n");
        return 1;
    }
    char* endptr = NULL;
    trackNumber = strtol(argv[1], &endptr, 10);
    if (argv[1][0] == '\0' || *endptr != '\0') {
        fprintf(stderr, "<track number> must be an integer.\n");
        return 1;
    }
    if (trackNumber > 2) {
        fprintf(stderr, "Invalid track number.\n");
        return 1;
    }

    const char* pipeline_string;
    if (!strcmp(argv[2], "xv"))
        pipeline_string = "appsrc format=time name=src ! videoconvert name=vc ! xvimagesink name=s";
    else if (!strcmp(argv[2], "mp4"))
        pipeline_string = "appsrc format=time name=src ! videoconvert name=vc ! x264enc ! "
            "video/x-h264, profile=main ! mp4mux ! "
            "filesink location=video.mp4";
    else if (!strcmp(argv[2], "webm"))
        pipeline_string = "appsrc format=time name=src ! videoconvert name=vc ! vp9enc ! "
            "video/x-vp9 ! webmmux ! "
            "filesink location=video.webm";
    else {
        fprintf(stderr, "Invalid output format requested.\n");
        return 1;
    }

    loop = g_main_loop_new (NULL, FALSE);

    GError* error = NULL;
    GstElement *pipeline = gst_parse_launch(pipeline_string, &error);
    g_assert_no_error(error);

    GstBus *bus = gst_pipeline_get_bus(GST_PIPELINE(pipeline));
    gst_bus_set_sync_handler(bus, bus_sync_handler, pipeline, NULL);

    GstElement *src = gst_bin_get_by_name(GST_BIN(pipeline), "src");

    GstCaps* caps = gst_caps_new_simple ("video/x-raw",
                                         "format", G_TYPE_STRING, "BGRx", // little endian only
                                         "framerate", GST_TYPE_FRACTION, fps, 1,
                                         "pixel-aspect-ratio", GST_TYPE_FRACTION, 1, 1,
                                         "width", G_TYPE_INT, frame_width,
                                         "height", G_TYPE_INT, frame_height,
                                         NULL);
    gst_app_src_set_caps(GST_APP_SRC(src), caps);
    for (int i = 0; i < total_frames; i++)
        gst_app_src_push_buffer(GST_APP_SRC(src), draw_frame(i));
    gst_app_src_end_of_stream(GST_APP_SRC(src));

    gst_element_set_state(pipeline, GST_STATE_PLAYING);
    g_main_loop_run(loop);

    g_object_unref(bus);
    g_object_unref(pipeline);
    gst_caps_unref(caps);

    return 0;
}

