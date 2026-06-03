package com.faster.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class LoginRequest {

    // ─── Can login with email OR phone ───────────────
    // Just send one of them, the other can be null
    private String email;

    private String phone;

    // ─── Password ────────────────────────────────────
    @NotBlank(message = "Password is required")
    @Size(min = 8, message = "Password must be at least 8 characters")
    private String password;
}