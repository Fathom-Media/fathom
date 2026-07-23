#include <unistd.h>

#include "my_application.h"

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  // The Flutter GTK embedder can segfault while its GObjects are finalized on
  // exit — a teardown race in the engine, and worse in an AppImage where GTK
  // loads bundled immodules (im-wayland). The process is exiting anyway and the
  // Dart side has already torn down (players disposed, live streams closed, mpv
  // released on window close), so end now and skip the crashy C++/GObject
  // destructors instead of dumping core. `_exit` runs no atexit/static dtors.
  _exit(status);
  return status;  // unreachable; keeps the compiler happy
}
