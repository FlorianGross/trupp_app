package dev.floriang.trupp_app.car_app;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.Action;
import androidx.car.app.model.GridItem;
import androidx.car.app.model.GridTemplate;
import androidx.car.app.model.ItemList;
import androidx.car.app.model.Template;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Hauptbildschirm in Android Auto: Grid 0-9
 */
public class StatusSelectionScreen extends Screen {

    private final Map<Integer, String> statusMap = new LinkedHashMap<>();
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    public StatusSelectionScreen(@NonNull CarContext carContext) {
        super(carContext);

        statusMap.put(1, "Einsatzbereit Funk");
        statusMap.put(2, "Wache");
        statusMap.put(3, "Auftrag Angenommen");
        statusMap.put(4, "Ziel erreicht");
        statusMap.put(5, "Sprechwunsch");
        statusMap.put(6, "Nicht Einsatzbereit");
        statusMap.put(7, "Transport");
        statusMap.put(8, "Ziel Erreicht");
        statusMap.put(9, "Sonstiges");
        statusMap.put(0, "Dringend");
    }

    @NonNull
    @Override
    public Template onGetTemplate() {
        ItemList.Builder listBuilder = new ItemList.Builder();

        for (Map.Entry<Integer, String> e : statusMap.entrySet()) {
            final int code = e.getKey();
            final String desc = e.getValue();

            GridItem item = new GridItem.Builder()
                    .setTitle(String.valueOf(code))
                    .setText(desc)
                    .setOnClickListener(() -> onStatusClicked(code))
                    .build();

            listBuilder.addItem(item);
        }

        return new GridTemplate.Builder()
                .setTitle("Status wählen")
                .setHeaderAction(Action.APP_ICON)
                .setSingleList(listBuilder.build())
                .build();
    }

    private void onStatusClicked(final int status) {
        io.submit(() -> {
            boolean ok = new EdpClient(getCarContext()).sendStatus(status);

            main.post(() -> {
                getScreenManager().push(
                        new ConfirmScreen(getCarContext(), status, ok)
                );
            });
        });
    }
}
