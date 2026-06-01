package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

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

    // ─── Identity ──────────────────────────────────
    @Column(nullable = false, unique = true)
    private String phone;

    // Email is optional but recommended for receipts & recovery
    @Column(unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(nullable = false)
    private String fullName;

    // ─── Role: MERCHANT | DRIVER | CUSTOMER ────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    // ─── Driver-specific fields ─────────────────────
    // Current debt the driver owes the platform (20%)
    @Builder.Default
    private BigDecimal debtAmount = BigDecimal.ZERO;

    // When debt hits $20, this becomes true → no new orders
    @Builder.Default
    private Boolean isBlocked = false;

    // Driver mode: PEOPLE | PACKAGE | HYBRID
    @Enumerated(EnumType.STRING)
    private DriverMode driverMode;

    // Is the driver currently online?
    @Builder.Default
    private Boolean isOnline = false;

    // ─── Account status ─────────────────────────────
    @Builder.Default
    private Boolean isActive = true;

    // ─── The Role Enum (inside same file) ───────────
    public enum Role {
        MERCHANT,
        DRIVER,
        CUSTOMER
    }

    // ─── Driver Mode Enum ───────────────────────
    public enum DriverMode {
        PEOPLE,
        PACKAGE,
        HYBRID
    }
}