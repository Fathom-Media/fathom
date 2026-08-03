#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <limits.h>
#include <signal.h>
#include <termios.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"

// The terminal's settings as they were at launch, saved when the app is started
// from a shell (dev runs). libmpv puts the TTY into raw / no-echo mode for its
// own input handling; on a graceful exit it restores it, but this app hard-exits
// on close (see on_window_delete), which would skip that and leave the shell
// unusable (no echo, needs `reset`). We restore this snapshot just before
// exiting so the terminal is handed back sane.
static struct termios g_saved_termios;
static bool g_termios_saved = false;

static void save_terminal_state() {
  if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &g_saved_termios) == 0) {
    g_termios_saved = true;
  }
}

static void restore_terminal_state() {
  if (!g_termios_saved) return;
  // When launched backgrounded (dev: `./fathom &`), this process isn't in the
  // terminal's foreground group, so tcsetattr would raise SIGTTOU and, by
  // default, suspend us instead of applying the change. Ignore it around the
  // call so the restore actually lands.
  void (*prev)(int) = signal(SIGTTOU, SIG_IGN);
  tcsetattr(STDIN_FILENO, TCSANOW, &g_saved_termios);
  signal(SIGTTOU, prev);
}

// Point the window/taskbar icon at the bundled app icon. The asset ships next
// to the executable under data/flutter_assets/, so resolve it relative to the
// running binary rather than a hard-coded install path.
static void set_app_icon(GtkWindow* window) {
  char exe[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (len <= 0) return;
  exe[len] = '\0';
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* icon = g_build_filename(
      dir, "data", "flutter_assets", "assets", "icon", "fathom.png", nullptr);
  g_autoptr(GError) error = nullptr;
  if (!gtk_window_set_icon_from_file(window, icon, &error)) {
    g_warning("Failed to load app icon %s: %s", icon, error->message);
    return;
  }
  // Also make it the default so any secondary windows inherit it.
  gtk_window_set_default_icon_from_file(icon, nullptr);
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// GTK-thread watchdog: hard-exit no matter what the Dart side is doing.
static gboolean force_exit_cb(gpointer data) {
  restore_terminal_state();
  _exit(0);
  return G_SOURCE_REMOVE;
}

// The user clicked the window's close button (or Alt+F4 / the compositor).
//
// The Dart side (window_manager -> onWindowClose) does the graceful-ish
// teardown and then SIGKILLs the process, but that path runs on the Dart UI
// thread's event loop, which is routinely jammed at exactly this moment (app
// startup, active video/audio playback). While it's jammed the close event
// can't even be delivered, so the window sits there frozen for seconds.
//
// This handler runs on the GTK main-loop thread instead, which is not blocked
// by Dart work, so it fires the instant the user asks to close. It arms a
// short watchdog that hard-exits regardless of the Dart loop's state, so the
// window always disappears within a blink. Returning FALSE lets window_manager
// still intercept (it prevents the default destroy that would otherwise race
// the engine shutdown and crash) and lets the Dart fast path release the Live
// TV tuner / SyncPlay socket when its loop is free — whichever kill lands first
// wins.
static gboolean on_window_delete(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  g_timeout_add(200, force_exit_cb, nullptr);
  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  // Snapshot the terminal now, before libmpv (created later, from Dart) puts it
  // into raw mode, so the hard-exit path can hand a sane terminal back.
  save_terminal_state();

  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  // Fathom draws its own seamless title bar. Give GTK an empty, zero-height
  // titlebar: this forces client-side decorations so the compositor (e.g. KWin)
  // does NOT draw its own server-side title bar, while keeping CSD resize
  // borders/shadow.
  gtk_window_set_title(window, "fathom");
  GtkWidget* empty_titlebar = gtk_fixed_new();
  gtk_widget_set_size_request(empty_titlebar, 0, 0);
  gtk_widget_show(empty_titlebar);
  gtk_window_set_titlebar(window, empty_titlebar);

  gtk_window_set_default_size(window, 1280, 720);
  set_app_icon(window);

  // Guarantee a snappy close even when the Dart loop is jammed (see
  // on_window_delete). Connected before the plugins so it runs ahead of
  // window_manager's own delete-event handler.
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete),
                   nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
