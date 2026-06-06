package com.faster.backend.controller;

import com.faster.backend.dto.OrderRequest;
import com.faster.backend.dto.OrderStatusRequest;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.OrderService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;
    private final UserRepository userRepository;

    // ─── POST /api/orders ─────────────────────────────
    // Create order (merchant or customer)
    @PostMapping("/api/orders")
    public ResponseEntity<?> createOrder(
            @Valid @RequestBody OrderRequest req,
            Authentication auth) {

        User user = getUser(auth);
        Order order;

        // ─── O2O Order (merchant creates for offline customer)
        if (Boolean.TRUE.equals(req.getIsO2O())) {
            if (req.getOfflineCustomerPhone() == null
                || req.getOfflineLandmark() == null) {
                return ResponseEntity.badRequest().body(
                    Map.of("message",
                           "Phone and landmark are " +
                           "required for O2O orders"));
            }

            order = orderService.createO2OOrder(
                    user.getId(),
                    req.getOfflineCustomerPhone(),
                    req.getOfflineLandmark(),
                    req.getTotalPrice(),
                    req.getPickupLat(),
                    req.getPickupLng(),
                    req.getPickupAddress());

        } else {
            // ─── Standard Order ───────────────────────
            order = orderService.createOrder(
                    user.getId(),
                    user.getId(),
                    req.getTotalPrice(),
                    req.getPickupLat(),
                    req.getPickupLng(),
                    req.getPickupAddress(),
                    req.getDeliveryLat(),
                    req.getDeliveryLng(),
                    req.getDeliveryAddress(),
                    req.getCustomerNotes(),
                    req.getOrderType() != null
                        ? req.getOrderType()
                        : Order.OrderType.LOGISTICS);
        }

        return ResponseEntity.ok(order);
    }

    // ─── POST /api/orders/{id}/accept ─────────────────
    // Driver accepts an order
    @PostMapping("/api/orders/{id}/accept")
    public ResponseEntity<?> acceptOrder(
            @PathVariable Long id,
            Authentication auth) {

        User driver = getUser(auth);
        Order order = orderService.acceptOrder(
            driver.getId(), id);

        return ResponseEntity.ok(Map.of(
            "message", "Order accepted successfully",
            "trackingCode", order.getTrackingCode(),
            "status", order.getStatus()
        ));
    }

    // ─── PATCH /api/orders/{id}/status ────────────────
    // Update order status (driver or merchant)
    @PatchMapping("/api/orders/{id}/status")
    public ResponseEntity<?> updateStatus(
            @PathVariable Long id,
            @Valid @RequestBody OrderStatusRequest req,
            Authentication auth) {

        User user = getUser(auth);

        // Handle dispute separately
        if (req.getStatus() == Order.OrderStatus.DISPUTED) {
            if (req.getDisputeReason() == null
                || req.getDisputeReason().isBlank()) {
                return ResponseEntity.badRequest().body(
                    Map.of("message",
                           "Dispute reason is required"));
            }
            Order order = orderService.disputeOrder(
                id, req.getDisputeReason(), user.getId());
            return ResponseEntity.ok(order);
        }

        Order order = orderService.updateStatus(
            id, req.getStatus(), user.getId());

        return ResponseEntity.ok(Map.of(
            "message", "Status updated to "
                       + req.getStatus(),
            "orderId", order.getId(),
            "status", order.getStatus()
        ));
    }

    // ─── GET /api/orders/merchant ─────────────────────
    // Merchant sees all their orders
    @GetMapping("/api/orders/merchant")
    public ResponseEntity<List<Order>> getMerchantOrders(
            Authentication auth) {

        User user = getUser(auth);
        return ResponseEntity.ok(
            orderService.getMerchantOrders(user.getId()));
    }

    // ─── GET /api/orders/driver ───────────────────────
    // Driver sees all their orders
    @GetMapping("/api/orders/driver")
    public ResponseEntity<List<Order>> getDriverOrders(
            Authentication auth) {

        User user = getUser(auth);
        return ResponseEntity.ok(
            orderService.getDriverOrders(user.getId()));
    }

    // ─── GET /api/orders/driver/active ────────────────
    @GetMapping("/api/orders/driver/active")
    public ResponseEntity<List<Order>> getActiveOrders(
            Authentication auth) {

        User user = getUser(auth);
        return ResponseEntity.ok(
            orderService.getActiveDriverOrders(
                user.getId()));
    }

    // ─── GET /tracking/public/{code} ──────────────────
    // PUBLIC — No token needed
    // Offline customer tracks their order via SMS link
    @GetMapping("/tracking/public/{trackingCode}")
    public ResponseEntity<?> trackOrder(
            @PathVariable String trackingCode) {

        Order order = orderService
            .trackOrder(trackingCode);

        // Return safe public view
        // (no merchant/driver personal data)
        return ResponseEntity.ok(Map.of(
            "trackingCode", order.getTrackingCode(),
            "status", order.getStatus(),
            "orderType", order.getOrderType(),
            "pickupAddress",
                order.getPickupAddress() != null
                ? order.getPickupAddress() : "",
            "deliveryAddress",
                order.getDeliveryAddress() != null
                ? order.getDeliveryAddress() : "",
            "createdAt", order.getCreatedAt(),
            "updatedAt", order.getUpdatedAt()
        ));
    }

    // ─── Helper ───────────────────────────────────────
    private User getUser(Authentication auth) {
        String principal = auth.getName();
        return userRepository
                .findByEmail(principal)
                .orElseGet(() ->
                    userRepository.findByPhone(principal)
                        .orElseThrow(() ->
                            new RuntimeException(
                                "User not found")));
    }
}