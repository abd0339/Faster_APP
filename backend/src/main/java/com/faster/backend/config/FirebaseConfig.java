package com.faster.backend.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import java.io.FileInputStream;
import java.io.IOException;

/**
 * Initializes the Firebase Admin SDK once at startup.
 *
 * Used ONLY to verify Firebase Phone Auth ID tokens
 * server-side after Flutter completes phone verification
 * client-side via Firebase. This is an ADDITIONAL,
 * independent verification path alongside the existing
 * Twilio OTP flow — neither replaces the other. A user can
 * verify their phone via whichever completes first; both
 * mark the same isPhoneVerified flag. See AuthService.
 *
 * Deliberately NOT wired into login/registration in any way
 * that could block those flows if Firebase is ever
 * unreachable — if the service account file is missing or
 * invalid, this logs an error and the app keeps running
 * normally; only the NEW firebase-verify endpoint would fail,
 * not registration, login, or the existing Twilio OTP path.
 */
@Slf4j
@Configuration
public class FirebaseConfig {

    @Value("${firebase.service-account-path:}")
    private String serviceAccountPath;

    @PostConstruct
    public void init() {
        if (serviceAccountPath == null || serviceAccountPath.isBlank()) {
            log.warn("⚠️ firebase.service-account-path not set — "
                    + "Firebase phone verification endpoint will not work. "
                    + "Registration, login, and Twilio OTP are unaffected.");
            return;
        }

        try {
            if (FirebaseApp.getApps().isEmpty()) {
                FileInputStream serviceAccount =
                        new FileInputStream(serviceAccountPath);

                FirebaseOptions options = FirebaseOptions.builder()
                        .setCredentials(GoogleCredentials.fromStream(serviceAccount))
                        .build();

                FirebaseApp.initializeApp(options);
                log.info("✅ Firebase Admin SDK initialized successfully");
            }
        } catch (IOException e) {
            log.error("❌ Failed to initialize Firebase Admin SDK — "
                    + "check firebase.service-account-path is correct and "
                    + "readable. Firebase phone verification will not work "
                    + "until this is fixed. Error: {}", e.getMessage());
        }
    }
}