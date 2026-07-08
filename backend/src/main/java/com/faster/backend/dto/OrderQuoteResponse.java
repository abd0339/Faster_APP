package com.faster.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

/**
 * Response for POST /api/orders/quote — lets the customer app
 * show the real, server-computed price BEFORE placing the order.
 * Nothing here is persisted; it's recomputed again (from scratch,
 * never trusting this response) when the order is actually created.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderQuoteResponse {
    private BigDecimal totalPrice;
    private BigDecimal deliveryFee;
    private BigDecimal grandTotal;
}