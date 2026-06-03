package com.faster.backend.entity;

import jakarta.persistence.*;
import jakarta.validation.constraints.Email;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
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
        CUSTOMER
    }

    public enum DriverMode {
        PEOPLE,
        PACKAGE,
        HYBRID
    }
}