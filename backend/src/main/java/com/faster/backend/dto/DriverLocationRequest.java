package com.faster.backend.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class DriverLocationRequest {

    @NotNull(message = "Latitude is required")
    @DecimalMin(value = "-90.0",
                message = "Invalid latitude")
    @DecimalMax(value = "90.0",
                message = "Invalid latitude")
    private Double lat;

    @NotNull(message = "Longitude is required")
    @DecimalMin(value = "-180.0",
                message = "Invalid longitude")
    @DecimalMax(value = "180.0",
                message = "Invalid longitude")
    private Double lng;

    // PEOPLE | PACKAGE | HYBRID
    private String mode;
}