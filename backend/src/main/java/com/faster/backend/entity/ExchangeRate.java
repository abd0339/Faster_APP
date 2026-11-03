package com.faster.backend.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

// ─────────────────────────────────────────────────────
// ExchangeRate — single-row table holding the admin-settable
// USD/LBP exchange rate used across the app (pricing, payouts,
// etc.).
//
// Deliberately a singleton row: id is always 1L, never
// auto-generated. The migration (infra/migrations/0004_add_
// exchange_rate.sql) seeds that row — its absence at runtime
// means the migration wasn't run, which ExchangeRateService
// treats as a loud failure (NotFoundException) rather than
// silently defaulting to some hardcoded rate.
// ─────────────────────────────────────────────────────
@Entity
@Table(name = "exchange_rate")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ExchangeRate {

    @Id
    private Long id;

    @Column(name = "usd_to_lbp_rate", nullable = false)
    private BigDecimal usdToLbpRate;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Nullable — the seeded row has no admin behind it yet
    @Column(name = "updated_by_admin_id")
    private Long updatedByAdminId;
}
