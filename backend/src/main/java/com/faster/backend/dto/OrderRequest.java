package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class OrderRequest {

    // ─── Standard order fields ────────────────────────
    @NotNull(message = "Total price is required")
    @DecimalMin(value = "0.01",
                message = "Price must be greater than 0")
    private BigDecimal totalPrice;

    // Pickup = merchant location
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    // Delivery = customer location
    private Double deliveryLat;
    private Double deliveryLng;
    private String deliveryAddress;

    private String customerNotes;

    // LOGISTICS or MOBILITY
    private Order.OrderType orderType;

    // ─── O2O fields (offline customer) ───────────────
    // Filled when merchant creates order for
    // an offline customer who called by phone
    private String offlineCustomerPhone;
    private String offlineLandmark;

    // ─── Is this an O2O order? ────────────────────────
    private Boolean isO2O = false;
}