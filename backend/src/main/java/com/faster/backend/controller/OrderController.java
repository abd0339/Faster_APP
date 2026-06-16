package com.faster.backend.controller;

import com.faster.backend.dto.OrderRequest;
import com.faster.backend.dto.OrderStatusRequest;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OrderRepository;
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
        private final OrderRepository orderRepository;

        // ─────────────────────────────────────────────────
        // POST /api/orders
        // Who calls this:
        //   MERCHANT  → O2O (isO2O: true, offline customer by phone)
        //   CUSTOMER  → App order (LOGISTICS or MOBILITY)
        // ─────────────────────────────────────────────────
        @PostMapping("/api/orders")
        public ResponseEntity<?> createOrder(
                        @Valid @RequestBody OrderRequest req,
                        Authentication auth) {

                User user = getUser(auth);
                Order order;

                // ─── O2O: Merchant creates for offline customer ──
                if (Boolean.TRUE.equals(req.getIsO2O())) {

                        // Only merchants can create O2O orders
                        if (user.getRole() != User.Role.MERCHANT) {
                                return ResponseEntity.status(403)
                                                .body(Map.of("message",
                                                                "Only merchants can create O2O orders"));
                        }

                        if (req.getOfflineCustomerPhone() == null
                                        || req.getOfflineLandmark() == null) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "Phone and landmark are required for O2O orders"));
                        }

                        order = orderService.createO2OOrder(
                                        user.getId(),
                                        req.getOfflineCustomerPhone(),
                                        req.getOfflineLandmark(),
                                        req.getTotalPrice(),
                                        req.getDeliveryFee(),
                                        req.getPickupLat(),
                                        req.getPickupLng(),
                                        req.getPickupAddress());

                } else if (req.getOrderType() == Order.OrderType.MOBILITY) {

                        // ─── MOBILITY: Customer requests a ride ──────────
                        // No merchant involved — driver picks up passenger
                        // Uses PEOPLE or HYBRID mode drivers
                        order = orderService.createMobilityOrder(
                                        user.getId(),
                                        req.getDeliveryFee(),
                                        req.getPickupLat(),
                                        req.getPickupLng(),
                                        req.getPickupAddress(),
                                        req.getDeliveryLat(),
                                        req.getDeliveryLng(),
                                        req.getDeliveryAddress(),
                                        req.getCustomerNotes());

                } else {

                        // ─── LOGISTICS: Customer orders from a store ─────
                        // merchantId must be provided by client
                        if (req.getMerchantId() == null) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "merchantId is required for LOGISTICS orders"));
                        }

                        order = orderService.createOrder(
                                        req.getMerchantId(),
                                        user.getId(),
                                        req.getTotalPrice(),
                                        req.getDeliveryFee(),
                                        req.getPickupLat(),
                                        req.getPickupLng(),
                                        req.getPickupAddress(),
                                        req.getDeliveryLat(),
                                        req.getDeliveryLng(),
                                        req.getDeliveryAddress(),
                                        req.getCustomerNotes(),
                                        Order.OrderType.LOGISTICS);
                }

                return ResponseEntity.ok(order);
        }

        // ─────────────────────────────────────────────────
        // GET /api/orders/{id}
        // Single order — accessible by merchant, driver,
        // customer who owns it, or admin
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/{id}")
        public ResponseEntity<?> getOrderById(
                        @PathVariable Long id,
                        Authentication auth) {

                User user = getUser(auth);
                Order order = orderRepository.findById(id)
                                .orElseThrow(() ->
                                                new RuntimeException("Order not found"));

                boolean isMerchant = order.getMerchant() != null &&
                                order.getMerchant().getId().equals(user.getId());
                boolean isDriver = order.getDriver() != null &&
                                order.getDriver().getId().equals(user.getId());
                boolean isCustomer = order.getCustomer() != null &&
                                order.getCustomer().getId().equals(user.getId());
                boolean isAdmin = user.getRole() == User.Role.ADMIN;

                if (!isMerchant && !isDriver && !isCustomer && !isAdmin) {
                        return ResponseEntity.status(403)
                                        .body(Map.of("message", "Access denied"));
                }

                return ResponseEntity.ok(order);
        }

        // ─────────────────────────────────────────────────
        // POST /api/orders/{id}/accept
        // Driver accepts a pending order
        // ─────────────────────────────────────────────────
        @PostMapping("/api/orders/{id}/accept")
        public ResponseEntity<?> acceptOrder(
                        @PathVariable Long id,
                        Authentication auth) {

                User driver = getUser(auth);

                if (driver.getRole() != User.Role.DRIVER) {
                        return ResponseEntity.status(403)
                                        .body(Map.of("message",
                                                        "Only drivers can accept orders"));
                }

                Order order = orderService.acceptOrder(driver.getId(), id);

                return ResponseEntity.ok(Map.of(
                                "message", "Order accepted successfully",
                                "trackingCode", order.getTrackingCode(),
                                "status", order.getStatus(),
                                "grandTotal", order.getGrandTotal(),
                                "deliveryAddress",
                                order.getDeliveryAddress() != null
                                                ? order.getDeliveryAddress()
                                                : ""));
        }

        // ─────────────────────────────────────────────────
        // PATCH /api/orders/{id}/status
        // Update order status — driver or merchant
        // PENDING → ACCEPTED → PREPARING → READY_FOR_PICKUP
        //         → PICKED_UP → DELIVERED
        // ─────────────────────────────────────────────────
        @PatchMapping("/api/orders/{id}/status")
        public ResponseEntity<?> updateStatus(
                        @PathVariable Long id,
                        @Valid @RequestBody OrderStatusRequest req,
                        Authentication auth) {

                User user = getUser(auth);

                // Dispute handled separately
                if (req.getStatus() == Order.OrderStatus.DISPUTED) {
                        if (req.getDisputeReason() == null
                                        || req.getDisputeReason().isBlank()) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "Dispute reason is required"));
                        }
                        Order order = orderService.disputeOrder(
                                        id, req.getDisputeReason(), user.getId());
                        return ResponseEntity.ok(order);
                }

                Order order = orderService.updateStatus(
                                id, req.getStatus(), user.getId());

                return ResponseEntity.ok(Map.of(
                                "message", "Status updated to " + req.getStatus(),
                                "orderId", order.getId(),
                                "status", order.getStatus()));
        }

        // ─────────────────────────────────────────────────
        // GET /api/orders/merchant
        // Merchant sees all orders for their store
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/merchant")
        public ResponseEntity<List<Order>> getMerchantOrders(
                        Authentication auth) {
                User user = getUser(auth);
                return ResponseEntity.ok(
                                orderService.getMerchantOrders(user.getId()));
        }

        // ─────────────────────────────────────────────────
        // GET /api/orders/driver
        // Driver sees all their orders (full history)
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/driver")
        public ResponseEntity<List<Order>> getDriverOrders(
                        Authentication auth) {
                User user = getUser(auth);
                return ResponseEntity.ok(
                                orderService.getDriverOrders(user.getId()));
        }

        // ─────────────────────────────────────────────────
        // GET /api/orders/driver/active
        // Driver sees their current active order only
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/driver/active")
        public ResponseEntity<List<Order>> getActiveDriverOrders(
                        Authentication auth) {
                User user = getUser(auth);
                return ResponseEntity.ok(
                                orderService.getActiveDriverOrders(user.getId()));
        }

        // ─────────────────────────────────────────────────
        // GET /api/orders/customer
        // Customer sees all their orders (history)
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/customer")
        public ResponseEntity<List<Order>> getCustomerOrders(
                        Authentication auth) {
                Long customerId = getUser(auth).getId();
                return ResponseEntity.ok(
                                orderService.getCustomerOrders(customerId));
        }

        // ─────────────────────────────────────────────────
        // GET /tracking/public/{trackingCode}
        // PUBLIC — No auth needed
        // Offline customer tracks via SMS link
        // ─────────────────────────────────────────────────
        @GetMapping("/tracking/public/{trackingCode}")
        public ResponseEntity<?> trackOrder(
                        @PathVariable String trackingCode) {

                Order order = orderService.trackOrder(trackingCode);

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
                                "updatedAt", order.getUpdatedAt()));
        }

        // ─── Helper: get authenticated user ───────────────
        private User getUser(Authentication auth) {
                String principal = auth.getName();
                return userRepository.findByEmail(principal)
                                .orElseGet(() ->
                                                userRepository.findByPhone(principal)
                                                                .orElseThrow(() ->
                                                                                new RuntimeException(
                                                                                                "User not found")));
        }
}