package com.faster.backend.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class RegisterRequest {

    // ─── Full Name ───────────────────────────────────
    @NotBlank(message = "Full name is required")
    @Size(min = 3, max = 50, message = "Full name must be between 3 and 50 characters")
    private String fullName;

    // ─── Phone ───────────────────────────────────────
    @NotBlank(message = "Phone number is required")
    @Pattern(
        regexp = "^\\+?[0-9]{7,15}$",
        message = "Phone number must be valid (e.g. +96170123456)"
    )
    private String phone;

    // ─── Email ───────────────────────────────────────
    @NotBlank(message = "Email is required")
    @Email(message = "Email must be a valid format (e.g. name@example.com)")
    private String email;

    // ─── Password ────────────────────────────────────
    @NotBlank(message = "Password is required")
    @Size(min = 8, message = "Password must be at least 8 characters")
    @Pattern(
        regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
        message = "Password must contain at least one uppercase letter, one lowercase letter, and one number"
    )
    private String password;

    // ─── Role ────────────────────────────────────────
    // ─── Role ────────────────────────────────────────
    @NotBlank(message = "Role is required")
    @Pattern(
        regexp = "^(MERCHANT|DRIVER|CUSTOMER|ADMIN)$",
         message = "Role must be MERCHANT, DRIVER, CUSTOMER, or ADMIN"
    )
    private String role;
}