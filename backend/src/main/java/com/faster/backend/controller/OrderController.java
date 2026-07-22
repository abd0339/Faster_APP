package com.faster.backend.controller;

import com.faster.backend.dto.OrderQuoteResponse;
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
        // POST /api/orders/quote
        // FIX (C2): lets the customer app show the REAL,
        // server-computed price before the customer confirms.
        // Nothing is persisted — createOrder() below recomputes
        // from scratch regardless, so this is a display
        // convenience only, never a trusted value.
        // ─────────────────────────────────────────────────
        @PostMapping("/api/orders/quote")
        public ResponseEntity<?> quoteOrder(
                        @RequestBody OrderRequest req) {

                if (req.getMerchantId() == null) {
                        return ResponseEntity.badRequest()
                                        .body(Map.of("message",
                                                        "merchantId is required for a quote"));
                }

                OrderQuoteResponse quote = orderService.quoteLogisticsOrder(
                                req.getMerchantId(),
                                req.getItems(),
                                req.getPickupLat(),
                                req.getPickupLng(),
                                req.getDeliveryLat(),
                                req.getDeliveryLng());

                return ResponseEntity.ok(quote);
        }

        // ─────────────────────────────────────────────────
        // POST /api/orders
        // Who calls this:
        // MERCHANT → O2O (isO2O: true, offline customer by phone)
        // CUSTOMER → App order (LOGISTICS or MOBILITY)
        //
        // FIX (C2 — Critical): totalPrice/deliveryFee are no
        // longer read from the request. The client sends WHAT
        // was ordered (merchantId + item lines) and WHERE
        // (coordinates); OrderService + PricingService compute
        // the real price server-side from the merchant's own
        // catalog and real distance. See OrderRequest.java and
        // PricingService.java for the full explanation.
        // ─────────────────────────────────────────────────
        @PostMapping("/api/orders")
        public ResponseEntity<?> createOrder(
                        @Valid @RequestBody OrderRequest req,
                        Authentication auth) {

                User user = getUser(auth);
                Order order;

                // ─── O2O: Merchant creates for offline customer ──
                if (Boolean.TRUE.equals(req.getIsO2O())) {

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

                        if (req.getTotalPrice() == null
                                        || req.getTotalPrice()
                                                        .compareTo(java.math.BigDecimal.ZERO) <= 0) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "A valid order price is required for O2O orders"));
                        }

                        order = orderService.createO2OOrder(
                                        user.getId(),
                                        req.getOfflineCustomerPhone(),
                                        req.getOfflineLandmark(),
                                        req.getTotalPrice(),
                                        req.getPickupLat(),
                                        req.getPickupLng(),
                                        req.getPickupAddress(),
                                        req.getDeliveryLat(),
                                        req.getDeliveryLng());

                } else if (req.getOrderType() == Order.OrderType.MOBILITY) {

                        // ─── MOBILITY: Customer requests a ride ──────────
                        // No items, no client-sent fee — server derives
                        // the ride fee from pickup→destination distance.
                        order = orderService.createMobilityOrder(
                                        user.getId(),
                                        req.getPickupLat(),
                                        req.getPickupLng(),
                                        req.getPickupAddress(),
                                        req.getDeliveryLat(),
                                        req.getDeliveryLng(),
                                        req.getDeliveryAddress(),
                                        req.getCustomerNotes());

                } else {

                        // ─── LOGISTICS: Customer orders from a store ─────
                        if (req.getMerchantId() == null) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "merchantId is required for LOGISTICS orders"));
                        }

                        if (req.getItems() == null || req.getItems().isEmpty()) {
                                return ResponseEntity.badRequest()
                                                .body(Map.of("message",
                                                                "Cart must contain at least one item"));
                        }

                        order = orderService.createOrder(
                                        req.getMerchantId(),
                                        user.getId(),
                                        req.getItems(),
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
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/{id}")
        public ResponseEntity<?> getOrderById(
                        @PathVariable Long id,
                        Authentication auth) {

                User user = getUser(auth);
                Order order = orderRepository.findById(id)
                                .orElseThrow(() -> new RuntimeException("Order not found"));

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
        // ─────────────────────────────────────────────────
        @PatchMapping("/api/orders/{id}/status")
        public ResponseEntity<?> updateStatus(
                        @PathVariable Long id,
                        @Valid @RequestBody OrderStatusRequest req,
                        Authentication auth) {

                User user = getUser(auth);

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
        // ─────────────────────────────────────────────────
        @GetMapping("/api/orders/customer")
        public ResponseEntity<List<Order>> getCustomerOrders(
                        Authentication auth) {
                Long customerId = getUser(auth).getId();
                return ResponseEntity.ok(
                                orderService.getCustomerOrders(customerId));
        }

        // ─────────────────────────────────────────────────
        // GET /api/tracking/public/{trackingCode}
        // FIX: moved from /tracking/public/** to /api/tracking/public/**.
        // Previously nginx routed the human-facing tracking LINK
        // (sent via WhatsApp/SMS) straight to this JSON endpoint —
        // a customer clicking the link saw raw JSON text, not a
        // page. Now /tracking/public/** is served by the Flutter
        // SPA (a real page), which calls THIS endpoint internally
        // to fetch the data it needs. See nginx.conf and
        // PublicTrackingScreen (Flutter).
        //
        // Also now returns orderId (so the Flutter page can poll
        // status) and driver info once assigned.
        // ─────────────────────────────────────────────────
        @GetMapping("/api/tracking/public/{trackingCode}")
        public ResponseEntity<?> trackOrder(
                        @PathVariable String trackingCode) {

                Order order = orderService.trackOrder(trackingCode);

                Map<String, Object> response = new java.util.HashMap<>();
                response.put("orderId", order.getId());
                response.put("trackingCode", order.getTrackingCode());
                response.put("status", order.getStatus());
                response.put("orderType", order.getOrderType());
                response.put("pickupAddress",
                                order.getPickupAddress() != null
                                                ? order.getPickupAddress()
                                                : "");
                response.put("deliveryAddress",
                                order.getDeliveryAddress() != null
                                                ? order.getDeliveryAddress()
                                                : "");
                response.put("deliveryLat", order.getDeliveryLat());
                response.put("deliveryLng", order.getDeliveryLng());
                response.put("grandTotal", order.getGrandTotal());
                response.put("deliveryFee", order.getDeliveryFee());
                response.put("createdAt", order.getCreatedAt());
                response.put("updatedAt", order.getUpdatedAt());

                if (order.getDriver() != null) {
                        response.put("driverName", order.getDriver().getFullName());
                        response.put("driverVehicleType",
                                        order.getDriver().getVehicleType() != null
                                                        ? order.getDriver().getVehicleType()
                                                        : "");
                        response.put("driverVehiclePlate",
                                        order.getDriver().getVehiclePlate() != null
                                                        ? order.getDriver().getVehiclePlate()
                                                        : "");
                }

                return ResponseEntity.ok(response);
        }

        // ─────────────────────────────────────────────────
        // PATCH /api/tracking/public/{trackingCode}/location
        // NEW — the offline customer opens their tracking
        // link and shares their location; this recomputes
        // the real distance-based delivery fee instead of
        // leaving it at the flat fallback used at order
        // creation when no coordinates were available yet.
        // Public — no auth — matches the existing GET above.
        // ─────────────────────────────────────────────────
        @PatchMapping("/api/tracking/public/{trackingCode}/location")
        public ResponseEntity<?> updateTrackingLocation(
                        @PathVariable String trackingCode,
                        @RequestBody Map<String, Double> body) {

                Order order = orderService.updateTrackingLocation(
                                trackingCode, body.get("lat"), body.get("lng"));

                return ResponseEntity.ok(Map.of(
                                "message", "Location confirmed",
                                "trackingCode", order.getTrackingCode(),
                                "deliveryFee", order.getDeliveryFee(),
                                "grandTotal", order.getGrandTotal()));
        }

        // ─── Helper: get authenticated user ───────────────
        private User getUser(Authentication auth) {
                String principal = auth.getName();
                return userRepository.findByEmail(principal)
                                .orElseGet(() -> userRepository.findByPhone(principal)
                                                .orElseThrow(() -> new RuntimeException(
                                                                "User not found")));
        }
}
