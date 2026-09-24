package io.github.thewwworm.gof2.android;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;

import com.chaquo.python.Python;
import com.chaquo.python.android.AndroidPlatform;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Comparator;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

/** Android SAF input and Chaquopy bridge for the shared, static Mac content reader. */
public final class AndroidImportPlugin extends GodotPlugin {
    private static final long MAX_SOURCE = 8L * 1024 * 1024 * 1024;
    private static final long HEADROOM = 512L * 1024 * 1024;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private volatile File activeCancel;
    private volatile String lastError = "";

    public AndroidImportPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "GoF2AndroidImport";
    }

    @UsedByGodot
    public boolean isImportRunning() {
        return running.get();
    }

    @UsedByGodot
    public String lastError() {
        return lastError;
    }

    @UsedByGodot
    public boolean startImport(String uriText, String dataPath, String statusPath, String cancelPath) {
        if (!running.compareAndSet(false, true)) {
            lastError = "A Mac import is already running";
            return false;
        }
        try {
            Context context = getActivity().getApplicationContext();
            Uri uri = Uri.parse(uriText);
            if (!"content".equals(uri.getScheme())) {
                throw new IllegalArgumentException("Choose your Mac app ZIP using the Android file picker");
            }
            File data = new File(dataPath).getCanonicalFile();
            File status = new File(statusPath).getCanonicalFile();
            File cancel = new File(cancelPath).getCanonicalFile();
            File internal = context.getFilesDir().getCanonicalFile();
            File external = context.getExternalFilesDir(null);
            if (!inside(data, internal) && (external == null || !inside(data, external.getCanonicalFile()))) {
                throw new IllegalArgumentException("Import storage must be private to this application");
            }
            File jobs = new File(data, "import-jobs").getCanonicalFile();
            if (!status.getParentFile().equals(jobs) || !cancel.getParentFile().equals(jobs)
                    || !status.getName().matches("[0-9]+-[0-9]+\\.json")
                    || !cancel.getName().equals(status.getName().replace(".json", ".cancel"))) {
                throw new IllegalArgumentException("Invalid private import job path");
            }
            if (!jobs.isDirectory() && !jobs.mkdirs()) {
                throw new IllegalStateException("Could not create the import progress folder");
            }
            String displayName = displayName(context.getContentResolver(), uri);
            if (!displayName.toLowerCase(Locale.ROOT).endsWith(".zip")) {
                throw new IllegalArgumentException("Choose a ZIP containing the original Mac .app");
            }
            File work = new File(jobs, status.getName() + ".work");
            if (!work.mkdir()) {
                throw new IllegalStateException("Could not create private import staging");
            }
            activeCancel = cancel;
            lastError = "";
            Thread worker = new Thread(() -> execute(context, uri, data, status, cancel, work),
                                       "gof2-android-import");
            worker.start();
            return true;
        } catch (Exception error) {
            running.set(false);
            activeCancel = null;
            lastError = error.getMessage() == null ? "Could not start the Android importer" : error.getMessage();
            return false;
        }
    }

    @UsedByGodot
    public boolean cancelImport() {
        File cancel = activeCancel;
        if (cancel == null) {
            lastError = "No Mac import is running";
            return false;
        }
        try {
            Files.write(cancel.toPath(), "cancel\n".getBytes(StandardCharsets.UTF_8));
            return true;
        } catch (Exception ignored) {
            lastError = "Could not request import cancellation";
            return false;
        }
    }

    private void execute(Context context, Uri uri, File data, File status, File cancel, File work) {
        try {
            File source = new File(work, "source.zip");
            copySource(context.getContentResolver(), uri, source, status, cancel);
            if (cancel.isFile()) {
                throw new InterruptedException("Import cancelled; the previous game and saves are unchanged");
            }
            if (!Python.isStarted()) {
                Python.start(new AndroidPlatform(context));
            }
            Python.getInstance().getModule("android_import_worker").callAttr(
                    "run", source.getAbsolutePath(), data.getAbsolutePath(),
                    status.getAbsolutePath(), cancel.getAbsolutePath());
        } catch (Exception error) {
            String message = error.getMessage() == null ? "Android importer stopped before finishing" : error.getMessage();
            writeStatus(status, cancel.isFile() ? "cancelled" : "failed", message);
        } finally {
            deleteWork(work);
            activeCancel = null;
            running.set(false);
        }
    }

    private static boolean inside(File path, File root) {
        return path.toPath().startsWith(root.toPath());
    }

    private static String displayName(ContentResolver resolver, Uri uri) {
        try (Cursor cursor = resolver.query(uri, new String[]{OpenableColumns.DISPLAY_NAME},
                                             null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                String value = cursor.getString(0);
                if (value != null) return value;
            }
        }
        return uri.getLastPathSegment() == null ? "" : uri.getLastPathSegment();
    }

    private static void copySource(ContentResolver resolver, Uri uri, File source,
                                   File status, File cancel) throws Exception {
        byte[] buffer = new byte[1024 * 1024];
        long count = 0;
        long last = 0;
        try (InputStream input = resolver.openInputStream(uri)) {
            if (input == null) throw new IllegalArgumentException("Cannot read the selected Mac app ZIP");
            try (FileOutputStream output = new FileOutputStream(source)) {
                int size;
                while ((size = input.read(buffer)) != -1) {
                    if (cancel.isFile()) {
                        throw new InterruptedException("Import cancelled; the previous game and saves are unchanged");
                    }
                    count += size;
                    if (count > MAX_SOURCE) {
                        throw new IllegalArgumentException("The Mac app ZIP exceeds the 8 GiB import limit");
                    }
                    if (source.getUsableSpace() < HEADROOM) {
                        throw new IllegalStateException("Import needs more free device storage");
                    }
                    output.write(buffer, 0, size);
                    long now = System.nanoTime();
                    if (now - last > 200_000_000L) {
                        last = now;
                        writeStatus(status, "working", "Copying the selected Mac app ZIP");
                    }
                }
                output.getFD().sync();
            }
        }
        if (count == 0) throw new IllegalArgumentException("The selected Mac app ZIP is empty");
    }

    private static void writeStatus(File path, String state, String message) {
        try {
            JSONObject record = new JSONObject();
            record.put("state", state);
            record.put("message", message);
            Path temp = new File(path.getParentFile(), path.getName() + ".tmp").toPath();
            Files.write(temp, (record.toString() + "\n").getBytes(StandardCharsets.UTF_8));
            try {
                Files.move(temp, path.toPath(), StandardCopyOption.ATOMIC_MOVE,
                           StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException ignored) {
                Files.move(temp, path.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (Exception ignored) {
            // A progress write never makes the installed game invalid.
        }
    }

    private static void deleteWork(File work) {
        try (java.util.stream.Stream<Path> paths = Files.walk(work.toPath())) {
            paths.sorted(Comparator.reverseOrder()).forEach(path -> {
                try { Files.deleteIfExists(path); } catch (Exception ignored) { }
            });
        } catch (Exception ignored) { }
    }
}
