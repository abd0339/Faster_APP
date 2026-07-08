package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import lombok.Data;

import java.util.List;

/**
 * FIX (C2 — Critical): totalPrice and deliveryFee are REMOVED from this
 * DTO. They used to be trusted straight from the client, meaning a
 * customer could POST {"totalPrice": 0.01} and the platform's commission
 * would be calculated on a fake number.
 *
 * The client now sends WHAT was ordered (merchantId + item lines) and
 * WHERE (pickup/delivery coordinates). OrderService + PricingService
 * compute the real totalPrice (from the merchant's own catalog) and the
 * real deliveryFee/rideFee (from actual distance) entirely server-side.
 * Nothing money-related is ever read from this request body anymore.
 */
@Data
public class OrderRequest {

    // ─── Which merchant (LOGISTICS / O2O orders only) ─
    // NOT required for MOBILITY (ride requests)
    private Long merchantId;

    // ─── Cart lines — required for LOGISTICS and O2O ──
    // Each line is an itemId + quantity (+ optional
    // modifiers/addons). Server looks up real prices from
    // this merchant's own catalog — see PricingService.
    // NOT used for MOBILITY (no products involved).
    private List<OrderItemLineRequest> items;

    // ─── Pickup location ──────────────────────────────
    // LOGISTICS/O2O: merchant store location
    // MOBILITY: customer current location (pickup point)
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    // ─── Delivery location ────────────────────────────
    // LOGISTICS: customer home/delivery address
    // MOBILITY: customer destination
    // O2O: optional — only if merchant pins an exact map
    // location (Flow 1). May be null for the WhatsApp
    // "bridge link" flow (Flow 2) where the offline
    // customer shares location after order creation.
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
    private Boolean isO2O = false;

    // Required only when isO2O = true
    private String offlineCustomerPhone;

    // Landmark/address of offline customer
    private String offlineLandmark;
}