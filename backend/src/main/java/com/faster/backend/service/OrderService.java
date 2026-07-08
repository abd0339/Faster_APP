package com.faster.backend.service;

import com.faster.backend.dto.OrderItemLineRequest;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.ForbiddenException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final UserRepository userRepository;
    private final LocationService locationService;
    private final SimpMessagingTemplate messagingTemplate;
    private final LedgerService ledgerService;
    private final CommunicationService communicationService;
    private final PricingService pricingService;

    private static final BigDecimal DRIVER_COMMISSION_RATE =
            new BigDecimal("0.20");
    private static final BigDecimal MERCHANT_COMMISSION_RATE =
            new BigDecimal("0.10");
    private static final double SEARCH_RADIUS_KM = 5.0;

    // ─────────────────────────────────────────────────
    // FIX (M2): ORDER STATUS STATE MACHINE
    //
    // Previously updateStatus() accepted ANY newStatus from
    // any authorized party with zero validation of the
    // current state — a single PATCH request could jump
    // PENDING → DELIVERED directly, skipping PREPARING,
    // READY_FOR_PICKUP, and PICKED_UP entirely, which would
    // immediately trigger driver commission for work that
    // was never actually done.
    //
    // This map is the single source of truth for which
    // transitions are legal from which state. ACCEPTED is
    // deliberately absent as a reachable target here — it
    // can ONLY happen through acceptOrder()'s atomic
    // assignDriver() update, never through this generic
    // status endpoint.
    // ─────────────────────────────────────────────────
    private static final Map<Order.OrderStatus, Set<Order.OrderStatus>>
            ALLOWED_TRANSITIONS = new EnumMap<>(Order.OrderStatus.class);

    static {
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.PENDING,
                EnumSet.of(Order.OrderStatus.CANCELLED));
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.ACCEPTED,
                EnumSet.of(Order.OrderStatus.PREPARING,
                        Order.OrderStatus.CANCELLED));
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.PREPARING,
                EnumSet.of(Order.OrderStatus.READY_FOR_PICKUP,
                        Order.OrderStatus.CANCELLED));
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.READY_FOR_PICKUP,
                EnumSet.of(Order.OrderStatus.PICKED_UP,
                        Order.OrderStatus.CANCELLED));
        // Once picked up, the driver has the physical goods —
        // cancellation is no longer a valid outcome, only delivery.
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.PICKED_UP,
                EnumSet.of(Order.OrderStatus.DELIVERED));
        // Terminal states — no transitions out via this endpoint.
        // DISPUTED is entered only through disputeOrder(), and
        // resolved only through AdminService.resolveDispute().
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.DELIVERED,
                EnumSet.noneOf(Order.OrderStatus.class));
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.CANCELLED,
                EnumSet.noneOf(Order.OrderStatus.class));
        ALLOWED_TRANSITIONS.put(Order.OrderStatus.DISPUTED,
                EnumSet.noneOf(Order.OrderStatus.class));
    }

    // ─────────────────────────────────────────────────
    // QUOTE — display-only, never trusted for creation
    // ─────────────────────────────────────────────────
    public com.faster.backend.dto.OrderQuoteResponse quoteLogisticsOrder(
            Long merchantId,
            List<OrderItemLineRequest> items,
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng) {

        BigDecimal totalPrice =
                pricingService.calculateItemsTotal(merchantId, items);
        BigDecimal deliveryFee = pricingService.calculateDeliveryFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng);
        BigDecimal grandTotal = totalPrice.add(deliveryFee)
                .setScale(2, RoundingMode.HALF_UP);

        return com.faster.backend.dto.OrderQuoteResponse.builder()
                .totalPrice(totalPrice)
                .deliveryFee(deliveryFee)
                .grandTotal(grandTotal)
                .build();
    }

    // ─────────────────────────────────────────────────
    // CREATE STANDARD ORDER (LOGISTICS)
    // ─────────────────────────────────────────────────
    @Transactional
    public Order createOrder(Long merchantId,
            Long customerId,
            List<OrderItemLineRequest> items,
            Double pickupLat,
            Double pickupLng,
            String pickupAddress,
            Double deliveryLat,
            Double deliveryLng,
            String deliveryAddress,
            String customerNotes,
            Order.OrderType orderType) {

        User merchant = getUser(merchantId);
        User customer = getUser(customerId);

        BigDecimal totalPrice =
                pricingService.calculateItemsTotal(merchantId, items);

        BigDecimal actualDeliveryFee = pricingService.calculateDeliveryFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        BigDecimal driverCommission = actualDeliveryFee
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal grandTotal = totalPrice
                .add(actualDeliveryFee)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal merchantCommission = totalPrice
                .multiply(MERCHANT_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        Order order = Order.builder()
                .trackingCode(generateTrackingCode())
                .merchant(merchant)
                .customer(customer)
                .orderType(Order.OrderType.LOGISTICS)
                .status(Order.OrderStatus.PENDING)
                .totalPrice(totalPrice)
                .deliveryFee(actualDeliveryFee)
                .commissionAmount(driverCommission)
                .grandTotal(grandTotal)
                .driverPaysMerchant(totalPrice)
                .merchantCommission(merchantCommission)
                .pickupLat(pickupLat)
                .pickupLng(pickupLng)
                .pickupAddress(pickupAddress)
                .deliveryLat(deliveryLat)
                .deliveryLng(deliveryLng)
                .deliveryAddress(deliveryAddress)
                .customerNotes(customerNotes)
                .build();

        Order saved = orderRepository.save(order);

        pricingService.decrementStockForOrder(items);

        notifyNearestDrivers(
                saved, pickupLat, pickupLng,
                Order.OrderType.LOGISTICS);

        System.out.println(
                "📦 LOGISTICS order: " + saved.getTrackingCode() +
                " | Merchant: " + merchantId +
                " | Total: $" + grandTotal);

        return saved;
    }

    // ─────────────────────────────────────────────────
    // CREATE MOBILITY ORDER (Uber-style ride)
    // ─────────────────────────────────────────────────
    @Transactional
    public Order createMobilityOrder(
            Long customerId,
            Double pickupLat,
            Double pickupLng,
            String pickupAddress,
            Double deliveryLat,
            Double deliveryLng,
            String deliveryAddress,
            String customerNotes) {

        User customer = getUser(customerId);

        BigDecimal actualFee = pricingService.calculateRideFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        BigDecimal driverCommission = actualFee
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal totalPrice = BigDecimal.ZERO
                .setScale(2, RoundingMode.HALF_UP);
        BigDecimal grandTotal = actualFee;

        Order order = Order.builder()
                .trackingCode(generateTrackingCode())
                .merchant(null)
                .customer(customer)
                .orderType(Order.OrderType.MOBILITY)
                .status(Order.OrderStatus.PENDING)
                .totalPrice(totalPrice)
                .deliveryFee(actualFee)
                .commissionAmount(driverCommission)
                .grandTotal(grandTotal)
                .driverPaysMerchant(BigDecimal.ZERO)
                .merchantCommission(BigDecimal.ZERO)
                .pickupLat(pickupLat)
                .pickupLng(pickupLng)
                .pickupAddress(pickupAddress)
                .deliveryLat(deliveryLat)
                .deliveryLng(deliveryLng)
                .deliveryAddress(deliveryAddress)
                .customerNotes(customerNotes)
                .build();

        Order saved = orderRepository.save(order);

        notifyNearestDrivers(
                saved, pickupLat, pickupLng,
                Order.OrderType.MOBILITY);

        System.out.println(
                "🚗 MOBILITY order: " + saved.getTrackingCode() +
                " | Pickup: " + pickupAddress +
                " | Fee: $" + actualFee);

        return saved;
    }

    // ─────────────────────────────────────────────────
    // CREATE O2O ORDER (Offline Customer by phone)
    // ─────────────────────────────────────────────────
    @Transactional
    public Order createO2OOrder(Long merchantId,
            String offlinePhone,
            String offlineLandmark,
            List<OrderItemLineRequest> items,
            Double pickupLat,
            Double pickupLng,
            String pickupAddress,
            Double deliveryLat,
            Double deliveryLng) {

        User merchant = getUser(merchantId);

        BigDecimal totalPrice =
                pricingService.calculateItemsTotal(merchantId, items);

        BigDecimal actualDeliveryFee = pricingService.calculateDeliveryFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        BigDecimal driverCommission = actualDeliveryFee
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal grandTotal = totalPrice
                .add(actualDeliveryFee)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal merchantCommission = totalPrice
                .multiply(MERCHANT_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        String trackingCode = generateTrackingCode();

        Order order = Order.builder()
                .trackingCode(trackingCode)
                .merchant(merchant)
                .offlineCustomerPhone(offlinePhone)
                .offlineCustomerLandmark(offlineLandmark)
                .orderType(Order.OrderType.LOGISTICS)
                .status(Order.OrderStatus.PENDING)
                .totalPrice(totalPrice)
                .deliveryFee(actualDeliveryFee)
                .commissionAmount(driverCommission)
                .grandTotal(grandTotal)
                .driverPaysMerchant(totalPrice)
                .merchantCommission(merchantCommission)
                .pickupLat(pickupLat)
                .pickupLng(pickupLng)
                .pickupAddress(pickupAddress)
                .deliveryLat(deliveryLat)
                .deliveryLng(deliveryLng)
                .deliveryAddress(offlineLandmark)
                .build();

        Order saved = orderRepository.save(order);

        pricingService.decrementStockForOrder(items);

        notifyNearestDrivers(
                saved, pickupLat, pickupLng,
                Order.OrderType.LOGISTICS);

        communicationService.sendO2OTrackingLink(saved);

        return saved;
    }

    // ─────────────────────────────────────────────────
    // GET CUSTOMER ORDERS
    // ─────────────────────────────────────────────────
    public List<Order> getCustomerOrders(Long customerId) {
        return orderRepository
                .findByCustomerIdOrderByCreatedAtDesc(customerId);
    }

    // ─────────────────────────────────────────────────
    // DRIVER ACCEPTS ORDER
    // The ONLY path that moves an order out of PENDING.
    // Atomic update prevents double-accept race condition.
    // ─────────────────────────────────────────────────
    @Transactional
    public Order acceptOrder(Long driverId, Long orderId) {

        User driver = getUser(driverId);

        if (Boolean.TRUE.equals(driver.getIsBlocked())) {
            throw new BusinessException(
                    "Your account is blocked. " +
                    "Settle your commission debt via OMT or WishMoney, " +
                    "then contact admin to reactivate.");
        }

        int updated = orderRepository.assignDriver(
                orderId, driverId, LocalDateTime.now());

        if (updated == 0) {
            throw new BusinessException(
                    "Order is no longer available — " +
                    "another driver already accepted it.");
        }

        Order saved = orderRepository.findById(orderId)
                .orElseThrow(() ->
                        new NotFoundException("Order not found"));

        if (saved.getMerchant() != null) {
            messagingTemplate.convertAndSend(
                    "/topic/merchant/" +
                    saved.getMerchant().getId(),
                    buildStatusUpdate(saved));
        }

        if (saved.getCustomer() != null) {
            messagingTemplate.convertAndSend(
                    "/topic/order/" + orderId,
                    buildStatusUpdate(saved));
        }

        if (saved.getOfflineCustomerPhone() != null) {
            communicationService.sendDriverAssignedNotification(saved);
        }

        return saved;
    }

    // ─────────────────────────────────────────────────
    // UPDATE ORDER STATUS
    // FIX (M2): every transition is now checked against
    // ALLOWED_TRANSITIONS before anything is persisted.
    // A request to jump straight to DELIVERED (or any
    // other non-adjacent state) is rejected with a clear
    // 422 BusinessException instead of silently succeeding.
    // ─────────────────────────────────────────────────
    @Transactional
    public Order updateStatus(Long orderId,
            Order.OrderStatus newStatus,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() ->
                        new NotFoundException("Order not found"));

        boolean isMerchant = order.getMerchant() != null &&
                order.getMerchant().getId().equals(requesterId);
        boolean isDriver = order.getDriver() != null &&
                order.getDriver().getId().equals(requesterId);

        if (!isMerchant && !isDriver) {
            throw new ForbiddenException(
                    "Not authorized to update this order");
        }

        // ─── State machine check (the M2 fix) ─────────
        Set<Order.OrderStatus> allowedNext =
                ALLOWED_TRANSITIONS.getOrDefault(
                        order.getStatus(),
                        EnumSet.noneOf(Order.OrderStatus.class));

        if (!allowedNext.contains(newStatus)) {
            throw new BusinessException(
                    "Cannot change order status from "
                    + order.getStatus() + " to " + newStatus
                    + ". Allowed next status"
                    + (allowedNext.size() == 1 ? " is " : "es are ")
                    + (allowedNext.isEmpty()
                            ? "none — this order is in a final state"
                            : allowedNext));
        }

        switch (newStatus) {
            case PICKED_UP ->
                order.setPickedUpAt(LocalDateTime.now());
            case DELIVERED ->
                order.setDeliveredAt(LocalDateTime.now());
            default -> {
            }
        }

        order.setStatus(newStatus);
        Order saved = orderRepository.save(order);

        if (newStatus == Order.OrderStatus.DELIVERED) {
            ledgerService.recordDriverCommission(saved);
        }

        messagingTemplate.convertAndSend(
                "/topic/order/" + orderId,
                buildStatusUpdate(saved));

        if (saved.getMerchant() != null) {
            messagingTemplate.convertAndSend(
                    "/topic/merchant/" +
                    saved.getMerchant().getId(),
                    buildStatusUpdate(saved));
        }

        return saved;
    }

    // ─────────────────────────────────────────────────
    // DISPUTE ORDER
    // FIX (M2, minor extension): an order that's already
    // CANCELLED or already DISPUTED can't be disputed
    // again. DELIVERED orders CAN still be disputed
    // (e.g. customer complains after the fact) — that's
    // intentional, not a gap.
    // ─────────────────────────────────────────────────
    @Transactional
    public Order disputeOrder(Long orderId,
            String reason,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() ->
                        new NotFoundException("Order not found"));

        boolean isParty =
                (order.getMerchant() != null &&
                        order.getMerchant().getId().equals(requesterId))
                || (order.getDriver() != null &&
                        order.getDriver().getId().equals(requesterId))
                || (order.getCustomer() != null &&
                        order.getCustomer().getId().equals(requesterId));

        if (!isParty) {
            throw new ForbiddenException(
                    "Not authorized to dispute this order");
        }

        if (order.getStatus() == Order.OrderStatus.CANCELLED
                || order.getStatus() == Order.OrderStatus.DISPUTED) {
            throw new BusinessException(
                    "This order is " + order.getStatus()
                    + " and cannot be disputed");
        }

        order.setStatus(Order.OrderStatus.DISPUTED);
        order.setDisputeReason(reason);

        Order saved = orderRepository.save(order);

        if (saved.getMerchant() != null) {
            messagingTemplate.convertAndSend(
                    "/topic/merchant/" +
                    saved.getMerchant().getId(),
                    buildStatusUpdate(saved));
        }

        messagingTemplate.convertAndSend(
                "/topic/admin/disputes",
                buildStatusUpdate(saved));

        return saved;
    }

    // ─────────────────────────────────────────────────
    // TRACK ORDER (public — O2O SMS link)
    // ─────────────────────────────────────────────────
    public Order trackOrder(String trackingCode) {
        return orderRepository
                .findByTrackingCode(trackingCode)
                .orElseThrow(() -> new NotFoundException(
                        "Order not found. Check your tracking code."));
    }

    public List<Order> getMerchantOrders(Long merchantId) {
        return orderRepository
                .findByMerchantIdOrderByCreatedAtDesc(merchantId);
    }

    public List<Order> getDriverOrders(Long driverId) {
        return orderRepository
                .findByDriverIdOrderByCreatedAtDesc(driverId);
    }

    public List<Order> getActiveDriverOrders(Long driverId) {
        return orderRepository.findActiveOrdersByDriver(driverId);
    }

    public List<Order> getActiveMerchantOrders(Long merchantId) {
        return orderRepository.findActiveOrdersByMerchant(merchantId);
    }

    // ─────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────
    private void notifyNearestDrivers(
            Order order,
            Double pickupLat,
            Double pickupLng,
            Order.OrderType orderType) {

        if (pickupLat == null || pickupLng == null) return;

        List<Long> nearbyDrivers;

        if (orderType == Order.OrderType.MOBILITY) {
            nearbyDrivers = locationService
                    .findNearestPeopleDrivers(
                            pickupLat, pickupLng,
                            SEARCH_RADIUS_KM);
        } else {
            nearbyDrivers = locationService
                    .findNearestPackageDrivers(
                            pickupLat, pickupLng,
                            SEARCH_RADIUS_KM);
        }

        nearbyDrivers.forEach(driverId ->
            messagingTemplate.convertAndSend(
                    "/topic/driver/" + driverId,
                    buildOrderNotification(order)));

        System.out.println(
                "📡 Pinged " + nearbyDrivers.size() +
                " drivers for " + order.getTrackingCode());
    }

    private String generateTrackingCode() {
        String date = LocalDateTime.now()
                .format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String random = String.format("%04X",
                new SecureRandom().nextInt(0xFFFF));
        return "FST-" + date + "-" + random;
    }

    private Map<String, Object> buildStatusUpdate(Order order) {
        return Map.of(
                "type", "STATUS_UPDATE",
                "orderId", order.getId(),
                "trackingCode", order.getTrackingCode(),
                "status", order.getStatus(),
                "updatedAt", LocalDateTime.now().toString());
    }

    private Map<String, Object> buildOrderNotification(Order order) {
        return Map.of(
                "type", "NEW_ORDER",
                "orderId", order.getId(),
                "trackingCode", order.getTrackingCode(),
                "totalPrice", order.getTotalPrice(),
                "deliveryFee", order.getDeliveryFee(),
                "commissionIfAccepted", order.getCommissionAmount(),
                "pickupAddress",
                order.getPickupAddress() != null
                        ? order.getPickupAddress() : "",
                "deliveryAddress",
                order.getDeliveryAddress() != null
                        ? order.getDeliveryAddress() : "");
    }

    private User getUser(Long userId) {
        return userRepository.findById(userId)
                .orElseThrow(() ->
                        new NotFoundException("User not found"));
    }
}