package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class OrderRequest {

    // ─── Product value ────────────────────────────────
    // What the driver will pay the merchant at pickup
    @NotNull(message = "Total price is required")
    @DecimalMin(value = "0.01",
                message = "Price must be greater than 0")
    private BigDecimal totalPrice;

    // ─── Delivery fee ─────────────────────────────────
    // What the customer pays for delivery
    // Platform takes 20% of this as driver commission
    // Driver keeps the remaining 80%
    @DecimalMin(value = "0.00",
                message = "Delivery fee cannot be negative")
    private BigDecimal deliveryFee;

    // ─── Pickup location (merchant location) ──────────
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    // ─── Delivery location (customer location) ────────
    private Double deliveryLat;
    private Double deliveryLng;
    private String deliveryAddress;

    // ─── Extra info ───────────────────────────────────
    private String customerNotes;

    // LOGISTICS (default) or MOBILITY
    private Order.OrderType orderType;

    // ─── O2O fields (offline customer) ───────────────
    // Set isO2O = true when merchant creates order
    // for a customer who called by phone
    private Boolean isO2O = false;

    // Required when isO2O = true
    private String offlineCustomerPhone;

    // Landmark/address of offline customer
    private String offlineLandmark;
}