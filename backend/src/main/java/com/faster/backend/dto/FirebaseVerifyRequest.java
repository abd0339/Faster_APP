package com.faster.backend.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/**
 * Body for POST /api/auth/verify-firebase-phone
 *
 * Deliberately only accepts the ID token — never a phone
 * number from the client. The phone number used to look up
 * and verify the account comes ONLY from inside the
 * cryptographically-signed Firebase token itself (see
 * AuthService.verifyFirebasePhone()), so a client can never
 * claim to be verifying a phone number they don't actually
 * control.
 */
@Data
public class FirebaseVerifyRequest {

    @NotBlank(message = "Firebase ID token is required")
    private String idToken;
}