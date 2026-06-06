package com.faster.backend.service;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Random;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final UserRepository userRepository;
    private final LocationService locationService;
    private final SimpMessagingTemplate messagingTemplate;

    // ─── Commission rate: 20% ─────────────────────────
    private static final BigDecimal COMMISSION_RATE
        = new BigDecimal("0.20");

    // ─── Search radius: 5km ───────────────────────────
    private static final double SEARCH_RADIUS_KM = 5.0;

    // ─── CREATE ORDER (App Customer) ──────────────────
    @Transactional
    public Order createOrder(Long merchantId,
                             Long customerId,
                             BigDecimal totalPrice,
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

        // Calculate financials
        BigDecimal commission = totalPrice
            .multiply(COMMISSION_RATE)
            .setScale(2, RoundingMode.HALF_UP);

        Order order = Order.builder()
                .trackingCode(generateTrackingCode())
                .merchant(merchant)
                .customer(customer)
                .orderType(orderType)
                .status(Order.OrderStatus.PENDING)
                .totalPrice(totalPrice)
                .commissionAmount(commission)
                .driverPaysMerchant(totalPrice)
                .pickupLat(pickupLat)
                .pickupLng(pickupLng)
                .pickupAddress(pickupAddress)
                .deliveryLat(deliveryLat)
                .deliveryLng(deliveryLng)
                .deliveryAddress(deliveryAddress)
                .customerNotes(customerNotes)
                .build();

        Order saved = orderRepository.save(order);

        // Find and notify nearest drivers
        notifyNearestDrivers(saved, pickupLat,
            pickupLng, orderType);

        return saved;
    }

    // ─── CREATE O2O ORDER (Offline Customer) ──────────
    @Transactional
    public Order createO2OOrder(Long merchantId,
                                String offlinePhone,
                                String offlineLandmark,
                                BigDecimal totalPrice,
                                Double pickupLat,
                                Double pickupLng,
                                String pickupAddress) {

        User merchant = getUser(merchantId);

        BigDecimal commission = totalPrice
            .multiply(COMMISSION_RATE)
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
                .commissionAmount(commission)
                .driverPaysMerchant(totalPrice)
                .pickupLat(pickupLat)
                .pickupLng(pickupLng)
                .pickupAddress(pickupAddress)
                .deliveryAddress(offlineLandmark)
                .build();

        Order saved = orderRepository.save(order);

        // Notify nearest PACKAGE drivers
        notifyNearestDrivers(
            saved, pickupLat, pickupLng,
            Order.OrderType.LOGISTICS);

        // In production: send SMS/WhatsApp here
        // with tracking link
        System.out.println(
            "📱 Send SMS to " + offlinePhone +
            ": Track your order at " +
            "https://faster.app/track/" + trackingCode);

        return saved;
    }

    // ─── DRIVER ACCEPTS ORDER ─────────────────────────
    @Transactional
    public Order acceptOrder(Long driverId,
                             Long orderId) {

        Order order = orderRepository.findById(orderId)
            .orElseThrow(() ->
                new RuntimeException("Order not found"));

        if (order.getStatus() != Order.OrderStatus.PENDING) {
            throw new RuntimeException(
                "Order is no longer available");
        }

        User driver = getUser(driverId);

        order.setDriver(driver);
        order.setStatus(Order.OrderStatus.ACCEPTED);
        order.setAcceptedAt(LocalDateTime.now());

        Order saved = orderRepository.save(order);

        // Notify merchant via WebSocket
        messagingTemplate.convertAndSend(
            "/topic/merchant/" + order.getMerchant().getId(),
            buildStatusUpdate(saved));

        // Notify customer if app user
        if (order.getCustomer() != null) {
            messagingTemplate.convertAndSend(
                "/topic/order/" + orderId,
                buildStatusUpdate(saved));
        }

        return saved;
    }

    // ─── UPDATE ORDER STATUS ──────────────────────────
    @Transactional
    public Order updateStatus(Long orderId,
                              Order.OrderStatus newStatus,
                              Long requesterId) {

        Order order = orderRepository.findById(orderId)
            .orElseThrow(() ->
                new RuntimeException("Order not found"));

        // Only driver or merchant can update
        boolean isMerchant = order.getMerchant()
            .getId().equals(requesterId);
        boolean isDriver = order.getDriver() != null &&
            order.getDriver().getId().equals(requesterId);

        if (!isMerchant && !isDriver) {
            throw new RuntimeException(
                "Not authorized to update this order");
        }

        // Set timestamps based on status
        switch (newStatus) {
            case PICKED_UP ->
                order.setPickedUpAt(LocalDateTime.now());
            case DELIVERED -> {
                order.setDeliveredAt(LocalDateTime.now());
                // Add commission debt to driver
                addDriverDebt(order);
            }
            default -> {}
        }

        order.setStatus(newStatus);
        Order saved = orderRepository.save(order);

        // Broadcast status update via WebSocket
        messagingTemplate.convertAndSend(
            "/topic/order/" + orderId,
            buildStatusUpdate(saved));

        return saved;
    }

    // ─── TRACK ORDER (public — for offline customer) ──
    public Order trackOrder(String trackingCode) {
        return orderRepository
            .findByTrackingCode(trackingCode)
            .orElseThrow(() ->
                new RuntimeException(
                    "Order not found. " +
                    "Check your tracking code."));
    }

    // ─── GET MERCHANT ORDERS ──────────────────────────
    public List<Order> getMerchantOrders(
            Long merchantId) {
        return orderRepository
            .findByMerchantIdOrderByCreatedAtDesc(
                merchantId);
    }

    // ─── GET DRIVER ORDERS ────────────────────────────
    public List<Order> getDriverOrders(Long driverId) {
        return orderRepository
            .findByDriverIdOrderByCreatedAtDesc(driverId);
    }

    // ─── GET ACTIVE DRIVER ORDERS ─────────────────────
    public List<Order> getActiveDriverOrders(
            Long driverId) {
        return orderRepository
            .findActiveOrdersByDriver(driverId);
    }

    // ─── DISPUTE ORDER ────────────────────────────────
    @Transactional
    public Order disputeOrder(Long orderId,
                              String reason,
                              Long requesterId) {
        Order order = orderRepository.findById(orderId)
            .orElseThrow(() ->
                new RuntimeException("Order not found"));

        order.setStatus(Order.OrderStatus.DISPUTED);
        order.setDisputeReason(reason);

        Order saved = orderRepository.save(order);

        // Notify both merchant and driver
        messagingTemplate.convertAndSend(
            "/topic/merchant/" +
            order.getMerchant().getId(),
            buildStatusUpdate(saved));

        return saved;
    }

    // ─── Add commission debt to driver ───────────────
    private void addDriverDebt(Order order) {
        if (order.getDriver() == null) return;

        User driver = order.getDriver();
        BigDecimal newDebt = driver.getDebtAmount()
            .add(order.getCommissionAmount());
        driver.setDebtAmount(newDebt);

        // Auto-block if debt >= $20
        if (newDebt.compareTo(new BigDecimal("20")) >= 0) {
            driver.setIsBlocked(true);
            System.out.println(
                "🚫 Driver " + driver.getId() +
                " blocked. Debt: $" + newDebt);
        }

        userRepository.save(driver);
    }

    // ─── Notify nearest drivers via WebSocket ─────────
    private void notifyNearestDrivers(
            Order order,
            Double pickupLat,
            Double pickupLng,
            Order.OrderType orderType) {

        if (pickupLat == null || pickupLng == null)
            return;

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

        // Ping each nearby driver
        nearbyDrivers.forEach(driverId ->
            messagingTemplate.convertAndSend(
                "/topic/driver/" + driverId,
                buildOrderNotification(order)));

        System.out.println(
            "📡 Pinged " + nearbyDrivers.size() +
            " drivers for order " +
            order.getTrackingCode());
    }

    // ─── Generate unique tracking code ───────────────
    private String generateTrackingCode() {
        String date = LocalDateTime.now()
            .format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String random = String.format("%04X",
            new Random().nextInt(0xFFFF));
        return "FST-" + date + "-" + random;
    }

    // ─── Build WebSocket status update payload ────────
    private java.util.Map<String, Object>
            buildStatusUpdate(Order order) {
        return java.util.Map.of(
            "orderId", order.getId(),
            "trackingCode", order.getTrackingCode(),
            "status", order.getStatus(),
            "updatedAt", LocalDateTime.now()
        );
    }

    // ─── Build new order notification for driver ──────
    private java.util.Map<String, Object>
            buildOrderNotification(Order order) {
        return java.util.Map.of(
            "type", "NEW_ORDER",
            "orderId", order.getId(),
            "trackingCode", order.getTrackingCode(),
            "totalPrice", order.getTotalPrice(),
            "pickupAddress",
                order.getPickupAddress() != null
                ? order.getPickupAddress() : "",
            "deliveryAddress",
                order.getDeliveryAddress() != null
                ? order.getDeliveryAddress() : ""
        );
    }

    // ─── Helper ───────────────────────────────────────
    private User getUser(Long userId) {
        return userRepository.findById(userId)
            .orElseThrow(() ->
                new RuntimeException("User not found"));
    }
}