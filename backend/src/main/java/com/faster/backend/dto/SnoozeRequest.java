package com.faster.backend.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class SnoozeRequest {

    @NotNull(message = "Hours is required")
    @Min(value = 1, message = "Minimum snooze is 1 hour")
    @Max(value = 24, message = "Maximum snooze is 24 hours")
    private Integer hours;
}