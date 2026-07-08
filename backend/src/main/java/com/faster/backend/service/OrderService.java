package com.faster.backend.service;

import com.faster.backend.dto.OrderItemLineRequest;
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
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final UserRepository userRepository;
    private final LocationService locationService;
    private final SimpMessagingTemplate messagingTemplate;
    private final LedgerService ledgerService;
    private final CommunicationService communicationService;
    // FIX (C2): all money now flows through PricingService instead
    // of being trusted from the client request.
    private final PricingService pricingService;

    private static final BigDecimal DRIVER_COMMISSION_RATE =
            new BigDecimal("0.20");
    private static final BigDecimal MERCHANT_COMMISSION_RATE =
            new BigDecimal("0.10");
    private static final double SEARCH_RADIUS_KM = 5.0;

    // ─────────────────────────────────────────────────
    // QUOTE — lets the customer app show the real price
    // BEFORE placing the order. Nothing is persisted here.
    // The actual order creation below recomputes from
    // scratch regardless — this is a display convenience,
    // never a trusted input.
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
    // FIX (C2): totalPrice/deliveryFee are no longer
    // parameters — they're computed here from the
    // merchant's own catalog and real distance.
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

        // ─── Server-computed pricing (never client input) ──
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

        // Bonus fix found while wiring in PricingService: stock was
        // never actually decremented anywhere in the order flow.
        // ItemService.decrementStock() existed but nothing called it.
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
    // FIX (C2): rideFee is no longer a parameter — it's
    // computed from real pickup→destination distance.
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
    // FIX (C2): totalPrice/deliveryFee removed as params.
    // A merchant can no longer under-report the sale total
    // to dodge the 10% commission — items are priced from
    // their own catalog exactly like app orders.
    //
    // deliveryLat/deliveryLng are optional here: Flow 1
    // (merchant pins the exact map location) has them and
    // gets a real distance-based fee; Flow 2 (WhatsApp
    // bridge link, customer shares location later) does not
    // yet, so PricingService falls back to the minimum fee
    // until the location is confirmed. This is a known,
    // intentional limitation — not a silent gap.
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

        // Send WhatsApp/SMS tracking link to offline customer
        // CommunicationService handles Twilio/Vonage routing
        // Never blocks order creation — failures are logged only
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
    // Atomic update prevents double-accept race condition
    // For O2O: sends driver-assigned SMS to offline customer
    // ─────────────────────────────────────────────────
    @Transactional
    public Order acceptOrder(Long driverId, Long orderId) {

        User driver = getUser(driverId);

        if (Boolean.TRUE.equals(driver.getIsBlocked())) {
            throw new RuntimeException(
                    "Your account is blocked. " +
                    "Settle your commission debt via OMT or WishMoney, " +
                    "then contact admin to reactivate.");
        }

        int updated = orderRepository.assignDriver(
                orderId, driverId, LocalDateTime.now());

        if (updated == 0) {
            throw new RuntimeException(
                    "Order is no longer available — " +
                    "another driver already accepted it.");
        }

        Order saved = orderRepository.findById(orderId)
                .orElseThrow(() ->
                        new RuntimeException("Order not found"));

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
    // ─────────────────────────────────────────────────
    @Transactional
    public Order updateStatus(Long orderId,
            Order.OrderStatus newStatus,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() ->
                        new RuntimeException("Order not found"));

        boolean isMerchant = order.getMerchant() != null &&
                order.getMerchant().getId().equals(requesterId);
        boolean isDriver = order.getDriver() != null &&
                order.getDriver().getId().equals(requesterId);

        if (!isMerchant && !isDriver) {
            throw new RuntimeException(
                    "Not authorized to update this order");
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
    // ─────────────────────────────────────────────────
    @Transactional
    public Order disputeOrder(Long orderId,
            String reason,
            Long requesterId) {

        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() ->
                        new RuntimeException("Order not found"));

        boolean isParty =
                (order.getMerchant() != null &&
                        order.getMerchant().getId().equals(requesterId))
                || (order.getDriver() != null &&
                        order.getDriver().getId().equals(requesterId))
                || (order.getCustomer() != null &&
                        order.getCustomer().getId().equals(requesterId));

        if (!isParty) {
            throw new RuntimeException(
                    "Not authorized to dispute this order");
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
                .orElseThrow(() -> new RuntimeException(
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
                        new RuntimeException("User not found"));
    }
}