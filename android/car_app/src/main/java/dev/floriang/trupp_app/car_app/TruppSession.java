package dev.floriang.trupp_app.car_app;

import android.content.Intent;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.Session;

public class TruppSession extends Session {

    @NonNull
    @Override
    public Screen onCreateScreen(@NonNull Intent intent) {
        CarContext ctx = getCarContext();
        return new StatusSelectionScreen(ctx);
    }
}
