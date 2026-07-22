package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import lombok.Data;

import java.math.BigDecimal;
import java.util.List;

/**
 * FIX (C2 — Critical): totalPrice and deliveryFee were REMOVED from this
 * DTO for standard app orders — a customer could POST
 * {"totalPrice": 0.01} and the platform's commission would be
 * calculated on a fake number. Standard LOGISTICS orders (customer's
 * own cart) still send item lines only — see below.
 *
 * FIX (product decision, O2O): O2O is different — the MERCHANT enters
 * their own order's price for a phone customer who isn't in the app.
 * That's the merchant's own sale, not a customer-supplied number, so
 * totalPrice IS trusted here specifically for isO2O=true requests.
 * deliveryFee is NEVER trusted from the client for ANY order type —
 * always computed server-side by PricingService from real distance.
 */
@Data
public class OrderRequest {

    // ─── Which merchant (LOGISTICS / O2O orders only) ─
    // NOT required for MOBILITY (ride requests)
    private Long merchantId;

    // ─── Cart lines — required for standard LOGISTICS ─
    // (customer's own self-checkout cart). NOT used for
    // O2O (see totalPrice below) or MOBILITY.
    private List<OrderItemLineRequest> items;

    // ─── Manual price — O2O ONLY ──────────────────────
    // The merchant's own entered price for a phone order.
    // Ignored/unused for standard LOGISTICS (those use
    // items above) and MOBILITY (no product involved).
    private BigDecimal totalPrice;

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
    // MOBILITY = people transport (Uber-style ride)
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