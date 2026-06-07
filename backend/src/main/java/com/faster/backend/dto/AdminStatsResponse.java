package com.faster.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AdminStatsResponse {

    // ─── User counts ──────────────────────────────────
    private long totalUsers;
    private long totalMerchants;
    private long totalDrivers;
    private long totalCustomers;
    private long blockedDrivers;
    private long activeDrivers;

    // ─── Order counts ─────────────────────────────────
    private long totalOrders;
    private long pendingOrders;
    private long activeOrders;
    private long deliveredOrders;
    private long disputedOrders;
    private long cancelledOrders;

    // ─── Financial ────────────────────────────────────
    private BigDecimal totalPlatformRevenue;
    private BigDecimal todayRevenue;
    private BigDecimal totalDriverDebtOutstanding;
    private BigDecimal totalMerchantDebtOutstanding;

    // ─── Today's activity ────────────────────────────
    private long todayOrders;
    private long todayDeliveries;
}