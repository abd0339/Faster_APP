package com.faster.backend.dto;

import com.faster.backend.entity.LedgerEntry;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LedgerResponse {

    private Long id;
    private LedgerEntry.EntryType type;
    private LedgerEntry.EntryCategory category;
    private BigDecimal amount;
    private BigDecimal deliveryFee;
    private BigDecimal balanceAfter;
    private String description;
    private String paymentReference;
    private String orderTrackingCode;
    private LocalDateTime createdAt;

    // ─── Build from LedgerEntry entity ───────────────
    public static LedgerResponse from(
            LedgerEntry entry) {
        return LedgerResponse.builder()
                .id(entry.getId())
                .type(entry.getType())
                .category(entry.getCategory())
                .amount(entry.getAmount())
                .deliveryFee(entry.getDeliveryFee())
                .balanceAfter(entry.getBalanceAfter())
                .description(entry.getDescription())
                .paymentReference(
                    entry.getPaymentReference())
                .orderTrackingCode(
                    entry.getOrder() != null
                    ? entry.getOrder()
                          .getTrackingCode()
                    : null)
                .createdAt(entry.getCreatedAt())
                .build();
    }
}