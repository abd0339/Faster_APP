package com.faster.backend.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.validation.constraints.Email;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties({ "hibernateLazyInitializer",
        "handler", "password" })
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Identity ───────────────────────────────────
    @Column(nullable = false)
    private String fullName;

    @Column(nullable = false, unique = true)
    private String phone;

    @Email
    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    // ─── Role ────────────────────────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    // ─── Account Status ──────────────────────────────
    @Builder.Default
    private Boolean isActive = true;

    // Is email verified?
    @Builder.Default
    private Boolean isEmailVerified = false;

    // Is phone verified?
    @Builder.Default
    private Boolean isPhoneVerified = false;

    // ─── Driver-specific fields ──────────────────────
    @Builder.Default
    private BigDecimal debtAmount = BigDecimal.ZERO;

    @Builder.Default
    private Boolean isBlocked = false;

    @Enumerated(EnumType.STRING)
    private DriverMode driverMode;

    @Builder.Default
    private Boolean isOnline = false;

    // ─── Driver Verification (Phase 2) ──────────────────
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private DriverVerificationStatus verificationStatus = DriverVerificationStatus.PENDING;

    // Vehicle info
    private String vehicleType; // MOTO / CAR / TOKTOK
    private String vehiclePlate;

    // Document URLs (uploaded images)
    private String driverPhotoUrl;
    private String nationalIdUrl;
    private String vehiclePaperUrl;

    // ─── Timestamps ──────────────────────────────────
    @Column(updatable = false)
    private LocalDateTime createdAt;

    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // ─── Enums ───────────────────────────────────────
    public enum Role {
        MERCHANT,
        DRIVER,
        CUSTOMER,
        ADMIN
    }

    public enum DriverMode {
        PEOPLE,
        PACKAGE,
        HYBRID
    }

    public enum DriverVerificationStatus {
    PENDING,     // Just registered, docs not submitted
    SUBMITTED,   // Driver uploaded docs, waiting admin
    APPROVED,    // Admin approved → can go online
    REJECTED     // Admin rejected → needs to resubmit
    }
}