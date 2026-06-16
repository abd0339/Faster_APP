package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class OrderRequest {

    // ─── Which merchant (LOGISTICS orders only) ───────
    // Required for LOGISTICS — the store the customer orders from
    // NOT required for MOBILITY (ride requests)
    // NOT required for O2O (merchant creates for offline customer)
    private Long merchantId;

    // ─── Product value ────────────────────────────────
    // LOGISTICS: total value of items ordered
    // MOBILITY: 0.00 (no products)
    // What the driver pays the merchant at pickup (LOGISTICS)
    @NotNull(message = "Total price is required")
    @DecimalMin(value = "0.00",
                message = "Price cannot be negative")
    private BigDecimal totalPrice;

    // ─── Delivery fee ─────────────────────────────────
    // What the customer pays the driver for delivery/ride
    // Platform takes 20% of this as driver commission
    // Driver keeps the remaining 80%
    @DecimalMin(value = "0.00",
                message = "Delivery fee cannot be negative")
    private BigDecimal deliveryFee;

    // ─── Pickup location ──────────────────────────────
    // LOGISTICS: merchant store location
    // MOBILITY: customer current location (pickup point)
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    // ─── Delivery location ────────────────────────────
    // LOGISTICS: customer home/delivery address
    // MOBILITY: customer destination
    private Double deliveryLat;
    private Double deliveryLng;
    private String deliveryAddress;

    // ─── Notes ────────────────────────────────────────
    private String customerNotes;

    // ─── Order type ───────────────────────────────────
    // LOGISTICS = package delivery (default)
    // MOBILITY  = people transport (Uber-style ride)
    private Order.OrderType orderType;

    // ─── O2O fields (offline customer via phone) ──────
    // Set isO2O = true when merchant creates order
    // for a customer who called by phone
    // isO2O = false by default (all app orders)
    private Boolean isO2O = false;

    // Required only when isO2O = true
    private String offlineCustomerPhone;

    // Landmark/address of offline customer
    private String offlineLandmark;
}