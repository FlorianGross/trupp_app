package dev.floriang.trupp_app.car_app;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

/**
 * Baut URL wie in Flutter:
 *   {protocol}://{host}:{port}/{token}/setstatus?issi=...&status=...
 * Liest Werte aus Flutter SharedPreferences.
 */
public class EdpClient {

    private static final String TAG = "EdpClient";
    private final Context context;
    private final OkHttpClient http = new OkHttpClient();

    public EdpClient(Context context) {
        this.context = context.getApplicationContext();
    }

    private static class Config {
        final String protocol;
        final String host;
        final int port;
        final String token;
        final String issi;

        Config(String protocol, String host, int port, String token, String issi) {
            this.protocol = protocol;
            this.host = host;
            this.port = port;
            this.token = token;
            this.issi = issi;
        }
    }

    private Config loadConfig() {
        // Flutter shared_preferences auf Android:
        // Datei "FlutterSharedPreferences"
        // Keys gespeichert als "flutter.<key>"
        SharedPreferences prefs =
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);

        String protocol = prefs.getString("flutter.protocol", null);
        String server   = prefs.getString("flutter.server", null);   // host[:port]
        String token    = prefs.getString("flutter.token", null);
        String issi     = prefs.getString("flutter.issi", null);

        if (protocol == null || server == null || token == null || issi == null) {
            Log.e(TAG, "Missing config (protocol/server/token/issi)");
            return null;
        }

        String host = server;
        int port = "https".equalsIgnoreCase(protocol) ? 443 : 80;

        int idx = server.indexOf(':');
        if (idx > 0 && idx < server.length() - 1) {
            host = server.substring(0, idx);
            try {
                port = Integer.parseInt(server.substring(idx + 1));
            } catch (NumberFormatException ignore) { /* fallback */ }
        }

        return new Config(protocol, host, port, token, issi);
    }

    public boolean sendStatus(int status) {
        try {
            Config cfg = loadConfig();
            if (cfg == null) {
                return false;
            }

            String url = cfg.protocol + "://" + cfg.host + ":" + cfg.port
                    + "/" + cfg.token + "/setstatus"
                    + "?issi=" + URLEncoder.encode(cfg.issi, StandardCharsets.UTF_8.name())
                    + "&status=" + URLEncoder.encode(String.valueOf(status), StandardCharsets.UTF_8.name());

            Request req = new Request.Builder()
                    .url(url)
                    .get()
                    .build();

            Response resp = http.newCall(req).execute();
            int code = resp.code();
            resp.close();

            Log.d(TAG, "sendStatus(" + status + ") -> HTTP " + code);
            return code >= 200 && code < 300;

        } catch (Exception e) {
            Log.e(TAG, "sendStatus failed", e);
            return false;
        }
    }
}
