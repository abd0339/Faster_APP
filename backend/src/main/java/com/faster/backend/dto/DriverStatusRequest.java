package com.faster.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import lombok.Data;

@Data
public class DriverStatusRequest {

    @NotBlank(message = "Mode is required")
    @Pattern(
        regexp = "^(PEOPLE|PACKAGE|HYBRID)$",
        message = "Mode must be PEOPLE, PACKAGE, or HYBRID"
    )
    private String mode;

    @NotNull(message = "Latitude is required")
    private Double lat;

    @NotNull(message = "Longitude is required")
    private Double lng;
}