package dev.floriang.trupp_app.car_app;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.Action;
import androidx.car.app.model.MessageTemplate;
import androidx.car.app.model.Template;

/**
 * Zeigt nach Status-Senden Erfolg oder Fehler.
 */
public class ConfirmScreen extends Screen {

    private final int status;
    private final boolean success;

    public ConfirmScreen(@NonNull CarContext carContext,
                         int status,
                         boolean success) {
        super(carContext);
        this.status = status;
        this.success = success;
    }

    @NonNull
    @Override
    public Template onGetTemplate() {
        String msg = success
                ? "Status " + status + " erfolgreich gesendet"
                : "Fehler beim Senden von Status " + status;

        return new MessageTemplate.Builder(msg)
                .setTitle("Bestätigung")
                .setHeaderAction(Action.BACK)
                .addAction(
                        new Action.Builder()
                                .setTitle("OK")
                                .setOnClickListener(() -> getScreenManager().pop())
                                .build()
                )
                .build();
    }
}
