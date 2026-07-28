package com.faster.backend.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/** Body for POST /api/devices/register */
@Data
public class DeviceTokenRequest {

    @NotBlank(message = "FCM token is required")
    private String fcmToken;

    // ANDROID / IOS / WEB — informational only
    private String platform;
}