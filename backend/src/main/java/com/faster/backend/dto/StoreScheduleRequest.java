package com.faster.backend.dto;

import com.faster.backend.entity.StoreSchedule;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.time.LocalTime;

@Data
public class StoreScheduleRequest {

    @NotNull(message = "Day of week is required")
    private StoreSchedule.DayOfWeek dayOfWeek;

    private LocalTime openTime;
    private LocalTime closeTime;

    // true = store closed this day entirely
    private Boolean isClosed;
}