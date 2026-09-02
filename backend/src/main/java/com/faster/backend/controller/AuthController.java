package com.faster.backend.controller;

import com.faster.backend.dto.AuthResponse;
import com.faster.backend.dto.LoginRequest;
import com.faster.backend.dto.RegisterRequest;
import com.faster.backend.service.AuthService;
import com.faster.backend.service.TokenBlacklistService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final TokenBlacklistService tokenBlacklistService;

    // ─── POST /api/auth/register ──────────────────────
    // Returns requiresOtp=true, no token
    // Flutter shows OTP screen next
    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(
            @Valid @RequestBody RegisterRequest request) {
        return ResponseEntity.ok(authService.register(request));
    }

    // ─── POST /api/auth/login ─────────────────────────
    // Returns requiresOtp=true if phone not verified
    // Returns token if fully verified
    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(
            @Valid @RequestBody LoginRequest request) {
        return ResponseEntity.ok(authService.login(request));
    }

    // ─── POST /api/auth/verify-otp ───────────────────
    // User submits the 6-digit code they received
    // On success: returns JWT token + requiresOtp=false
    //
    // Body: { "phone": "+96170000001", "code": "482917" }
    @PostMapping("/verify-otp")
    public ResponseEntity<AuthResponse> verifyOtp(
            @Valid @RequestBody OtpRequest request) {
        return ResponseEntity.ok(
            authService.verifyOtp(request.getPhone(),
                                  request.getCode()));
    }

    // ─── POST /api/auth/resend-otp ────────────────────
    // User requests a fresh OTP (expired or not received)
    //
    // Body: { "phone": "+96170000001" }
    // Body (choosing a channel):
    //   { "phone": "+96170000001", "channel": "SMS" }
    //   channel is optional — omit or send "WHATSAPP" for
    //   the default. This is what powers the "Resend via
    //   SMS instead" button on the OTP screen.
    @PostMapping("/resend-otp")
    public ResponseEntity<AuthResponse> resendOtp(
            @Valid @RequestBody ResendOtpRequest request) {
        return ResponseEntity.ok(
            authService.resendOtp(request.getPhone(), request.getChannel()));
    }

    // ─── POST /api/auth/logout ────────────────────────
    // M5: revokes the caller's token so it stops working
    // immediately, instead of remaining valid for up to ten more
    // days. The Flutter app already clears local storage on
    // logout; this makes the server agree.
    //
    // Deliberately tolerant: a missing or malformed header still
    // returns 200. Logout should never fail — the client is
    // signing out either way, and an error here would just leave
    // the user stuck on a screen they're trying to leave.
    @PostMapping("/logout")
    public ResponseEntity<?> logout(HttpServletRequest request) {
        String authHeader = request.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            tokenBlacklistService.blacklist(authHeader.substring(7));
        }
        return ResponseEntity.ok(
                java.util.Map.of("message", "Signed out successfully"));
    }

    // ─── Inner DTOs ───────────────────────────────────
    @Data
    public static class OtpRequest {

        @NotBlank(message = "Phone is required")
        private String phone;

        @NotBlank(message = "Code is required")
        @Pattern(regexp = "^[0-9]{6}$",
                 message = "Code must be exactly 6 digits")
        private String code;
    }

    @Data
    public static class ResendOtpRequest {

        @NotBlank(message = "Phone is required")
        private String phone;

        // Optional — "WHATSAPP" (default) or "SMS"
        private String channel;
    }
}