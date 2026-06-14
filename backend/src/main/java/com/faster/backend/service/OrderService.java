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
import java.util.Map;
import java.util.Random;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final UserRepository userRepository;
    private final LocationService locationService;
    private final SimpMessagingTemplate messagingTemplate;

    // ─── Commission rates ─────────────────────────────
    // Driver: 20% of delivery fee per order
    private static final BigDecimal DRIVER_COMMISSION_RATE = new BigDecimal("0.20");

    // Merchant: 10% of daily sales (per order stored)
    private static final BigDecimal MERCHANT_COMMISSION_RATE = new BigDecimal("0.10");

    // ─── Search radius ────────────────────────────────
    private static final double SEARCH_RADIUS_KM = 5.0;

    // ─────────────────────────────────────────────────
    // CREATE STANDARD ORDER (App Customer)
    // ─────────────────────────────────────────────────
    @Transactional
    public Order createOrder(Long merchantId,
            Long customerId,
            BigDecimal totalPrice,
            BigDecimal deliveryFee,
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

        // ─── Calculate all financial fields ──────────
        BigDecimal actualDeliveryFee = deliveryFee != null
                ? deliveryFee.setScale(2, RoundingMode.HALF_UP)
                : BigDecimal.ZERO;

        // Driver commission = 20% of delivery fee only
        BigDecimal driverCommission = actualDeliveryFee
                .multiply(DRIVER_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        // Grand total = product price + delivery fee
        BigDecimal grandTotal = totalPrice
                .add(actualDeliveryFee)
                .setScale(2, RoundingMode.HALF_UP);

        // Merchant daily commission = 10% of product price
        // Stored per order for daily aggregation
        BigDecimal merchantCommission = totalPrice
                .multiply(MERCHANT_COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);

        Order order = Order.builder()
                .trackingCode(generateTrackingCode())
                .merchant(merchant)
                .customer(customer)
                .orderType(orderType != null
                        ? orderType
                        : Order.OrderType.LOGISTICS)
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

        // Find and notify nearest drivers
        notifyNearestDrivers(
                saved, pickupLat, pickupLng,
                saved.getOrderType());

        return saved;
    }

    // ─────────────────────────────────────────────────
    // CREATE O2O ORDER (Offline Customer)
    // Merchant creates for customer who called by phone
    // ─────────────────────────────────────────────────
    @Transactional
    public Order createO2OOrder(Long merchantId,
            String offlinePhone,
            String offlineLandmark,
            BigDecimal totalPrice,
            BigDecimal deliveryFee,
            Double pickupLat,
            Double pickupLng,
            String pickupAddress) {

        User merchant = getUser(merchantId);

        BigDecimal actualDeliveryFee = deliveryFee != null
                ? deliveryFee.setScale(2, RoundingMode.HALF_UP)
                : BigDecimal.ZERO;

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
                .deliveryAddress(offlineLandmark)
                .build();

        Order saved = orderRepository.save(order);

        // Notify nearest PACKAGE drivers
        notifyNearestDrivers(
                saved, pickupLat, pickupLng,
                Order.OrderType.LOGISTICS);

        // Log SMS (production: integrate SMS gateway)
        System.out.println(
                "📱 SMS → " + offlinePhone +
                        " | Track: https://faster.app/track/"
                        + trackingCode);

        return saved;
    }

    // ─────────────────────────────────────────────────
    // DRIVER ACCEPTS ORDER
    // ─────────────────────────────────────────────────
    @Transactional
    public Order acceptOrder(Long driverId,
            Long orderId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() -> new RuntimeException("Order not found"));

        if (order.getStatus() != Order.OrderStatus.PENDING) {
            throw new RuntimeException(
                    "Order is no longer available");
        }

        User driver = getUser(driverId);

        // Check driver is not blocked
        if (Boolean.TRUE.equals(driver.getIsBlocked())) {
            throw new RuntimeException(
                    "Your account is blocked. Please " +
                            "settle your commission debt first.");
        }

        order.setDriver(driver);
        order.setStatus(Order.OrderStatus.ACCEPTED);
        order.setAcceptedAt(LocalDateTime.now());

        Order saved = orderRepository.save(order);

        // Notify merchant
        messagingTemplate.convertAndSend(
                "/topic/merchant/" +
                        order.getMerchant().getId(),
                buildStatusUpdate(saved));

        // Notify customer if app user
        if (order.getCustomer() != null) {
            messagingTemplate.convertAndSend(
                    "/topic/order/" + orderId,
                    buildStatusUpdate(saved));
        }

        return saved;
    }

    // ─────────────────────────────────────────────────
    // UPDATE ORDER STATUS
    // ─────────────────────────────────────────────────
    @Transactional
    public Order updateStatus(Long orderId,
            Order.OrderStatus newStatus,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() -> new RuntimeException("Order not found"));

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
                // LedgerService handles full ledger entry
                addDriverDebt(order);
            }
            default -> {
            }
        }

        order.setStatus(newStatus);
        Order saved = orderRepository.save(order);

        // Broadcast to all parties via WebSocket
        messagingTemplate.convertAndSend(
                "/topic/order/" + orderId,
                buildStatusUpdate(saved));

        // Also notify merchant
        messagingTemplate.convertAndSend(
                "/topic/merchant/" +
                        order.getMerchant().getId(),
                buildStatusUpdate(saved));

        return saved;
    }

    // ─────────────────────────────────────────────────
    // DISPUTE ORDER
    // ─────────────────────────────────────────────────
    @Transactional
    public Order disputeOrder(Long orderId,
            String reason,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() -> new RuntimeException("Order not found"));

        order.setStatus(Order.OrderStatus.DISPUTED);
        order.setDisputeReason(reason);

        Order saved = orderRepository.save(order);

        // Notify merchant and admin via WebSocket
        messagingTemplate.convertAndSend(
                "/topic/merchant/" +
                        order.getMerchant().getId(),
                buildStatusUpdate(saved));

        messagingTemplate.convertAndSend(
                "/topic/admin/disputes",
                buildStatusUpdate(saved));

        return saved;
    }

    // ─────────────────────────────────────────────────
    // TRACK ORDER (public — offline customer)
    // ─────────────────────────────────────────────────
    public Order trackOrder(String trackingCode) {
        return orderRepository
                .findByTrackingCode(trackingCode)
                .orElseThrow(() -> new RuntimeException(
                        "Order not found. " +
                                "Check your tracking code."));
    }

    // ─────────────────────────────────────────────────
    // GET ORDERS
    // ─────────────────────────────────────────────────
    public List<Order> getMerchantOrders(
            Long merchantId) {
        return orderRepository
                .findByMerchantIdOrderByCreatedAtDesc(
                        merchantId);
    }

    public List<Order> getDriverOrders(Long driverId) {
        return orderRepository
                .findByDriverIdOrderByCreatedAtDesc(driverId);
    }

    public List<Order> getActiveDriverOrders(
            Long driverId) {
        return orderRepository
                .findActiveOrdersByDriver(driverId);
    }

    public List<Order> getActiveMerchantOrders(
            Long merchantId) {
        return orderRepository
                .findActiveOrdersByMerchant(merchantId);
    }

    // ─────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────

    // Add driver commission debt on delivery
    private void addDriverDebt(Order order) {
        if (order.getDriver() == null)
            return;

        User driver = order.getDriver();
        BigDecimal newDebt = driver.getDebtAmount()
                .add(order.getCommissionAmount())
                .setScale(2, RoundingMode.HALF_UP);

        driver.setDebtAmount(newDebt);
        userRepository.save(driver);

        // Notify driver of commission recorded
        messagingTemplate.convertAndSend(
                "/topic/driver/" + driver.getId(),
                Map.of(
                        "type", "COMMISSION_RECORDED",
                        "message", "Commission $" + order.getCommissionAmount()
                                + " recorded for order "
                                + order.getTrackingCode()
                                + ". Total debt: $" + newDebt,
                        "commissionAmount", order.getCommissionAmount(),
                        "totalDebt", newDebt));
    }

    // Ping nearest drivers via WebSocket
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

        nearbyDrivers.forEach(driverId -> messagingTemplate.convertAndSend(
                "/topic/driver/" + driverId,
                buildOrderNotification(order)));

        System.out.println(
                "📡 Pinged " + nearbyDrivers.size() +
                        " drivers for order " +
                        order.getTrackingCode());
    }

    // Generate unique tracking code FST-YYYYMMDD-XXXX
    private String generateTrackingCode() {
        String date = LocalDateTime.now()
                .format(DateTimeFormatter
                        .ofPattern("yyyyMMdd"));
        String random = String.format("%04X",
                new Random().nextInt(0xFFFF));
        return "FST-" + date + "-" + random;
    }

    // Build WebSocket status update payload
    private Map<String, Object> buildStatusUpdate(
            Order order) {
        return Map.of(
                "type", "STATUS_UPDATE",
                "orderId", order.getId(),
                "trackingCode", order.getTrackingCode(),
                "status", order.getStatus(),
                "updatedAt", LocalDateTime.now().toString());
    }

    // Build new order notification for driver
    private Map<String, Object> buildOrderNotification(
            Order order) {
        return Map.of(
                "type", "NEW_ORDER",
                "orderId", order.getId(),
                "trackingCode", order.getTrackingCode(),
                "totalPrice", order.getTotalPrice(),
                "deliveryFee", order.getDeliveryFee(),
                "commissionIfAccepted",
                order.getCommissionAmount(),
                "pickupAddress",
                order.getPickupAddress() != null
                        ? order.getPickupAddress()
                        : "",
                "deliveryAddress",
                order.getDeliveryAddress() != null
                        ? order.getDeliveryAddress()
                        : "");
    }

    private User getUser(Long userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
    }
}