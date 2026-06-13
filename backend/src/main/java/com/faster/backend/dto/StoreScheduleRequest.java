package com.faster.backend.dto;

import com.faster.backend.entity.StoreSchedule;
import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.time.LocalTime;

@Data
public class StoreScheduleRequest {

    // Not @NotNull here — bulk endpoint sends days
    // that might have null dayOfWeek if closed
    private StoreSchedule.DayOfWeek dayOfWeek;

    @JsonFormat(pattern = "HH:mm")
    private LocalTime openTime;

    @JsonFormat(pattern = "HH:mm")
    private LocalTime closeTime;

    private Boolean isClosed;
}