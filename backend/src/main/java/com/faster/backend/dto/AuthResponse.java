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

    private String token;
    private String role;
    private String fullName;
    private String email;
    private String phone;
    private Boolean isBlocked;
    private Boolean isEmailVerified;
    private String message;
}