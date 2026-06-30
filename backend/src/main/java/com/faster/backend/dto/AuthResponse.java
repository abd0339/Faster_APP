package com.faster.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AuthResponse {

    // ─── JWT token ────────────────────────────────────
    // NULL when requiresOtp = true (user not fully authed yet)
    // Set after successful OTP verification
    private String token;

    // ─── User info ────────────────────────────────────
    private String role;
    private String fullName;
    private String email;
    private String phone;

    // ─── Account flags ────────────────────────────────
    private Boolean isBlocked;
    private Boolean isEmailVerified;
    private Boolean isPhoneVerified;

    // ─── OTP gate flag ────────────────────────────────
    // true  → Flutter must show OTP screen (no token yet)
    // false → Login complete, token is valid
    private Boolean requiresOtp;

    // ─── Human-readable message ───────────────────────
    private String message;
}