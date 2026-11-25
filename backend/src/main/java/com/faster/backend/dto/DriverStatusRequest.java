package com.faster.backend.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
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

    // FIX: this DTO backs /api/driver/online and /api/driver/mode, which
    // only had @NotNull here — an out-of-range value (e.g. lat=999) went
    // straight through to LocationService with no range check, unlike
    // DriverLocationRequest (the location-ping endpoint), which already
    // has both. Same range the rest of the codebase uses for lat/lng.
    @NotNull(message = "Latitude is required")
    @DecimalMin(value = "-90.0", message = "Invalid latitude")
    @DecimalMax(value = "90.0", message = "Invalid latitude")
    private Double lat;

    @NotNull(message = "Longitude is required")
    @DecimalMin(value = "-180.0", message = "Invalid longitude")
    @DecimalMax(value = "180.0", message = "Invalid longitude")
    private Double lng;
}